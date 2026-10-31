import Foundation

/// One test case from `dotnet test` (a theory / test case row is its own result).
public struct TestResult: Sendable, Hashable, Identifiable {
    public enum Status: Sendable, Hashable { case running, passed, failed, skipped }

    /// `Namespace.Class`.
    public var className: String
    /// The method name, without arguments.
    public var method: String
    /// As the runner names it: `Ns.Class.Method` or `Ns.Class.Method(a: 1, b: 2)`.
    public let displayName: String
    public var status: Status
    /// Seconds.
    public var elapsed: Double?
    /// Error message, stack trace and captured output.
    public var output: String

    public var id: String { displayName }
    public var fullyQualifiedName: String { className.isEmpty ? method : className + "." + method }
    /// `Method` or `Method(a: 1, b: 2)`.
    public var shortName: String {
        displayName.hasPrefix(className + ".") && !className.isEmpty
            ? String(displayName.dropFirst(className.count + 1)) : displayName
    }

    public init(className: String, method: String, displayName: String, status: Status,
                elapsed: Double? = nil, output: String = "") {
        self.className = className
        self.method = method
        self.displayName = displayName
        self.status = status
        self.elapsed = elapsed
        self.output = output
    }

    /// Splits `Ns.Class.Method(args)` into class and method (best effort, for live results).
    static func split(_ displayName: String) -> (className: String, method: String) {
        let head = displayName.firstIndex(of: "(").map { String(displayName[..<$0]) } ?? displayName
        guard let dot = head.lastIndex(of: ".") else { return ("", head) }
        return (String(head[..<dot]), String(head[head.index(after: dot)...]))
    }
}

/// Aggregates `dotnet test` results: live from the console logger, then exactly from TRX files.
public struct TestReport: Sendable {
    public private(set) var tests: [TestResult] = []
    /// Compiler errors from the build step (shown when no test ran).
    public private(set) var buildOutput = ""
    private var index: [String: Int] = [:]
    /// The failed test whose "Error Message:" / "Stack Trace:" block is being read.
    private var collecting: Int?

    public init() {}

    public var passed: Int { tests.filter { $0.status == .passed }.count }
    public var failed: Int { tests.filter { $0.status == .failed }.count }
    public var skipped: Int { tests.filter { $0.status == .skipped }.count }

    /// Per test method (theory rows folded together: any failure wins), for the gutter.
    public var statusByMethod: [String: TestResult.Status] {
        var result: [String: TestResult.Status] = [:]
        func rank(_ s: TestResult.Status) -> Int {
            switch s { case .failed: 3; case .running: 2; case .passed: 1; case .skipped: 0 }
        }
        for test in tests {
            if let current = result[test.method], rank(current) >= rank(test.status) { continue }
            result[test.method] = test.status
        }
        return result
    }

    private static let statusLine = try! NSRegularExpression(
        pattern: #"^\s{1,4}(Passed|Failed|Skipped)\s+(.+?)\s+\[([^\]]*)\]\s*$"#)

    /// A console-logger line (`dotnet test --logger "console;verbosity=normal"`).
    public mutating func consume(line: String) {
        let ns = line as NSString
        if let match = Self.statusLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let outcome = ns.substring(with: match.range(at: 1))
            let name = ns.substring(with: match.range(at: 2))
            let status: TestResult.Status = outcome == "Passed" ? .passed : outcome == "Failed" ? .failed : .skipped
            let i = upsert(name)
            tests[i].status = status
            tests[i].elapsed = Self.parseConsoleDuration(ns.substring(with: match.range(at: 3)))
            collecting = status == .failed ? i : nil
            return
        }
        if line.hasPrefix("[xUnit.net") || line.hasPrefix("Results File:") || line.hasPrefix("Test Run ")
            || line.hasPrefix("Total tests:") || line.hasPrefix("A total of") {
            collecting = nil
            return
        }
        if let i = collecting {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && tests[i].output.hasSuffix("\n\n") { return }
            tests[i].output += line + "\n"
            return
        }
        if !BuildOutput.problems(in: line).isEmpty { buildOutput += line + "\n" }
    }

