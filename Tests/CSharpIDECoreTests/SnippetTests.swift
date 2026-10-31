import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct SnippetTests {
    private func parts(_ s: Snippet) -> [String] {
        s.stops.map { (s.text as NSString).substring(with: $0) }
    }

    @Test func parsesStopsPlaceholdersAndChoices() {
        let s = Snippet.parse("for ${1:i} := 0; ${1} < ${2:n}; ${3|i++,i--|} {\n\t$0\n}")
        #expect(s.text == "for i := 0;  < n; i++ {\n\t\n}")
        #expect(parts(s) == ["i", "n", "i++", ""])
        #expect(s.stops.last == NSRange(location: 25, length: 0))
    }

    @Test func parsesNestingAndEscapes() {
        let s = Snippet.parse("Printf(${1:\"${2:%v}\\n\"}, ${3:a ...any}) \\$x \\}")
        #expect(s.text == "Printf(\"%v\\n\", a ...any) $x }")
        #expect(parts(s) == ["\"%v\\n\"", "%v", "a ...any", ""])
        #expect(Snippet.parse("plain").stops == [NSRange(location: 5, length: 0)])
    }

    @Test func indentsFollowingLines() {
        let s = Snippet.parse("if err != nil {\n\treturn ${1:err}\n}$0").indented("\t\t")
        #expect(s.text == "if err != nil {\n\t\t\treturn err\n\t\t}")
        #expect(parts(s) == ["err", ""])
        #expect(s.stops.last == NSRange(location: (s.text as NSString).length, length: 0))
    }

    @Test func builtInSnippetsMatchTriggers() {
        #expect(CSharpSnippets.completions(matching: "propg").map(\.label) == ["propg"])
        #expect(CSharpSnippets.completions(matching: "fo").map(\.label).contains("foreach"))
        #expect(CSharpSnippets.completions(matching: "x").isEmpty)
        let ctor = Snippet.parse(CSharpSnippets.all.first { $0.trigger == "ctor" }!.body)
        #expect(ctor.text == "public ClassName()\n{\n\t\n}")
        #expect(Set(CSharpSnippets.all.map(\.trigger)).count == CSharpSnippets.all.count)  // unique triggers
        #expect(CSharpSnippets.all.allSatisfy { !Snippet.parse($0.body).stops.isEmpty })
    }
}
