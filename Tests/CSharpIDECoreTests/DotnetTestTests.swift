import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct TestReportTests {
    @Test func parsesConsoleLoggerLines() {
        var report = TestReport()
        for line in """
            [xUnit.net 00:00:00.24]     Calc.Tests.CalcTests.Fails [FAIL]
              Skipped Calc.Tests.CalcTests.Skipped [1 ms]
              Passed Calc.Tests.CalcTests.Adds [9 ms]
              Passed Calc.Tests.CalcTests.Theory(a: 2, b: 2) [< 1 ms]
              Failed Calc.Tests.CalcTests.Theory(a: 1, b: 2) [1 s 20 ms]
              Error Message:
               Assert.Equal() Failure: Values differ
              Stack Trace:
                 at Calc.Tests.CalcTests.Theory(Int32 a, Int32 b) in /src/UnitTest1.cs:line 18
            Results File: /tmp/x.trx
            /src/UnitTest1.cs(3,1): error CS1002: ; expected [/src/T.csproj]
            """.split(separator: "\n", omittingEmptySubsequences: false) {
            report.consume(line: String(line))
        }
        #expect(report.tests.map(\.displayName) == ["Calc.Tests.CalcTests.Skipped", "Calc.Tests.CalcTests.Adds",
                                                   "Calc.Tests.CalcTests.Theory(a: 2, b: 2)", "Calc.Tests.CalcTests.Theory(a: 1, b: 2)"])
        #expect((report.passed, report.failed, report.skipped) == (2, 1, 1))
        let theory = report.tests[3]
        #expect(theory.className == "Calc.Tests.CalcTests" && theory.method == "Theory")
        #expect(theory.shortName == "Theory(a: 1, b: 2)")
        #expect(theory.elapsed == 1.02)
        #expect(theory.output.contains("Values differ") && theory.output.contains("UnitTest1.cs:line 18"))
        #expect(!theory.output.contains("Results File"))
        #expect(report.statusByMethod == ["Skipped": .skipped, "Adds": .passed, "Theory": .failed])
        #expect(report.buildOutput.contains("CS1002"))
    }

    @Test func mergesTRX() {
        let trx = """
            <?xml version="1.0" encoding="utf-8"?>
            <TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
              <Results>
                <UnitTestResult testId="t1" testName="Calc.Tests.CalcTests.Fails" duration="00:00:00.0024675" outcome="Failed">
                  <Output>
                    <StdOut>hello from test</StdOut>
                    <ErrorInfo>
                      <Message>Assert.Equal() Failure: Values differ
            Expected: 5</Message>
                      <StackTrace>   at Calc.Tests.CalcTests.Fails() in /src/UnitTest1.cs:line 12</StackTrace>
                    </ErrorInfo>
                  </Output>
                </UnitTestResult>
                <UnitTestResult testId="t2" testName="Weird Display Name" duration="00:00:01.5000000" outcome="NotExecuted" />
              </Results>
              <TestDefinitions>
                <UnitTest name="Calc.Tests.CalcTests.Fails" id="t1"><TestMethod className="Calc.Tests.CalcTests" name="Fails" /></UnitTest>
                <UnitTest name="Weird Display Name" id="t2"><TestMethod className="Calc.Tests.Other" name="Named" /></UnitTest>
              </TestDefinitions>
            </TestRun>
            """
        var report = TestReport()
        report.consume(line: "  Passed Calc.Tests.CalcTests.Fails [3 ms]")  // live result, corrected by TRX
        report.merge(trx: Data(trx.utf8))
        #expect(report.tests.count == 2)
        let fails = report.tests[0]
        #expect(fails.status == .failed && fails.elapsed == 0.0024675)
        #expect(fails.output.contains("Expected: 5") && fails.output.contains("line 12") && fails.output.contains("hello from test"))
        let named = report.tests[1]
        #expect(named.className == "Calc.Tests.Other" && named.method == "Named" && named.status == .skipped)
        #expect(named.fullyQualifiedName == "Calc.Tests.Other.Named" && named.elapsed == 1.5)
    }
}

@Suite struct CSharpTestFinderTests {
    static let source = """
        using Xunit;

        namespace Calc.Tests;

        public class CalcTests
        {
            [Fact]
            public void Adds()
            {
                Assert.Equal(4, 2 + 2);
            }

            [Theory]
            [InlineData(1, 2)]
            public async Task Theory(int a, int b) => await Task.Yield();

            private int Helper() => 1;

            public class Nested
            {
                [Fact(Skip = "later")] // why
                public void Inner() { }
            }

            [NUnit.Framework.TestCase(1)]
            [TestMethod, Timeout(100)]
            public void Mixed(int x) { }
        }
        """

    @Test func findsTestMethods() {
        let methods = CSharpTestFinder.testMethods(in: Self.source)
        #expect(methods.map(\.name) == ["Adds", "Theory", "Inner", "Mixed"])
        #expect(methods.map(\.line) == [7, 14, 21, 26])
        #expect(methods[0].fullyQualifiedName == "Calc.Tests.CalcTests.Adds")
        #expect(methods[2].className == "Calc.Tests.CalcTests+Nested")
        #expect(methods[3].className == "Calc.Tests.CalcTests")
    }

    @Test func findsEnclosingTest() {
        let index = LineIndex(Self.source)
        func at(_ line: Int) -> String? {
            CSharpTestFinder.enclosingTest(in: Self.source, at: index.offset(of: TextPosition(line: line, character: 8)))?.name
        }
        #expect(at(9) == "Adds")      // inside the body
        #expect(at(14) == "Theory")   // expression body
        #expect(at(16) == nil)        // Helper, not a test
        #expect(at(21) == "Inner")
        #expect(at(2) == nil)
    }

    @Test func blockScopedNamespace() {
        let source = "namespace A.B\n{\n    public class T\n    {\n        [Test]\n        public void X() { }\n    }\n}\n"
        #expect(CSharpTestFinder.testMethods(in: source).first?.fullyQualifiedName == "A.B.T.X")
    }
}
