import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct ReferencesTests {
    @Test func groupsLocationsWithPreviews() {
        func loc(_ uri: String, _ line: Int, _ c1: Int, _ c2: Int) -> Location {
            Location(uri: uri, start: TextPosition(line: line, character: c1), end: TextPosition(line: line, character: c2))
        }
        let files = [
            "/p/a.go": "package p\n\nfunc Foo() {}\n",
            "/p/b.go": "package p\n\nfunc bar() {\n\tFoo()\n\tFoo()\n}\n",
        ]
        let results = ProjectSearch.results(
            for: [loc("file:///p/b.go", 4, 1, 4), loc("file:///p/a.go", 2, 5, 8), loc("file:///p/b.go", 3, 1, 4)],
            text: { files[$0] })
        #expect(results.map(\.path) == ["/p/a.go", "/p/b.go"])
        #expect(results[1].matches.map(\.line) == [3, 4])
        #expect(results[1].matches[0].preview == "Foo()")
        #expect(results[1].matches[0].previewRange == NSRange(location: 0, length: 3))
    }

}
