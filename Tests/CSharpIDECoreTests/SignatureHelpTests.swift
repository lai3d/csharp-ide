import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct SignatureHelpTests {
    @Test func parsesStringAndOffsetLabels() throws {
        let help = try #require(SignatureHelp.parse([
            "signatures": [[
                "label": "Printf(format string, a ...any) (n int, err error)",
                "documentation": ["kind": "markdown", "value": "Printf formats."],
                "parameters": [["label": "format string"], ["label": [22, 30]]],
            ]],
            "activeSignature": 0, "activeParameter": 1,
        ]))
        let label = help.active!.label as NSString
        #expect(label.substring(with: help.active!.parameters[0]) == "format string")
        #expect(label.substring(with: try #require(help.activeParameterRange)) == "a ...any")
        #expect(help.active?.documentation == "Printf formats.")
    }

    @Test func perSignatureActiveParameterWins() throws {
        let help = try #require(SignatureHelp.parse([
            "signatures": [["label": "f(a, b)", "parameters": [["label": "a"], ["label": "b"]], "activeParameter": 1]],
            "activeParameter": 0,
        ]))
        #expect(help.activeParameterRange == NSRange(location: 5, length: 1))
        #expect(SignatureHelp.parse(["signatures": []]) == nil)
    }

}

@Suite struct ArgumentIndexTests {
    private func index(_ marked: String) -> Int? {
        let caret = (marked as NSString).range(of: "|").location
        return SignatureHelp.argumentIndex(in: marked.replacingOccurrences(of: "|", with: ""), at: caret)
    }

    @Test func countsTopLevelCommas() {
        #expect(index("Add(|") == 0)
        #expect(index("Add(1, |") == 1)
        #expect(index("Add(Max(1, 2), |") == 1)
        #expect(index("Log(\"a, b\", 'x', |") == 2)
        #expect(index("new Dictionary<int, string>(cap, |") == 1)
        #expect(index("var x = 1; |") == nil)
        #expect(index("if (x) { |") == nil)
    }
}
