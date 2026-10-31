import Foundation

/// Line coverage from coverlet's cobertura reports (`dotnet test --collect "XPlat Code Coverage"`).
public struct CoverageReport: Sendable, Hashable {
    public struct FileCoverage: Sendable, Hashable {
        /// Zero-based line → covered (true) / not covered (false). Lines without sequence points are absent.
        public var lines: [Int: Bool] = [:]

        public init(lines: [Int: Bool] = [:]) { self.lines = lines }

        public var statements: Int { lines.count }
        public var coveredStatements: Int { lines.values.filter { $0 }.count }

        public var percent: Double {
            statements == 0 ? 0 : Double(coveredStatements) / Double(statements) * 100
        }
    }

    /// Keyed by absolute file path.
    public var files: [String: FileCoverage] = [:]

    public var percent: Double {
        let total = files.values.reduce(0) { $0 + $1.statements }
        let covered = files.values.reduce(0) { $0 + $1.coveredStatements }
        return total == 0 ? 0 : Double(covered) / Double(total) * 100
    }

    public init() {}

    /// Parses one cobertura XML document. `filename`s are resolved against the report's
    /// `<source>` entries (coverlet writes `/` plus a root-relative path, other tools a base dir).
    /// A line listed more than once (per method and per class, or by several classes) is covered
    /// if any entry has hits.
    public static func parseCobertura(_ data: Data, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> CoverageReport {
        let delegate = CoberturaParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        var report = CoverageReport()
        for (filename, lines) in delegate.lines {
            let path = resolve(filename, sources: delegate.sources, fileExists: fileExists)
            var file = report.files[path, default: FileCoverage()]
            for (line, hit) in lines { file.lines[line - 1] = (file.lines[line - 1] ?? false) || hit }
            report.files[path] = file
        }
        return report
    }

    /// Several reports (one per test project) folded together.
    public mutating func merge(_ other: CoverageReport) {
        for (path, theirs) in other.files {
            var file = files[path, default: FileCoverage()]
            for (line, hit) in theirs.lines { file.lines[line] = (file.lines[line] ?? false) || hit }
            files[path] = file
        }
    }

    static func resolve(_ filename: String, sources: [String], fileExists: (String) -> Bool) -> String {
        if filename.hasPrefix("/") { return filename }
        let candidates = sources.map { ($0 as NSString).appendingPathComponent(filename) }
        return candidates.first(where: fileExists) ?? candidates.first ?? "/" + filename
    }
}

private final class CoberturaParser: NSObject, XMLParserDelegate {
    var sources: [String] = []
    /// filename → one-based line → hit.
    var lines: [String: [Int: Bool]] = [:]
    private var currentFile: String?
    private var inSource = false
    private var sourceText = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "source":
            inSource = true
            sourceText = ""
        case "class":
            currentFile = attributes["filename"]
        case "line":
            guard let file = currentFile, let number = attributes["number"].flatMap(Int.init),
                  let hits = attributes["hits"].flatMap(Int.init) else { return }
            lines[file, default: [:]][number] = (lines[file]?[number] ?? false) || hits > 0
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSource { sourceText += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "source":
            inSource = false
            let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sources.append(trimmed) }
        case "class":
            currentFile = nil
        default:
            break
        }
    }
}
