import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct InlayHintTests {
    @Test func parsesStringAndPartLabels() {
        let hints = InlayHint.parseAll([
            ["position": ["line": 3, "character": 9], "label": "name:", "kind": 2, "paddingRight": true],
            ["position": ["line": 4, "character": 2], "label": [["value": "int"]], "kind": 1, "paddingLeft": true],
        ])
        #expect(hints.map(\.label) == ["name:", "int"])
        #expect(hints[0].kind == .parameter && hints[0].paddingRight)
        #expect(hints[1].kind == .type && hints[1].paddingLeft)
    }

}
