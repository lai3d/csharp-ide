import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct EditorConfigTests {
    @Test func matchesGlobs() {
        #expect(EditorConfig.matches("*", relativePath: "a/b/C.cs"))
        #expect(EditorConfig.matches("*.cs", relativePath: "src/C.cs"))
        #expect(!EditorConfig.matches("*.cs", relativePath: "src/C.csx"))
        #expect(EditorConfig.matches("*.{cs,vb}", relativePath: "x/Y.vb"))
        #expect(EditorConfig.matches("{*.csproj,*.props}", relativePath: "Directory.Build.props"))
        #expect(EditorConfig.matches("src/**.cs", relativePath: "src/a/b/C.cs"))
        #expect(!EditorConfig.matches("src/*.cs", relativePath: "src/a/C.cs"))
        #expect(EditorConfig.matches("/tests/**/*.cs", relativePath: "tests/T.cs"))
        #expect(EditorConfig.matches("[Cc]alc.cs", relativePath: "calc.cs"))
        #expect(!EditorConfig.matches("[!C]alc.cs", relativePath: "Calc.cs"))
    }

    @Test func resolvesNearestFilesAndRoot() {
        let files: [String: String] = [
            "/.editorconfig": "[*]\nindent_size = 8\n",  // above root = true: ignored
            "/w/.editorconfig": """
                # top
                root = true

                [*]
                indent_style = space
                indent_size = 4
                end_of_line = lf

                [*.cs]
                indent_size = 2 ; two for C#
                csharp_new_line_before_open_brace = all
                """,
            "/w/legacy/.editorconfig": "[*.cs]\nindent_style = tab\nindent_size = tab\ntab_width = 3\n",
        ]
        let read = { (url: URL) in files[url.path] }
        let props = EditorConfig.properties(for: URL(fileURLWithPath: "/w/src/A.cs"), read: read)
        #expect(props["indent_size"] == "2" && props["end_of_line"] == "lf")
        #expect(EditorConfig.indentation(for: URL(fileURLWithPath: "/w/src/A.cs"), read: read)
            == .init(insertSpaces: true, size: 2))
        #expect(EditorConfig.indentation(for: URL(fileURLWithPath: "/w/README.md"), read: read)
            == .init(insertSpaces: true, size: 4))
        #expect(EditorConfig.indentation(for: URL(fileURLWithPath: "/w/legacy/Old.cs"), read: read)
            == .init(insertSpaces: false, size: 3))
        #expect(EditorConfig.indentation(for: URL(fileURLWithPath: "/elsewhere/A.cs")) { _ in nil }
            == .init(insertSpaces: nil, size: nil))
    }

    /// csharp-ls applies .editorconfig style rules (brace placement) itself; indentation comes
    /// from the formatting options, which the IDE fills from .editorconfig.
    @Test(.enabled(if: CSharpLSFixture.isAvailable), .timeLimit(.minutes(2)))
    func csharpLSFollowsEditorConfigStyle() async throws {
        let source = "namespace T;\npublic class C\n{\npublic int X()\n{\nreturn 1;\n}\n}\n"
        let fixture = try await CSharpLSFixture(files: [
            ".editorconfig": "root = true\n[*.cs]\nindent_style = tab\ncsharp_new_line_before_open_brace = none\n",
            "C.cs": source,
        ], name: "editorconfig")
        try fixture.open("C.cs")
        let indentation = EditorConfig.indentation(for: fixture.url("C.cs"))
        #expect(indentation.insertSpaces == false)
        let result = try await fixture.poll("textDocument/formatting", [
            "textDocument": ["uri": fixture.uri("C.cs")],
            "options": ["tabSize": 4, "insertSpaces": .bool(indentation.insertSpaces ?? true)],
        ]) { $0.arrayValue?.isEmpty == false }
        let formatted = TextEdit.apply(result.arrayValue?.compactMap(TextEdit.parse) ?? [], to: source)
        #expect(formatted == "namespace T;\n\npublic class C {\n\tpublic int X() {\n\t\treturn 1;\n\t}\n}\n", "\(formatted)")
        await fixture.shutdown()
    }
}
