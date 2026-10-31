import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct SemanticTokenTests {
    @Test func decodesRelativeEncoding() {
        let legend = SemanticTokenLegend(types: ["namespace", "type", "parameter"], modifiers: ["definition", "readonly"])
        // (0,8) len 3 namespace; same line +5 len 4 type [definition]; next line col 2 len 1 parameter [readonly]
        let tokens = legend.decode(["data": [0, 8, 3, 0, 0, 0, 5, 4, 1, 1, 1, 2, 1, 2, 2]])
        #expect(tokens == [
            SemanticToken(line: 0, start: 8, length: 3, type: "namespace"),
            SemanticToken(line: 0, start: 13, length: 4, type: "type", modifiers: ["definition"]),
            SemanticToken(line: 1, start: 2, length: 1, type: "parameter", modifiers: ["readonly"]),
        ])
    }

}
