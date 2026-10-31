import Foundation
import Testing
@testable import CSharpIDECore

/// A throwaway console project plus a running, initialized csharp-ls.
/// Integration tests gate on `CSharpLSFixture.isAvailable` so they skip on machines without .NET.
final class CSharpLSFixture {
    static var isAvailable: Bool { ToolLocator.find("csharp-ls") != nil && ToolLocator.find("dotnet") != nil }

    static let csproj = """
        <Project Sdk="Microsoft.NET.Sdk">
          <PropertyGroup>
            <OutputType>Exe</OutputType>
            <TargetFramework>net10.0</TargetFramework>
            <ImplicitUsings>enable</ImplicitUsings>
            <Nullable>enable</Nullable>
          </PropertyGroup>
        </Project>
        """

    let dir: URL
    let client = LSPClient()
    private(set) var initializeResult: JSONValue = .null
    /// Every notification the server sent, in order.
    let notifications: AsyncStream<(String, JSONValue)>
    private let continuation: AsyncStream<(String, JSONValue)>.Continuation

    /// Writes `files` (relative path → contents) next to a `T.csproj` and starts csharp-ls on it.
    init(files: [String: String], capabilities: JSONValue = [:], name: String = "t") async throws {
        // Real path: csharp-ls reports /private/var/..., not /var/...
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("csharpide-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        dir = tmp.canonicalFileURL
        try Self.csproj.write(to: dir.appendingPathComponent("T.csproj"), atomically: true, encoding: .utf8)
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        (notifications, continuation) = AsyncStream<(String, JSONValue)>.makeStream()
        let continuation = continuation
        client.onNotification = { method, params in continuation.yield((method, params)) }
        client.onRequest = { method, params in
            method == "workspace/configuration"
                ? .array((params["items"]?.arrayValue ?? []).map { _ in .null }) : .null
        }
        try client.start(executable: try #require(ToolLocator.find("csharp-ls")),
                         environment: ToolLocator.environment(), currentDirectory: dir)
        initializeResult = try await client.request("initialize", params: [
            "processId": .int(Int(getpid())),
            "rootUri": .string(dir.absoluteString),
            "workspaceFolders": [["uri": .string(dir.absoluteString), "name": "t"]],
            "capabilities": capabilities,
            "initializationOptions": CSharpLSSettings.default,
        ])
        try client.notify("initialized", params: [:])
    }

    func url(_ path: String) -> URL { dir.appendingPathComponent(path) }

    func uri(_ path: String) -> JSONValue { .string(url(path).absoluteString) }

    /// Sends didOpen for a file written in `init` (or `text` if given).
    func open(_ path: String, text: String? = nil) throws {
        let text = try text ?? String(contentsOf: url(path), encoding: .utf8)
        try client.notify("textDocument/didOpen", params: [
            "textDocument": ["uri": uri(path), "languageId": "csharp", "version": 1, "text": .string(text)],
        ])
    }

    /// Re-sends `request` until `accept` likes the answer: csharp-ls answers null / empty
    /// until the project has loaded, which takes a few seconds on a cold start.
    func poll(_ method: String, _ params: JSONValue, attempts: Int = 60,
              until accept: (JSONValue) -> Bool = { $0 != .null }) async throws -> JSONValue {
        var last: JSONValue = .null
        for _ in 0..<attempts {
            last = (try? await client.request(method, params: params)) ?? .null
            if accept(last) { return last }
            try await Task.sleep(for: .milliseconds(500))
        }
        return last
    }

    /// The first non-empty diagnostics published for `path`.
    func firstDiagnostics(for path: String) async -> [Diagnostic]? {
        let target = url(path).absoluteString
        for await (method, params) in notifications where method == "textDocument/publishDiagnostics" {
            if let published = Diagnostic.parsePublish(params), published.uri == target, !published.diagnostics.isEmpty {
                return published.diagnostics
            }
        }
        return nil
    }

    func shutdown() async {
        await client.shutdown()
        continuation.finish()
        try? FileManager.default.removeItem(at: dir)
    }
}
