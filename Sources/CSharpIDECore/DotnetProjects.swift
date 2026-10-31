import Foundation

/// One MSBuild project (`.csproj` / `.fsproj` / `.vbproj`) in the workspace.
public struct DotnetProject: Sendable, Hashable, Identifiable {
    /// Path relative to the workspace root, e.g. `src/App/App.csproj`.
    public let path: String
    public let name: String
    /// Builds a runnable app (OutputType Exe/WinExe, or the Web / Worker SDKs).
    public let isExecutable: Bool
    /// A test project (Microsoft.NET.Test.Sdk, xUnit / NUnit / MSTest, or IsTestProject).
    public let isTest: Bool
    public let targetFrameworks: [String]

    public var id: String { path }
    /// Runnable and not a test project (xUnit v3 / MSTest runner test projects are Exe too).
    public var isRunnable: Bool { isExecutable && !isTest }
    /// The folder holding the project, relative to the root ("." for the root).
    public var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "." : dir
    }

    public init(path: String, name: String, isExecutable: Bool, isTest: Bool, targetFrameworks: [String]) {
        self.path = path
        self.name = name
        self.isExecutable = isExecutable
        self.isTest = isTest
        self.targetFrameworks = targetFrameworks
    }
}

public enum DotnetProjects {
    public static let projectExtensions: Set<String> = ["csproj", "fsproj", "vbproj"]
    public static let solutionExtensions: Set<String> = ["sln", "slnx"]

