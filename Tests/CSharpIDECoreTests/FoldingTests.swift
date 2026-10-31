import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct FoldingTests {
    @Test func computesHiddenRanges() throws {
        let text = "func f() {\n\tx := 1\n}\n"
        let index = LineIndex(text)
        let withChars = FoldRegion(startLine: 0, startCharacter: 10, endLine: 2, endCharacter: 0)
        let hidden = try #require(withChars.hiddenRange(in: index))
        #expect((text as NSString).replacingCharacters(in: hidden, with: "⋯") == "func f() {⋯}\n")
        let linesOnly = FoldRegion(startLine: 0, endLine: 1)
        #expect((text as NSString).replacingCharacters(in: try #require(linesOnly.hiddenRange(in: index)), with: "⋯") == "func f() {⋯\n}\n")
        #expect(FoldRegion.parseAll([["startLine": 3, "endLine": 3]]).isEmpty)
    }

}
