import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct NetcoredbgHelperTests {
    @Test func buildsLaunchArgumentsAndFindsTestHostPid() {
        let args = Netcoredbg.launchArguments(dotnet: URL(fileURLWithPath: "/d/dotnet"), dll: "/p/bin/App.dll",
                                              arguments: ["--x", "1"], cwd: "/p", environment: ["A": "b"])
        #expect(args["program"]?.stringValue == "/d/dotnet")
        #expect(args["args"]?.arrayValue?.compactMap(\.stringValue) == ["/p/bin/App.dll", "--x", "1"])
        #expect(args["env"]?["A"]?.stringValue == "b" && args["cwd"]?.stringValue == "/p")
        #expect(Netcoredbg.testHostProcessID(in: "Process Id: 4242, Name: testhost") == 4242)
        #expect(Netcoredbg.testHostProcessID(in: "Waiting for debugger attach...") == nil)
    }
}

/// End-to-end against a real netcoredbg (skipped until it's installed: Settings or first debug).
@Suite struct DAPTests {
    static var available: Bool { Netcoredbg.find() != nil && ToolLocator.find("dotnet") != nil }

    /// Builds a console app and returns (project dir, Program.cs, dll).
    private func buildApp(_ source: String) async throws -> (URL, URL, String) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-dap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dir = base.canonicalFileURL
        try """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework></PropertyGroup>
            </Project>
            """.write(to: dir.appendingPathComponent("Dbg.csproj"), atomically: true, encoding: .utf8)
        let program = dir.appendingPathComponent("Program.cs")
        try source.write(to: program, atomically: true, encoding: .utf8)
        let build = Process()
        build.executableURL = try #require(ToolLocator.find("dotnet"))
        build.arguments = ["build", "-nologo", "-v:q"]
        build.currentDirectoryURL = dir
        build.environment = ToolLocator.environment()
        build.standardOutput = FileHandle.nullDevice
        try build.run()
        build.waitUntilExit()
        #expect(build.terminationStatus == 0)
        return (dir, program, dir.appendingPathComponent("bin/Debug/net10.0/Dbg.dll").path)
    }

    private func launch(_ client: DAPClient, dir: URL, dll: String, breakpoints: [JSONValue], file: URL) async throws {
        try client.start(adapter: try #require(Netcoredbg.find()), directory: dir, environment: ToolLocator.environment())
        _ = try await client.request("initialize", arguments: [
            "clientID": "csharpide", "adapterID": "coreclr", "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path",
        ])
        async let initialized: Void = client.waitForEvent("initialized")
        _ = try await client.request("launch", arguments: Netcoredbg.launchArguments(
            dotnet: try #require(ToolLocator.find("dotnet")), dll: dll, arguments: [], cwd: dir.path,
            environment: ToolLocator.environment()))
        await initialized
        let set = try await client.request("setBreakpoints", arguments: [
            "source": ["path": .string(file.path)], "breakpoints": .array(breakpoints),
        ])
        #expect(set["breakpoints"]?[0]?["verified"]?.boolValue == true || set["breakpoints"]?[0] != nil)
        _ = try await client.request("configurationDone")
    }

    @Test(.enabled(if: DAPTests.available), .timeLimit(.minutes(2)))
    func launchesBreaksInspectsAndContinues() async throws {
        let (dir, program, dll) = try await buildApp("""
            var p = new Point(3, 4);
            var total = p.X + p.Y;
            Console.WriteLine($"total {total}");

            record Point(int X, int Y);

            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = DAPClient()
        let (events, continuation) = AsyncStream<(String, JSONValue)>.makeStream()
        client.onEvent = { continuation.yield(($0, $1)) }
        try await launch(client, dir: dir, dll: dll, breakpoints: [["line": 3]], file: program)

        var stoppedThread: Int?
        for await (event, body) in events where event == "stopped" {
            stoppedThread = body["threadId"]?.intValue
            break
        }
        let thread = try #require(stoppedThread)
        let frames = StackFrame.parseAll(try await client.request("stackTrace", arguments: ["threadId": .int(thread), "levels": 20]))
        #expect(frames.first?.line == 3 && frames.first?.path == program.path, "frames: \(frames)")

        let scopes = DebugVariable.parseScopes(try await client.request("scopes", arguments: ["frameId": .int(frames[0].id)]))
        let locals = try #require(scopes.first)
        let variables = DebugVariable.parseVariables(try await client.request("variables", arguments: [
            "variablesReference": .int(locals.variablesReference),
        ]))
        #expect(variables.first { $0.name == "total" }?.value == "7", "variables: \(variables)")
        let point = try #require(variables.first { $0.name == "p" })
        #expect(point.variablesReference > 0)
        let fields = DebugVariable.parseVariables(try await client.request("variables", arguments: [
            "variablesReference": .int(point.variablesReference),
        ]))
        #expect(fields.contains { $0.name == "X" && $0.value == "3" }, "fields: \(fields)")

        let evaluated = try await client.request("evaluate", arguments: [
            "expression": "total * 2 + p.Y", "frameId": .int(frames[0].id), "context": "hover",
        ])
        #expect(evaluated["result"]?.stringValue == "18")

        _ = try await client.request("continue", arguments: ["threadId": .int(thread)])
        var sawOutput = false
        for await (event, body) in events {
            if event == "output", body["output"]?.stringValue?.contains("total 7") == true { sawOutput = true }
            if event == "terminated" || event == "exited" { break }
        }
        #expect(sawOutput)
        await client.shutdown()
    }

    @Test(.enabled(if: DAPTests.available), .timeLimit(.minutes(2)))
    func conditionalBreakpoint() async throws {
        let (dir, program, dll) = try await buildApp("""
            var total = 0;
            for (var i = 0; i < 10; i++)
            {
                total += i;
            }
            Console.WriteLine(total);

            """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = DAPClient()
        let (events, continuation) = AsyncStream<(String, JSONValue)>.makeStream()
        client.onEvent = { continuation.yield(($0, $1)) }
        try await launch(client, dir: dir, dll: dll, breakpoints: [["line": 4, "condition": "i == 7"]], file: program)
        var thread: Int?
        for await (event, body) in events where event == "stopped" {
            thread = body["threadId"]?.intValue
            break
        }
        let frames = StackFrame.parseAll(try await client.request("stackTrace", arguments: ["threadId": .int(try #require(thread)), "levels": 1]))
        let frame = try #require(frames.first).id
        func evaluate(_ expression: String) async throws -> String? {
            try await client.request("evaluate", arguments: ["expression": .string(expression), "frameId": .int(frame), "context": "hover"])["result"]?.stringValue
        }
        #expect(try await evaluate("i") == "7")
        #expect(try await evaluate("total") == "21")
        await client.shutdown()
    }
}
