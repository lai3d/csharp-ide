import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct CoverageTests {
    /// Trimmed coverlet output: lines appear under each method and again under the class.
    static let coverlet = """
        <?xml version="1.0" encoding="utf-8"?>
        <coverage line-rate="0.71" lines-covered="5" lines-valid="7">
          <sources><source>/</source></sources>
          <packages><package name="Calc"><classes>
            <class name="Calc.Calculator" filename="r/Calc/Calculator.cs">
              <methods>
                <method name="Add"><lines><line number="5" hits="1" branch="False" /></lines></method>
                <method name="Divide"><lines>
                  <line number="9" hits="1" branch="True" condition-coverage="50% (1/2)">
                    <conditions><condition number="7" type="jump" coverage="50%" /></conditions>
                  </line>
                  <line number="10" hits="0" branch="False" />
                </lines></method>
              </methods>
              <lines>
                <line number="5" hits="1" /><line number="8" hits="1" /><line number="9" hits="1" />
                <line number="10" hits="0" /><line number="11" hits="0" /><line number="13" hits="1" /><line number="14" hits="1" />
              </lines>
            </class>
            <class name="Calc.Calculator/&lt;&gt;c" filename="r/Calc/Calculator.cs">
              <lines><line number="11" hits="2" /></lines>
            </class>
          </classes></package></packages>
        </coverage>
        """

    @Test func parsesCoberturaAndFoldsDuplicateLines() throws {
        let report = CoverageReport.parseCobertura(Data(Self.coverlet.utf8)) { _ in false }
        let calc = try #require(report.files["/r/Calc/Calculator.cs"])
        #expect(calc.statements == 7)
        #expect(calc.lines[4] == true && calc.lines[9] == false)
        #expect(calc.lines[10] == true)  // a second class (lambda closure) covered line 11
        #expect(calc.coveredStatements == 6)
        #expect(report.percent > 85 && report.percent < 86)
    }

    @Test func resolvesAgainstSourcesAndMerges() {
        #expect(CoverageReport.resolve("/abs/a.cs", sources: ["/x"]) { _ in false } == "/abs/a.cs")
        #expect(CoverageReport.resolve("a.cs", sources: ["/x", "/y"]) { $0 == "/y/a.cs" } == "/y/a.cs")
        #expect(CoverageReport.resolve("a.cs", sources: []) { _ in false } == "/a.cs")

        var a = CoverageReport()
        a.files["/f.cs"] = .init(lines: [0: false, 1: true])
        var b = CoverageReport()
        b.files["/f.cs"] = .init(lines: [0: true, 2: false])
        b.files["/g.cs"] = .init(lines: [0: true])
        a.merge(b)
        #expect(a.files["/f.cs"]?.lines == [0: true, 1: true, 2: false])
        #expect(a.files.count == 2)
    }
}
