import Foundation

/// Finds .NET tooling. GUI apps launched from Finder get a minimal PATH, so we
/// also look in the usual .NET SDK, dotnet-tool and Homebrew install locations.
public enum ToolLocator {
    public static func searchDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        if let root = environment["DOTNET_ROOT"] { dirs.append(root) }
        // Global dotnet tools (csharp-ls, netcoredbg wrappers), then the SDK install locations:
        // dotnet-install.sh (~/.dotnet), the official .pkg, Homebrew.
        dirs += ["\(home)/.dotnet/tools", "\(home)/.dotnet", "/usr/local/share/dotnet",
                 "/opt/homebrew/share/dotnet", "/opt/homebrew/bin", "/usr/local/bin",
                 "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// UserDefaults key for a user-chosen tool path (set in Settings).
    public static func overrideKey(for name: String) -> String { "toolPath.\(name)" }

    public static func find(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let custom = UserDefaults.standard.string(forKey: overrideKey(for: name))?
            .trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for dir in searchDirectories(environment: environment) {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// The current environment with PATH widened to every search directory,
    /// so child processes (csharp-ls, dotnet) can find each other. Also sets DOTNET_ROOT:
    /// framework-dependent tools like csharp-ls need it when the SDK isn't in /usr/local/share/dotnet.
    public static func environment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["PATH"] = searchDirectories(environment: base).joined(separator: ":")
        if env["DOTNET_ROOT"] == nil, let root = dotnetRoot(environment: base) {
            env["DOTNET_ROOT"] = root.path
        }
        env["DOTNET_CLI_TELEMETRY_OPTOUT"] = env["DOTNET_CLI_TELEMETRY_OPTOUT"] ?? "1"
        env["DOTNET_NOLOGO"] = env["DOTNET_NOLOGO"] ?? "1"
        return env
    }

    /// The directory holding the `dotnet` host (symlinks resolved, so a Homebrew
    /// `/opt/homebrew/bin/dotnet` maps to its real SDK folder).
    public static func dotnetRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let dotnet = find("dotnet", environment: environment) else { return nil }
        return dotnet.canonicalFileURL.deletingLastPathComponent()
    }
}

public extension URL {
    /// The canonical file URL as the OS (and csharp-ls) sees it: symlinks resolved and
    /// `/tmp` → `/private/tmp`. Unlike `resolvingSymlinksInPath()`, keeps `/private`.
    var canonicalFileURL: URL {
        guard isFileURL, let resolved = realpath(path, nil) else { return standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: hasDirectoryPath)
    }
}
