import Foundation
import Testing
@testable import CSharpIDE
import CSharpIDECore

@MainActor
@Suite struct WorkspaceTabTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.cs", "b.cs", "c.cs"] {
            try "package main\n".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    @Test func openingTheSameFileReusesItsTab() {
        let workspace = Workspace()
        let first = workspace.openFile(url("a.cs"))
        workspace.openFile(url("b.cs"))
        let again = workspace.openFile(url("a.cs"))
        #expect(first === again)
        #expect(workspace.documents.map(\.name) == ["a.cs", "b.cs"])
        #expect(workspace.activeDocument === first)
    }

    @Test func newTabsOpenNextToTheActiveOne() {
        let workspace = Workspace()
        let a = workspace.openFile(url("a.cs"))!
        workspace.openFile(url("b.cs"))
        workspace.activate(a)
        workspace.openFile(url("c.cs"))
        #expect(workspace.documents.map(\.name) == ["a.cs", "c.cs", "b.cs"])
    }

    @Test func closingTheActiveTabSelectsItsNeighbour() {
        let workspace = Workspace()
        workspace.openFile(url("a.cs"))
        let b = workspace.openFile(url("b.cs"))!
        workspace.openFile(url("c.cs"))
        workspace.activate(b)
        workspace.closeDocument(b)
        #expect(workspace.documents.map(\.name) == ["a.cs", "c.cs"])
        #expect(workspace.activeDocument?.name == "c.cs")
        workspace.closeAllDocuments()
        #expect(workspace.documents.isEmpty && workspace.activeDocument == nil)
    }

    @Test func cyclesTabs() {
        let workspace = Workspace()
        workspace.openFile(url("a.cs"))
        workspace.openFile(url("b.cs"))
        workspace.selectAdjacentTab(1)
        #expect(workspace.activeDocument?.name == "a.cs")
        workspace.selectAdjacentTab(-1)
        #expect(workspace.activeDocument?.name == "b.cs")
    }

    @Test func editsMarkDirtyAndSaveWritesToDisk() throws {
        let workspace = Workspace()
        let a = workspace.openFile(url("a.cs"))!
        workspace.updateText(of: a, to: "package main\n\nfunc x() {}\n")
        #expect(a.isDirty)
        workspace.save(a)
        #expect(!a.isDirty)
        #expect(try String(contentsOf: url("a.cs"), encoding: .utf8).contains("func x()"))
    }
}

@MainActor
@Suite struct WorkspaceFormattingTests {
}

@MainActor
@Suite struct WorkspaceFileSystemTests {
    let dir: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pkg"), withIntermediateDirectories: true)
        dir = base.canonicalFileURL  // real path, as FSEvents reports it
        try "module example.com/fs\n\ngo 1.22\n".write(to: dir.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        try "package main\n\nfunc main() {}\n".write(to: dir.appendingPathComponent("Program.cs"), atomically: true, encoding: .utf8)
        try "package widgets\n".write(to: dir.appendingPathComponent("pkg/a.cs"), atomically: true, encoding: .utf8)
    }

    private func url(_ path: String) -> URL { dir.appendingPathComponent(path) }

    @Test func reloadsCleanDocumentsAndFlagsDirtyOnes() async throws {
        let workspace = Workspace()
        await workspace.openFolder(dir.canonicalFileURL)
        let main = try #require(workspace.activeDocument)
        let other = try #require(workspace.openFile(url("pkg/a.cs")))
        workspace.updateText(of: other, to: "package widgets // edited\n")

        try "package main\n\nfunc main() { println() }\n".write(to: url("Program.cs"), atomically: true, encoding: .utf8)
        try "package widgets // external\n".write(to: url("pkg/a.cs"), atomically: true, encoding: .utf8)
        workspace.handleFileSystemChanges([url("Program.cs").path, url("pkg/a.cs").path])

        #expect(main.text.contains("println()") && !main.isDirty)
        #expect(other.text.contains("edited") && other.hasExternalChange)
        workspace.reloadFromDisk(other)
        #expect(other.text.contains("external") && !other.isDirty && !other.hasExternalChange)
    }

    @Test func createsRenamesAndTrashes() async throws {
        let workspace = Workspace()
        await workspace.openFolder(dir.canonicalFileURL)

        try "<Project Sdk=\"Microsoft.NET.Sdk\" />\n".write(to: url("My.App.csproj"), atomically: true, encoding: .utf8)
        let created = try workspace.createFile(named: "Widget.cs", in: url("pkg"))
        #expect(try String(contentsOf: created, encoding: .utf8) == "namespace My.App.pkg;\n\npublic class Widget\n{\n}\n")
        #expect(workspace.activeDocument?.name == "Widget.cs")
        #expect(throws: FileOperationError.self) { try workspace.createFile(named: "Widget.cs", in: url("pkg")) }

        let renamed = try workspace.renameItem(at: url("pkg"), to: "widgets")
        #expect(workspace.activeDocument?.url.path == renamed.appendingPathComponent("Widget.cs").path)
        #expect(workspace.fileTree.contains { $0.name == "widgets" })

        try workspace.trashItem(at: renamed)
        #expect(!workspace.documents.contains { $0.name == "Widget.cs" })
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test func derivesNamespaces() throws {
        try FileManager.default.createDirectory(at: url("src/My-Lib/Models"), withIntermediateDirectories: true)
        #expect(Workspace.namespaceName(for: url("src/My-Lib/Models")) == nil)  // no project
        try "<Project><PropertyGroup><RootNamespace>Acme.Lib</RootNamespace></PropertyGroup></Project>"
            .write(to: url("src/My-Lib/Lib.csproj"), atomically: true, encoding: .utf8)
        #expect(Workspace.namespaceName(for: url("src/My-Lib/Models")) == "Acme.Lib.Models")
        #expect(Workspace.namespaceName(for: url("src/My-Lib")) == "Acme.Lib")
        #expect(Workspace.identifier("2-fast") == "_2_fast")
        #expect(Workspace.newClassTemplate(for: url("Loose.cs")) == "public class Loose\n{\n}\n")
    }
}

@MainActor
@Suite struct WorkspaceSearchTests {
    @Test func searchesProjectIncludingUnsavedBuffers() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-ws-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "package main\n\nfunc main() { greet() }\n".write(to: dir.appendingPathComponent("Program.cs"), atomically: true, encoding: .utf8)
        try "package main\n\nfunc greet() {}\n".write(to: dir.appendingPathComponent("greet.cs"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        workspace.searchQuery = "greet"
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 2)

        // Edit greet.cs without saving: the search sees the buffer.
        let greet = try #require(workspace.openFile(dir.appendingPathComponent("greet.cs")))
        workspace.updateText(of: greet, to: "package main\n\nfunc greet() {}\nfunc greetAgain() {}\n")
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 3)