    /// Replaces live results with a TRX file's (outcomes, durations, messages, stack traces, stdout).
    public mutating func merge(trx data: Data) {
        let parser = TRXParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return }
        for result in parser.results {
            let method = parser.methods[result.testId]
            let i = upsert(result.testName)
            if let method {
                tests[i].className = method.className
                tests[i].method = method.name
            }
            tests[i].status = switch result.outcome {
            case "Passed": .passed
            case "Failed", "Error", "Timeout", "Aborted": .failed
            default: .skipped
            }
            tests[i].elapsed = result.duration
            var output = ""
            if !result.message.isEmpty { output += result.message + "\n" }
            if !result.stackTrace.isEmpty { output += "\n" + result.stackTrace + "\n" }
            if !result.stdout.isEmpty { output += "\nOutput:\n" + result.stdout + "\n" }
            if !output.isEmpty { tests[i].output = output }
        }
    }

    private mutating func upsert(_ displayName: String) -> Int {
        if let i = index[displayName] { return i }
        let (className, method) = TestResult.split(displayName)
        tests.append(TestResult(className: className, method: method, displayName: displayName, status: .running))
        index[displayName] = tests.count - 1
        return tests.count - 1
    }

    /// `9 ms`, `< 1 ms`, `1 s`, `2 m 3 s` → seconds.
    static func parseConsoleDuration(_ text: String) -> Double? {
        var total = 0.0
        var found = false
        let parts = text.replacingOccurrences(of: "<", with: "").split(separator: " ")
        var i = 0
        while i + 1 < parts.count {
            if let value = Double(parts[i]) {
                switch parts[i + 1] {
                case "ms": total += value / 1000; found = true
                case "s": total += value; found = true
                case "m": total += value * 60; found = true
                case "h": total += value * 3600; found = true
                default: break
                }
            }
            i += 1
        }
        return found ? total : nil
    }

    /// TRX `hh:mm:ss.fffffff` → seconds.
    static func parseTRXDuration(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

private final class TRXParser: NSObject, XMLParserDelegate {
    struct Result {
        var testId = "", testName = "", outcome = ""
        var duration: Double?
        var message = "", stackTrace = "", stdout = ""
    }

    var results: [Result] = []
    var methods: [String: (className: String, name: String)] = [:]
    private var current: Result?
    private var definitionId: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "UnitTestResult":
            current = Result(testId: attributes["testId"] ?? "", testName: attributes["testName"] ?? "",
                             outcome: attributes["outcome"] ?? "",
                             duration: attributes["duration"].flatMap(TestReport.parseTRXDuration))
        case "UnitTest":
            definitionId = attributes["id"]
        case "TestMethod":
            if let id = definitionId, let className = attributes["className"], let method = attributes["name"] {
                methods[id] = (className, method)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "Message": current?.message = text.trimmingCharacters(in: .newlines)
        case "StackTrace": current?.stackTrace = text.trimmingCharacters(in: .newlines)
        case "StdOut": current?.stdout = text.trimmingCharacters(in: .newlines)
        case "UnitTestResult":
            if let current { results.append(current) }
            current = nil
        case "UnitTest": definitionId = nil
        default: break
        }
    }
}

/// Finds test methods (xUnit, NUnit, MSTest, TUnit attributes) in C# source.
public enum CSharpTestFinder {
    public static let attributeNames: Set<String> = [
        "Fact", "Theory", "SkippableFact", "SkippableTheory",       // xUnit
        "Test", "TestCase", "TestCaseSource", "Theory",              // NUnit (+ TUnit's Test)
        "TestMethod", "DataTestMethod",                              // MSTest
    ]

    public struct Method: Sendable, Hashable {
        public let name: String
        /// Zero-based line of the method's name.
        public let line: Int
        /// `Namespace.Class` (nested classes as `Outer+Inner`).
        public let className: String
        public var fullyQualifiedName: String { className.isEmpty ? name : className + "." + name }
    }

