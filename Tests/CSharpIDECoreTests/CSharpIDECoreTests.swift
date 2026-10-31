import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct LSPFramerTests {
    @Test func roundTripsSingleMessage() {
        var framer = LSPFramer()
        let body = Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
        #expect(framer.append(LSPFramer.frame(body)) == [body])
    }

    @Test func reassemblesSplitChunks() {
        var framer = LSPFramer()
        let body = Data(#"{"hello":"wörld"}"#.utf8)
        let framed = LSPFramer.frame(body)
        let mid = framed.count / 2
        #expect(framer.append(framed.prefix(mid)).isEmpty)
        #expect(framer.append(framed.suffix(from: mid)) == [body])
    }

    @Test func splitsMultipleMessagesInOneChunk() {
        var framer = LSPFramer()
        let a = Data("{}".utf8), b = Data("[1,2]".utf8)
        #expect(framer.append(LSPFramer.frame(a) + LSPFramer.frame(b)) == [a, b])
    }
}

@Suite struct JSONValueTests {
    @Test func roundTrips() throws {
        let value: JSONValue = ["a": 1, "b": [true, nil, "x"], "c": 1.5]
        let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(decoded["a"]?.intValue == 1)
        #expect(decoded["b"]?[2]?.stringValue == "x")
    }
}

@Suite struct LineIndexTests {
    @Test func convertsPositions() {
        let index = LineIndex("ab\ncdef\n\ng")
        #expect(index.lineCount == 4)
        #expect(index.offset(of: TextPosition(line: 1, character: 2)) == 5)
        #expect(index.offset(of: TextPosition(line: 1, character: 99)) == 7)  // clamped before newline
        #expect(index.position(of: 5) == TextPosition(line: 1, character: 2))
        #expect(index.position(of: 9) == TextPosition(line: 3, character: 0))
    }

    @Test func usesUTF16Units() {
        let index = LineIndex("x😀y")  // emoji is 2 UTF-16 units, like LSP's default encoding
        #expect(index.offset(of: TextPosition(line: 0, character: 3)) == 3)
        #expect(index.utf16Count == 4)
    }
}

@Suite struct GoHighlighterTests {
    private func kinds(_ source: String) -> [(String, GoTokenKind)] {
        let ns = source as NSString
        return GoHighlighter.tokenize(source).map { (ns.substring(with: $0.range), $0.kind) }
    }

    @Test func classifiesTokens() {
        let tokens = kinds(#"func main() { x := len("hi // no") + 42 } // done"#)
        #expect(tokens.map(\.0) == ["func", "main", "len", #""hi // no""#, "42", "// done"])
        #expect(tokens.map(\.1) == [.keyword, .function, .builtin, .string, .number, .comment])
    }

    @Test func handlesRawStringsAndTypes() {
        let tokens = kinds("var s string = `a\n\"b\"`")
        #expect(tokens.map(\.1) == [.keyword, .type, .string])
    }

    @Test func highlightsUnterminatedBlockComment() {
        #expect(kinds("x /* open").last?.1 == .comment)
    }
}

@Suite struct DiagnosticTests {
    @Test func parsesPublishDiagnostics() throws {
        let params: JSONValue = [
            "uri": "file:///tmp/main.go",
            "diagnostics": [
                ["range": ["start": ["line": 3, "character": 1], "end": ["line": 3, "character": 5]],
                 "severity": 1, "message": "undefined: foo", "source": "compiler"],
                ["range": ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 1]],
                 "severity": 2, "message": "warn"],
            ],
        ]
        let result = try #require(Diagnostic.parsePublish(params))
        #expect(result.uri == "file:///tmp/main.go")
        #expect(result.diagnostics.map(\.message) == ["warn", "undefined: foo"])  // sorted by position
        #expect(result.diagnostics[1].severity == .error)
        #expect(result.diagnostics[1].start == TextPosition(line: 3, character: 1))
    }
}

/// End-to-end check against a real csharp-ls (skipped when .NET / csharp-ls aren't installed).
@Suite struct CSharpLSIntegrationTests {
    @Test(.enabled(if: CSharpLSFixture.isAvailable), .timeLimit(.minutes(2)))
    func publishesDiagnosticsForBrokenCode() async throws {
        let source = "namespace T;\n\npublic static class Program\n{\n    public static void Main() => UndefinedThing();\n}\n"
        let fixture = try await CSharpLSFixture(files: ["Program.cs": source])
        try fixture.open("Program.cs")
        let diagnostics = try #require(await fixture.firstDiagnostics(for: "Program.cs"))
        #expect(diagnostics.contains { $0.message.contains("UndefinedThing") && $0.start.line == 4 })
        await fixture.shutdown()
    }

    @Test(.enabled(if: CSharpLSFixture.isAvailable), .timeLimit(.minutes(2)))
    func hoversCompletesAndJumpsToDefinition() async throws {
        let source = """
            namespace T;

            public static class Program
            {
                public static void Main()
                {
                    var g = new Greeter();
                    Console.WriteLine(g.Greet());
                }
            }

            public class Greeter
            {
                public string Greet() => "hi";
            }
            """
        let fixture = try await CSharpLSFixture(files: ["Program.cs": source])
        try fixture.open("Program.cs")
        let at: (Int, Int) -> JSONValue = { line, character in
            ["textDocument": ["uri": fixture.uri("Program.cs")], "position": ["line": .int(line), "character": .int(character)]]
        }
        // `Greet` in g.Greet()
        let hover = try await fixture.poll("textDocument/hover", at(7, 30))
        #expect(HoverContent.parse(hover)?.contains("Greet()") == true)

        let definition = try await fixture.poll("textDocument/definition", at(7, 30)) { !Location.parseAll($0).isEmpty }
        #expect(Location.parseAll(definition).first?.start.line == 13)

        // Members after `g.`
        let completion = try await fixture.poll("textDocument/completion", at(7, 28)) { !CompletionItem.parseList($0).isEmpty }
        #expect(CompletionItem.parseList(completion).contains { $0.label == "Greet" })
        await fixture.shutdown()
    }
}
