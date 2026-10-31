import Foundation

/// A package from a NuGet search.
public struct NuGetPackage: Sendable, Hashable, Identifiable {
    public let id: String
    public let version: String
    public let description: String
    public let totalDownloads: Int
    public let verified: Bool
}

/// A package with a newer version (`dotnet list package --outdated --format json`).
public struct OutdatedPackage: Sendable, Hashable {
    /// Absolute path of the project file.
    public let project: String
    public let id: String
    public let requested: String
    public let latest: String
}

public enum NuGet {
    public static let serviceIndex = URL(string: "https://api.nuget.org/v3/index.json")!

    /// The SearchQueryService endpoint from a v3 service index.
    public static func searchService(inIndex data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resources = json["resources"] as? [[String: Any]] else { return nil }
        let search = resources.first { ($0["@type"] as? String)?.hasPrefix("SearchQueryService") == true }
        return (search?["@id"] as? String).flatMap(URL.init(string:))
    }

    public static func searchURL(service: URL, query: String, prerelease: Bool, take: Int = 30) -> URL {
        var components = URLComponents(url: service, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "take", value: String(take)),
            URLQueryItem(name: "prerelease", value: prerelease ? "true" : "false"),
            URLQueryItem(name: "semVerLevel", value: "2.0.0"),
        ]
        return components.url!
    }

    public static func parseSearch(_ data: Data) -> [NuGetPackage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let version = item["version"] as? String else { return nil }
            return NuGetPackage(id: id, version: version, description: (item["description"] as? String) ?? "",
                                totalDownloads: (item["totalDownloads"] as? Int) ?? 0,
                                verified: (item["verified"] as? Bool) ?? false)
        }
    }

    /// Parses the JSON report; tolerates text around it (dotnet may print restore notes first).
    public static func parseOutdated(_ output: String) -> [OutdatedPackage] {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
              let json = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]] else { return [] }
        var result: [OutdatedPackage] = []
        for project in projects {
            guard let path = project["path"] as? String else { continue }
            var seen = Set<String>()
            for framework in project["frameworks"] as? [[String: Any]] ?? [] {
                for package in framework["topLevelPackages"] as? [[String: Any]] ?? [] {
                    guard let id = package["id"] as? String, let latest = package["latestVersion"] as? String,
                          seen.insert(id).inserted else { continue }
                    result.append(OutdatedPackage(project: path, id: id,
                                                  requested: (package["requestedVersion"] as? String) ?? "",
                                                  latest: latest))
                }
            }
        }
        return result
    }

    /// Searches nuget.org (resolving the search endpoint from the service index once).
    public static func search(_ query: String, prerelease: Bool) async throws -> [NuGetPackage] {
        let service: URL
        if let cached = await SearchServiceCache.shared.url {
            service = cached
        } else {
            let (index, _) = try await URLSession.shared.data(from: serviceIndex)
            guard let found = searchService(inIndex: index) else { throw URLError(.badServerResponse) }
            await SearchServiceCache.shared.set(found)
            service = found
        }
        let (data, _) = try await URLSession.shared.data(from: searchURL(service: service, query: query, prerelease: prerelease))
        return parseSearch(data)
    }
}

private actor SearchServiceCache {
    static let shared = SearchServiceCache()
    var url: URL?
    func set(_ url: URL) { self.url = url }
}