    /// Every project under `root`, sorted by path.
    public static func find(under root: URL) -> [DotnetProject] {
        let rootPath = root.canonicalFileURL.path
        return ProjectSearch.files(under: root)
            .filter { projectExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .compactMap { path -> DotnetProject? in
                guard let xml = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
                return parse(xml: xml, path: relative)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Reads the bits of a project file the IDE needs (no MSBuild evaluation: imports and
    /// conditions are ignored, which is right for the common SDK-style project).
    public static func parse(xml: String, path: String) -> DotnetProject {
        let sdk = attribute("Sdk", ofFirst: "Project", in: xml) ?? ""
        let outputType = (property("OutputType", in: xml) ?? "").lowercased()
        let isWebOrWorker = sdk.contains("Microsoft.NET.Sdk.Web") || sdk.contains("Microsoft.NET.Sdk.Worker")
            || sdk.contains("Microsoft.NET.Sdk.BlazorWebAssembly") || sdk.contains("Aspire.AppHost")
        let isExecutable = outputType == "exe" || outputType == "winexe" || (outputType.isEmpty && isWebOrWorker)
        let lowered = xml.lowercased()
        let isTest = property("IsTestProject", in: xml)?.lowercased() == "true"
            || sdk.contains("MSTest.Sdk")
            || ["\"microsoft.net.test.sdk\"", "\"xunit\"", "\"xunit.v3\"", "\"nunit\"", "\"mstest\"",
                "\"mstest.testframework\"", "\"tunit\""].contains { lowered.contains("include=\($0)") }
        let frameworks = (property("TargetFrameworks", in: xml) ?? property("TargetFramework", in: xml) ?? "")
            .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return DotnetProject(path: path, name: name, isExecutable: isExecutable, isTest: isTest,
                             targetFrameworks: frameworks)
    }

    /// Solutions under `root` (relative paths), shallowest first.
    public static func solutions(under root: URL) -> [String] {
        let rootPath = root.canonicalFileURL.path
        return ProjectSearch.files(under: root)
            .filter { solutionExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { $0.hasPrefix(rootPath + "/") ? String($0.dropFirst(rootPath.count + 1)) : $0 }
            .sorted { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }
    }

    /// What `dotnet build` / `dotnet test` should be pointed at: the shallowest solution, else
    /// the only project, else nil (then dotnet looks in the working directory itself).
    public static func buildTarget(solutions: [String], projects: [DotnetProject]) -> String? {
        if let solution = solutions.first { return solution }
        if projects.count == 1 { return projects[0].path }
        return nil
    }

    /// A `.slnx` listing every project (absolute paths), for folders that have several projects
    /// but no solution, so build / test / clean still run as one command.
    public static func generatedSolution(root: URL, projects: [DotnetProject]) -> String {
        let escape = { (s: String) in
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
        }
        let lines = projects.map { "  <Project Path=\"\(escape(root.appendingPathComponent($0.path).path))\" />" }
        return "<Solution>\n" + lines.joined(separator: "\n") + "\n</Solution>\n"
    }

    /// Where the generated solution for `root` lives: a stable name under `directory`.
    public static func generatedSolutionURL(root: URL, in directory: URL) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325  // FNV-1a: stable across launches, unlike hashValue
        for byte in root.path.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return directory.appendingPathComponent("\(root.lastPathComponent)-\(String(hash, radix: 16)).slnx")
    }

    private static func property(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ name: String, ofFirst element: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(element)"),
              let end = xml.range(of: ">", range: start.upperBound..<xml.endIndex) else { return nil }
        let tag = xml[start.upperBound..<end.lowerBound]
        guard let attr = tag.range(of: "\(name)=\"") ,
              let quote = tag.range(of: "\"", range: attr.upperBound..<tag.endIndex) else { return nil }
        return String(tag[attr.upperBound..<quote.lowerBound])
    }
}

/// Compiler output references: MSBuild `File.cs(12,5): error CS0103: … [Proj.csproj]`,
/// plus the `File.cs:line 12` / `File.cs:12` forms stack traces and test runners print.
public enum BuildOutput {
    public struct Reference: Sendable, Hashable {
        public let range: NSRange
        public let file: String
        /// One-based.
        public let line: Int
        /// One-based, when known.
        public let column: Int?
    }

    public struct Problem: Sendable, Hashable {
        public let file: String
        public let line: Int
        public let column: Int
        public let severity: Diagnostic.Severity
        public let code: String
        public let message: String
    }

    private static let referenceRegex = try! NSRegularExpression(pattern:
        #"((?:[A-Za-z]:)?[\w./\\-]*?[\w-]+\.(?:cs|csx|fs|vb|razor|cshtml|csproj|props|targets|sln|xaml))(?:\((\d+),(\d+)(?:,\d+,\d+)?\)|:line (\d+)|:(\d+)(?::(\d+))?)"#)

    private static let problemRegex = try! NSRegularExpression(pattern:
        #"^\s*(.+?)\((\d+),(\d+)(?:,\d+,\d+)?\)\s*:\s*(error|warning)\s+([A-Za-z]+\d+)\s*:\s*(.*?)(?:\s+\[[^\]]+\])?\s*$"#)

    public static func references(in line: String) -> [Reference] {
        let ns = line as NSString
        return referenceRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func group(_ i: Int) -> String? {
                match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i))
            }
            guard let file = group(1)?.trimmingCharacters(in: .whitespaces),
                  let lineNumber = (group(2) ?? group(4) ?? group(5)).flatMap(Int.init) else { return nil }
            return Reference(range: match.range, file: file, line: lineNumber, column: (group(3) ?? group(6)).flatMap(Int.init))
        }
    }

    /// MSBuild errors and warnings, de-duplicated (MSBuild repeats them in its summary).
    public static func problems(in output: String) -> [Problem] {
        var seen = Set<Problem>()
        var result: [Problem] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            let ns = text as NSString
            guard let match = problemRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let problem = Problem(
                file: ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                line: Int(ns.substring(with: match.range(at: 2))) ?? 1,
                column: Int(ns.substring(with: match.range(at: 3))) ?? 1,
                severity: ns.substring(with: match.range(at: 4)) == "error" ? .error : .warning,
                code: ns.substring(with: match.range(at: 5)),
                message: ns.substring(with: match.range(at: 6)))
            if seen.insert(problem).inserted { result.append(problem) }
        }
        return result
    }
}
