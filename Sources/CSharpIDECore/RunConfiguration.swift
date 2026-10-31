import Foundation

/// How to run/debug a project: which one, with what arguments, environment and build configuration.
public struct RunConfiguration: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    /// Project file relative to the workspace root, e.g. `src/App/App.csproj`.
    public var project: String
    /// Program arguments, shell-style (quotes group words).
    public var arguments: String
    /// Extra environment, one `KEY=value` per line.
    public var environment: String
    /// MSBuild configuration: Debug or Release.
    public var configuration: String
    /// A `Properties/launchSettings.json` profile ("" = dotnet's default, the first project profile).
    public var launchProfile: String

    public init(name: String, project: String, arguments: String = "", environment: String = "",
                configuration: String = "Debug", launchProfile: String = "") {
        self.name = name
        self.project = project
        self.arguments = arguments
        self.environment = environment
        self.configuration = configuration
        self.launchProfile = launchProfile
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, project, arguments, environment, configuration, launchProfile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "App"
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try c.decodeIfPresent(String.self, forKey: .environment) ?? ""
        configuration = try c.decodeIfPresent(String.self, forKey: .configuration) ?? "Debug"
        launchProfile = try c.decodeIfPresent(String.self, forKey: .launchProfile) ?? ""
    }

    public var argumentList: [String] { ShellWords.split(arguments) }

    public var environmentVariables: [String: String] {
        var result: [String: String] = [:]
        for line in environment.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            result[String(trimmed[..<eq])] = String(trimmed[trimmed.index(after: eq)...])
        }
        return result
    }

    /// `dotnet run` arguments for this configuration.
    public var dotnetRunArguments: [String] {
        var args = ["run", "--project", project, "--configuration", configuration]
        if !launchProfile.isEmpty { args += ["--launch-profile", launchProfile] }
        if !argumentList.isEmpty { args += ["--"] + argumentList }
        return args
    }
}

public enum ShellWords {
    /// Splits like a shell: whitespace separates words; '…' and "…" group; backslash escapes.
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for c in line {
            if escaped {
                current.append(c)
                escaped = false
            } else if c == "\\" && quote != "'" {
                escaped = true
                inWord = true
            } else if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
                inWord = true
            } else if c.isWhitespace {
                if inWord { words.append(current); current = ""; inWord = false }
            } else {
                current.append(c)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}

public enum LaunchSettings {
    /// Profile names from `Properties/launchSettings.json` next to `projectPath` that `dotnet run`
    /// can use (commandName "Project"), in file order.
    public static func profiles(forProject projectURL: URL) -> [String] {
        let file = projectURL.deletingLastPathComponent().appendingPathComponent("Properties/launchSettings.json")
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return [] }
        // launchSettings.json often has comments / trailing commas; strip line comments first.
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let range = line.range(of: "//"), !line[..<range.lowerBound].contains("\"") else { return line }
                return line[..<range.lowerBound]
            }.joined(separator: "\n")
        guard let json = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8), options: [.json5Allowed]) as? [String: Any],
              let profiles = json["profiles"] as? [String: Any] else { return [] }
        // Dictionary order is lost: recover file order from where each key appears.
        return profiles.compactMap { name, value -> (String, String.Index)? in
            guard (value as? [String: Any])?["commandName"] as? String == "Project",
                  let at = text.range(of: "\"\(name)\"") else { return nil }
            return (name, at.lowerBound)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
