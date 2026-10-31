import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct RunConfigurationTests {
    @Test func splitsShellWords() {
        #expect(ShellWords.split(#"-port 8080 --name "my app" 'a b' c\ d"#) == ["-port", "8080", "--name", "my app", "a b", "c d"])
        #expect(ShellWords.split("   ").isEmpty)
        #expect(ShellWords.split(#"--flag="" x"#) == ["--flag=", "x"])
    }


    @Test func parsesEnvironmentAndBuildsRunArguments() throws {
        let config = RunConfiguration(name: "api", project: "src/Api/Api.csproj", arguments: "--port 8080 \"a b\"",
                                      environment: "PORT=8080\n# comment\nDSN=Host=h;Db=x\n\n")
        #expect(config.environmentVariables == ["PORT": "8080", "DSN": "Host=h;Db=x"])
        #expect(config.dotnetRunArguments == ["run", "--project", "src/Api/Api.csproj", "--configuration", "Debug",
                                              "--", "--port", "8080", "a b"])
        let release = RunConfiguration(name: "x", project: "X.csproj", configuration: "Release", launchProfile: "https")
        #expect(release.dotnetRunArguments == ["run", "--project", "X.csproj", "--configuration", "Release", "--launch-profile", "https"])
        let decoded = try JSONDecoder().decode(RunConfiguration.self, from: Data(#"{"name":"old","project":"A.csproj"}"#.utf8))
        #expect(decoded.configuration == "Debug" && decoded.launchProfile == "")
    }

    @Test func readsLaunchProfiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Properties"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try """
            {
              // comment
              "profiles": {
                "https": { "commandName": "Project", "applicationUrl": "https://localhost:7001" },
                "IIS Express": { "commandName": "IISExpress" },
                "http": { "commandName": "Project", },
              }
            }
            """.write(to: base.appendingPathComponent("Properties/launchSettings.json"), atomically: true, encoding: .utf8)
        #expect(LaunchSettings.profiles(forProject: base.appendingPathComponent("Api.csproj")) == ["https", "http"])
    }
}

@Suite struct DotnetProjectTests {
    @Test func classifiesProjects() {
        let console = DotnetProjects.parse(xml: """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework></PropertyGroup>
            </Project>
            """, path: "src/App/App.csproj")
        #expect(console.name == "App" && console.isRunnable && console.directory == "src/App")
        #expect(console.targetFrameworks == ["net10.0"])

        let web = DotnetProjects.parse(xml: #"<Project Sdk="Microsoft.NET.Sdk.Web"></Project>"#, path: "Web.csproj")
        #expect(web.isRunnable && web.directory == ".")

        let lib = DotnetProjects.parse(xml: """
            <Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks></PropertyGroup></Project>
            """, path: "Lib.csproj")
        #expect(!lib.isRunnable && !lib.isTest && lib.targetFrameworks == ["net8.0", "netstandard2.0"])

        let tests = DotnetProjects.parse(xml: """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup><OutputType>Exe</OutputType></PropertyGroup>
              <ItemGroup><PackageReference Include="xunit.v3" Version="1.0.0" /></ItemGroup>
            </Project>
            """, path: "T.Tests.csproj")
        #expect(tests.isTest && !tests.isRunnable)
    }

    @Test func findsProjectsSolutionsAndSkipsBuildOutput() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-proj-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in ["src/App/bin/Debug", "src/App/obj", "tests/App.Tests", "tools/bin"] {
            try fm.createDirectory(at: base.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: base) }
        try #"<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup></Project>"#
            .write(to: base.appendingPathComponent("src/App/App.csproj"), atomically: true, encoding: .utf8)
        try #"<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>"#
            .write(to: base.appendingPathComponent("tests/App.Tests/App.Tests.csproj"), atomically: true, encoding: .utf8)
        try "x".write(to: base.appendingPathComponent("src/App/obj/Stale.csproj"), atomically: true, encoding: .utf8)
        try "x".write(to: base.appendingPathComponent("tools/bin/run.sh"), atomically: true, encoding: .utf8)
        try "".write(to: base.appendingPathComponent("App.slnx"), atomically: true, encoding: .utf8)

        let projects = DotnetProjects.find(under: base)
        #expect(projects.map(\.path) == ["src/App/App.csproj", "tests/App.Tests/App.Tests.csproj"])
        #expect(projects.map(\.isTest) == [false, true])
        #expect(DotnetProjects.solutions(under: base) == ["App.slnx"])
        #expect(DotnetProjects.buildTarget(solutions: ["App.slnx"], projects: projects) == "App.slnx")
        #expect(DotnetProjects.buildTarget(solutions: [], projects: [projects[0]]) == "src/App/App.csproj")
        #expect(DotnetProjects.buildTarget(solutions: [], projects: projects) == nil)
        let root = URL(fileURLWithPath: "/w/R&D")
        let xml = DotnetProjects.generatedSolution(root: root, projects: projects)
        #expect(xml.hasPrefix("<Solution>\n  <Project Path=\"/w/R&amp;D/src/App/App.csproj\" />"))
        #expect(xml.components(separatedBy: "<Project ").count == projects.count + 1)
        let cache = URL(fileURLWithPath: "/c")
        let url = DotnetProjects.generatedSolutionURL(root: root, in: cache)
        #expect(url == DotnetProjects.generatedSolutionURL(root: root, in: cache))
        #expect(url.lastPathComponent.hasPrefix("R&D-") && url.pathExtension == "slnx")
        #expect(url != DotnetProjects.generatedSolutionURL(root: URL(fileURLWithPath: "/x/R&D"), in: cache))
        // bin/obj next to a project are hidden; a plain tools/bin folder is not.
        #expect(ProjectSearch.files(under: base).contains { $0.hasSuffix("tools/bin/run.sh") })
        let tree = FileNode.loadTree(at: base)
        let app = tree.first { $0.name == "src" }?.children?.first { $0.name == "App" }
        #expect(app?.children?.map(\.name) == ["App.csproj"])
    }
}

@Suite struct BuildOutputTests {
    @Test func parsesMSBuildProblems() {
        let output = """
            /Users/me/p/Program.cs(9,22): error CS0029: Cannot implicitly convert type 'string' to 'int' [/Users/me/p/Hello.csproj]
            /Users/me/p/Program.cs(3,7): warning CS0168: The variable 'e' is declared but never used [/Users/me/p/Hello.csproj]
            Build FAILED.
            /Users/me/p/Program.cs(9,22): error CS0029: Cannot implicitly convert type 'string' to 'int' [/Users/me/p/Hello.csproj]
            CSC : error CS5001: Program does not contain a static 'Main' method suitable for an entry point [/x.csproj]
            """
        let problems = BuildOutput.problems(in: output)
        #expect(problems.count == 2)
        #expect(problems[0].file == "/Users/me/p/Program.cs" && problems[0].line == 9 && problems[0].column == 22)
        #expect(problems[0].severity == .error && problems[0].code == "CS0029")
        #expect(problems[0].message == "Cannot implicitly convert type 'string' to 'int'")
        #expect(problems[1].severity == .warning)
    }

    @Test func findsClickableReferences() {
        let msbuild = BuildOutput.references(in: "/a/b/Program.cs(9,22): error CS0029: nope [/a/b/x.csproj]")
        #expect(msbuild.first?.file == "/a/b/Program.cs" && msbuild.first?.line == 9 && msbuild.first?.column == 22)
        let trace = BuildOutput.references(in: "   at T.Program.Main() in /src/App/Program.cs:line 14")
        #expect(trace.first?.file == "/src/App/Program.cs" && trace.first?.line == 14)
        let short = BuildOutput.references(in: "Assert failed at CalcTests.cs:27")
        #expect(short.first?.file == "CalcTests.cs" && short.first?.line == 27)
        #expect(BuildOutput.references(in: "Build succeeded in 1.2s").isEmpty)
    }
}
