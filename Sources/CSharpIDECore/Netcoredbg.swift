import Foundation

/// Finds, or downloads, Samsung's netcoredbg — the open-source .NET debug adapter.
public enum Netcoredbg {
    /// Where CSharpIDE installs it: ~/Library/Application Support/CSharpIDE/netcoredbg/netcoredbg.
    public static var installDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CSharpIDE/netcoredbg", isDirectory: true)
    }

    /// A Settings override or PATH copy first, then the one CSharpIDE installed.
    public static func find() -> URL? {
        if let found = ToolLocator.find("netcoredbg") { return found }
        let bundled = installDirectory.appendingPathComponent("netcoredbg/netcoredbg")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    /// The release asset for this Mac (3.2.0 is the first with a native Apple Silicon build).
    public static var downloadURL: URL {
        #if arch(arm64)
        URL(string: "https://github.com/Samsung/netcoredbg/releases/download/3.2.0-1092/netcoredbg-osx-arm64.zip")!
        #else
        URL(string: "https://github.com/Samsung/netcoredbg/releases/download/3.1.3-1062/netcoredbg-osx-amd64.tar.gz")!
        #endif
    }

    /// Downloads and unpacks the release into `installDirectory`; returns the executable.
    public static func install() async throws -> URL {
        let (archive, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "download failed (\(downloadURL))"])
        }
        let fm = FileManager.default
        try? fm.removeItem(at: installDirectory)
        try fm.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let unpack = Process()
        if downloadURL.pathExtension == "zip" {
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unpack.arguments = ["-x", "-k", archive.path, installDirectory.path]
        } else {
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            unpack.arguments = ["-xzf", archive.path, "-C", installDirectory.path]
        }
        try unpack.run()
        unpack.waitUntilExit()
        guard unpack.terminationStatus == 0, let executable = find() else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "couldn't unpack netcoredbg"])
        }
        return executable
    }

    /// DAP `launch` arguments: run `dotnet <dll> <args>` under the debugger.
    public static func launchArguments(dotnet: URL, dll: String, arguments: [String], cwd: String,
                                       environment: [String: String], stopAtEntry: Bool = false) -> JSONValue {
        [
            "name": "CSharpIDE", "type": "coreclr", "request": "launch",
            "program": .string(dotnet.path),
            "args": .array(([dll] + arguments).map(JSONValue.string)),
            "cwd": .string(cwd),
            "env": .object(environment.mapValues(JSONValue.string)),
            "stopAtEntry": .bool(stopAtEntry),
            "justMyCode": true,
        ]
    }

    /// `Process Id: 12345, Name: testhost` from `dotnet test` run with VSTEST_HOST_DEBUG=1.
    public static func testHostProcessID(in line: String) -> Int? {
        guard let range = line.range(of: #"Process Id:\s*(\d+)"#, options: .regularExpression) else { return nil }
        return Int(line[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
    }
}
