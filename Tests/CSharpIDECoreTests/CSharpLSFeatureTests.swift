import Foundation
import Testing
@testable import CSharpIDECore

/// Every LSP feature the editor uses, against one real csharp-ls (a cold project load costs
/// ~15 s, so the checks share a fixture). Skipped when .NET / csharp-ls aren't installed.
@Suite struct CSharpLSFeatureTests {
    static let program = """
        namespace T;

        public static class Program
        {
            public static void Main()
            {
                var total = Add(1, 2);
                total = total + Add(total, 3);
                Console.WriteLine(total);
                Middle();
            }

            static int Add(int left, int right) => left + right;

            static void Leaf() { }

            static void Middle()
            {
                Leaf();
                Leaf();
            }
        }

        public class Order
        {
            public int Id { get; set; }
        }

        """
    static let helper = "namespace T;\n\npublic static class Helper\n{\n    public static Order Make() => new Order();\n}\n"
    static let messy = "namespace T;\npublic class Messy{\npublic int X( ){return 1;}\n}\n"

    @Test(.enabled(if: CSharpLSFixture.isAvailable), .timeLimit(.minutes(3)))
    func languageFeatures() async throws {
        let fixture = try await CSharpLSFixture(
            files: ["Program.cs": Self.program, "Helper.cs": Self.helper, "Messy.cs": Self.messy],
            capabilities: [
                "textDocument": [
                    "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
                    "signatureHelp": ["signatureInformation": ["parameterInformation": ["labelOffsetSupport": true]]],
                    "foldingRange": ["lineFoldingOnly": false],
                    "semanticTokens": [
                        "requests": ["full": true], "formats": ["relative"],
                        "tokenTypes": .array(SemanticTokenLegend.clientTypes.map(JSONValue.string)),
                        "tokenModifiers": .array(SemanticTokenLegend.clientModifiers.map(JSONValue.string)),
                    ],
                    "inlayHint": [:],
                ],
            ], name: "features")
        try fixture.open("Program.cs")
        try fixture.open("Messy.cs")
        let program = ["uri": fixture.uri("Program.cs")] as JSONValue
        func at(_ line: Int, _ character: Int) -> JSONValue {
            ["textDocument": program, "position": TextPosition(line: line, character: character).json]
        }

        // Wait for the project to load (definition answers once Roslyn knows the file).
        let definition = try await fixture.poll("textDocument/definition", at(6, 21)) { !Location.parseAll($0).isEmpty }
        #expect(Location.parseAll(definition).first?.start.line == 12)

        // Outline + workspace symbols
        let outline = SymbolNode.parseAll(try await fixture.client.request("textDocument/documentSymbol", params: ["textDocument": program]))
        func flatten(_ nodes: [SymbolNode]) -> [String] { nodes.flatMap { [$0.name] + flatten($0.children ?? []) } }
        let names = flatten(outline)
        #expect(!names.contains("Program.cs"))  // file wrapper unwrapped
        #expect(names.contains { $0.hasPrefix("Program") } && names.contains { $0.hasPrefix("Order") }, "outline: \(names)")
        #expect(names.contains { $0.hasPrefix("Main") }, "outline: \(names)")
        let symbols = SymbolNode.parseAll(try await fixture.poll("workspace/symbol", ["query": "Middle"]) {
            !SymbolNode.parseAll($0).isEmpty
        })
        #expect(symbols.contains { $0.name.contains("Middle") && $0.uri?.hasSuffix("/Program.cs") == true })

        // Occurrences of `total`
        let highlights = DocumentHighlight.parseAll(try await fixture.client.request("textDocument/documentHighlight", params: at(8, 26)))
        #expect(highlights.count == 5, "highlights: \(highlights)")
        #expect(highlights.contains { $0.start.line == 6 })

        // References to Order, across files
        let refs = Location.parseAll(try await fixture.client.request("textDocument/references", params: [
            "textDocument": program, "position": TextPosition(line: 23, character: 14).json,
            "context": ["includeDeclaration": true],
        ]))
        #expect(refs.contains { $0.uri.hasSuffix("/Helper.cs") }, "refs: \(refs)")

        // Signature help: `Add(1, |2)`
        let rawSignature = try await fixture.client.request("textDocument/signatureHelp", params: at(6, 27))
        let offset = LineIndex(Self.program).offset(of: TextPosition(line: 6, character: 27))
        let signature = try #require(SignatureHelp.parse(rawSignature)?.resolvingActiveParameter(text: Self.program, offset: offset))
        let label = try #require(signature.active?.label) as NSString
        #expect(label.substring(with: try #require(signature.activeParameterRange)).contains("right"), "signature: \(label)")

        // Folding
        let regions = FoldRegion.parseAll(try await fixture.client.request("textDocument/foldingRange", params: ["textDocument": program]))
        #expect(regions.contains { $0.startLine == 16 || $0.startLine == 17 }, "folds: \(regions.map(\.startLine))")

        // Call hierarchy around Middle()
        let items = CallHierarchyItem.parseAll(try await fixture.client.request("textDocument/prepareCallHierarchy", params: at(16, 17)))
        let middle = try #require(items.first)
        #expect(middle.name.hasPrefix("Middle"))
        let incoming = CallHierarchyCall.parseAll(try await fixture.client.request("callHierarchy/incomingCalls", params: ["item": middle.raw]))
        #expect(incoming.contains { $0.item.name.hasPrefix("Main") }, "incoming: \(incoming.map(\.item.name))")
        let outgoing = CallHierarchyCall.parseAll(try await fixture.client.request("callHierarchy/outgoingCalls", params: ["item": middle.raw]))
        #expect(outgoing.contains { $0.item.name.hasPrefix("Leaf") }, "outgoing: \(outgoing.map(\.item.name))")

        // Semantic tokens
        let legend = try #require(SemanticTokenLegend(initializeResult: fixture.initializeResult))
        let tokens = legend.decode(try await fixture.client.request("textDocument/semanticTokens/full", params: ["textDocument": program]))
        let lines = Self.program.components(separatedBy: "\n")
        let byText = Dictionary(tokens.map { token in
            ((lines[token.line] as NSString).substring(with: NSRange(location: token.start, length: token.length)) + "@\(token.line)", token)
        }, uniquingKeysWith: { a, _ in a })
        #expect(byText["Order@23"]?.type == "class", "Order: \(String(describing: byText["Order@23"]))")
        #expect(byText["left@12"]?.type == "parameter")
        #expect(byText["Add@6"]?.type == "method")

        // Inlay hints: parameter names at Add(1, 2)
        let hints = InlayHint.parseAll(try await fixture.client.request("textDocument/inlayHint", params: [
            "textDocument": program,
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 27, "character": 0]],
        ]))
        #expect(hints.contains { $0.label.contains("left") && $0.position.line == 6 }, "hints: \(hints.map(\.label))")

        // Formatting
        let messy = ["uri": fixture.uri("Messy.cs")] as JSONValue
        let formatEdits = (try await fixture.client.request("textDocument/formatting", params: [
            "textDocument": messy, "options": ["tabSize": 4, "insertSpaces": true],
        ])).arrayValue?.compactMap(TextEdit.parse) ?? []
        let formatted = TextEdit.apply(formatEdits, to: Self.messy)
        #expect(formatted.contains("public int X() { return 1; }"), "formatted:\n\(formatted)")

        // Rename Leaf → Tip
        let rename = WorkspaceEdit.parse(try await fixture.client.request("textDocument/rename", params: [
            "textDocument": program, "position": TextPosition(line: 14, character: 17).json, "newName": "Tip",
        ]))
        #expect((rename.changes[fixture.url("Program.cs").absoluteString]?.count ?? 0) == 3, "rename: \(rename.changes)")

        await fixture.shutdown()
    }
}