        let file = try #require(workspace.searchResults.first { $0.path.hasSuffix("Program.cs") })
        workspace.open(file.matches[0], in: file)
        #expect(workspace.activeDocument?.name == "Program.cs")
        #expect(workspace.activeDocument?.revealTarget?.position == TextPosition(line: 2, character: 14))
        #expect(workspace.activeDocument?.revealTarget?.length == 5)

        workspace.searchOptions.regex = true
        workspace.searchQuery = "("
        await workspace.performSearch()
        #expect(workspace.searchError != nil && workspace.searchResults.isEmpty)
    }
}

@MainActor
@Suite struct WorkspaceReferencesTests {
}

@MainActor
@Suite struct WorkspaceRenameTests {
}

@MainActor
@Suite struct WorkspaceCodeActionTests {
}

@MainActor
@Suite struct WorkspaceNavigationTests {
}

@MainActor
@Suite struct WorkspaceGitTests {
    @Test(.enabled(if: CSharpIDECore.ToolLocator.find("git") != nil), .timeLimit(.minutes(1)))
    func tracksBranchStatusesAndBases() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-ws-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        Git.run(["init", "-q", "-b", "feature"], in: dir)
        try "module example.com/g\n\ngo 1.22\n".write(to: dir.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        try "package main\n\nfunc main() {}\n".write(to: dir.appendingPathComponent("Program.cs"), atomically: true, encoding: .utf8)
        Git.run(["add", "."], in: dir)
        Git.run(["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init"], in: dir)
        try "package main\n\n// changed\nfunc main() {}\n".write(to: dir.appendingPathComponent("Program.cs"), atomically: true, encoding: .utf8)
        try "package main\n".write(to: dir.appendingPathComponent("new.cs"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        for _ in 0..<50 where workspace.gitBranch == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(workspace.gitBranch == "feature")
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("Program.cs")) == .modified)
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("new.cs")) == .untracked)
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("go.mod")) == nil)
        let main = try #require(workspace.activeDocument)
        #expect(workspace.gitBase(for: main) == "package main\n\nfunc main() {}\n")
        let changes = LineChanges.compute(base: workspace.gitBase(for: main)!, current: main.text)
        #expect(changes.lines == [2: .added])
    }
}

@MainActor
@Suite(.serialized) struct SessionRestoreTests {
    @Test func restoresTabsAndRecents() async throws {
        let suite = "csharpide-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        SessionStore.defaults = defaults
        defer {
            SessionStore.defaults = .standard
            defaults.removePersistentDomain(forName: suite)
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        for name in ["Program.cs", "a.cs", "b.cs"] {
            try "package main\n".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let first = Workspace()
        await first.openFolder(dir)
        #expect(first.documents.map(\.name) == ["Program.cs"])  // nothing saved yet: default file
        first.openFile(dir.appendingPathComponent("a.cs"))
        first.openFile(dir.appendingPathComponent("b.cs"))
        first.activate(first.documents[1])  // a.cs
        await first.shutdown()

        let second = Workspace()
        await second.openFolder(dir)
        #expect(second.documents.map(\.name) == ["Program.cs", "a.cs", "b.cs"])
        #expect(second.activeDocument?.name == "a.cs")
        #expect(SessionStore.recentProjects.first?.path == dir.path)
        await second.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceReplaceTests {
    @Test func replacesInOpenBuffersAndOnDisk() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "package main\n\nfunc main() { getUser(); getName() }\n".write(to: dir.appendingPathComponent("Program.cs"), atomically: true, encoding: .utf8)
        let other = dir.appendingPathComponent("other.cs")
        try "package main\n\nfunc getUser() {}\nfunc getName() {}\n".write(to: other, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let main = try #require(workspace.activeDocument)
        workspace.searchOptions = SearchOptions(regex: true)
        workspace.searchQuery = #"get(\w+)\("#
        workspace.replaceQuery = "fetch$1("
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 4)

        // One match first: the second call in Program.cs (still in the buffer).
        let mainResult = try #require(workspace.searchResults.first { $0.path.hasSuffix("Program.cs") })
        await workspace.replace(mainResult.matches[1], in: mainResult)
        #expect(main.text.contains("getUser(); fetchName()") && main.isDirty)

        #expect(await workspace.replaceAllInProject() == 3)
        #expect(main.text.contains("fetchUser(); fetchName()"))
        #expect(try String(contentsOf: other, encoding: .utf8) == "package main\n\nfunc fetchUser() {}\nfunc fetchName() {}\n")
        #expect(workspace.searchMatchCount == 0)
    }
}

@MainActor
@Suite struct WorkspaceImplementationTests {
}