    private static let attributeLine = try! NSRegularExpression(pattern: #"^\s*\[(.*)\]\s*(?://.*)?$"#)
    private static let attributeName = try! NSRegularExpression(pattern: #"(?:^|[\[,]\s*)(?:[\w.]+\.)?(\w+?)(?:Attribute)?\s*(?:\(|,|$|\])"#)
    private static let methodDeclaration = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:public|private|protected|internal|static|async|virtual|override|sealed|unsafe|new|extern)\s+)*[\w<>\[\],?.() ]+?\s+(\w+)\s*(?:<[^>]*>)?\s*\("#)
    private static let namespaceRegex = try! NSRegularExpression(pattern: #"^\s*namespace\s+([\w.]+)"#, options: .anchorsMatchLines)
    private static let typeRegex = try! NSRegularExpression(
        pattern: #"\b(?:class|record|struct)\s+(\w+)"#)

    /// Test methods with their zero-based lines.
    public static func testMethods(in text: String) -> [Method] {
        let lines = text.components(separatedBy: "\n")
        let ns = text as NSString
        let namespace = namespaceRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
        var result: [Method] = []
        var pendingTest = false
        // Enclosing types by brace depth, to name nested classes Outer+Inner.
        var typeStack: [(name: String, depth: Int)] = []
        var depth = 0
        var pendingType: String?
        for (number, line) in lines.enumerated() {
            let range = NSRange(location: 0, length: (line as NSString).length)
            let isAttribute = attributeLine.firstMatch(in: line, range: range) != nil
            if isAttribute {
                let inner = line as NSString
                for match in attributeName.matches(in: line, range: range)
                where attributeNames.contains(inner.substring(with: match.range(at: 1))) {
                    pendingTest = true
                }
            } else if let type = typeRegex.firstMatch(in: line, range: range), !line.contains("(") || line.contains("record") {
                pendingType = (line as NSString).substring(with: type.range(at: 1))
                pendingTest = false
            } else if pendingTest, let match = methodDeclaration.firstMatch(in: line, range: range) {
                let name = (line as NSString).substring(with: match.range(at: 1))
                let types = typeStack.map(\.name).joined(separator: "+")
                let className = [namespace, types.isEmpty ? nil : types].compactMap { $0 }.joined(separator: ".")
                result.append(Method(name: name, line: number, className: className))
                pendingTest = false
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty
                        && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                pendingTest = false
            }
            // Track braces (strings and comments are rare enough around declarations to ignore).
            for c in line {
                if c == "{" {
                    depth += 1
                    if let type = pendingType { typeStack.append((type, depth)); pendingType = nil }
                } else if c == "}" {
                    if typeStack.last?.depth == depth { typeStack.removeLast() }
                    depth -= 1
                }
            }
        }
        return result
    }

    /// The test method whose declaration or body contains `offset`.
    public static func enclosingTest(in text: String, at offset: Int) -> Method? {
        let index = LineIndex(text)
        let units = Array(text.utf16)
        for method in testMethods(in: text).reversed() {
            let start = index.offset(of: TextPosition(line: method.line, character: 0))
            guard start <= offset, let end = bodyEnd(units, from: start) else { continue }
            return offset <= end ? method : nil
        }
        return nil
    }

    /// UTF-16 offset just past a method body starting at its declaration: the `}` matching the
    /// first `{`, or the `;` ending an `=>` expression body.
    private static func bodyEnd(_ units: [UInt16], from start: Int) -> Int? {
        var i = start
        var parens = 0
        while i < units.count {
            switch units[i] {
            case 0x28: parens += 1
            case 0x29: parens -= 1
            case 0x3D where parens == 0 && i + 1 < units.count && units[i + 1] == 0x3E:  // =>
                while i < units.count, units[i] != 0x3B { i += 1 }
                return i
            case 0x7B where parens == 0:  // {
                var depth = 0
                while i < units.count {
                    if units[i] == 0x7B { depth += 1 }
                    if units[i] == 0x7D { depth -= 1; if depth == 0 { return i + 1 } }
                    i += 1
                }
                return units.count
            default: break
            }
            i += 1
        }
        return nil
    }
}
