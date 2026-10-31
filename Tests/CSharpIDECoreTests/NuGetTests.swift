import Foundation
import Testing
@testable import CSharpIDECore

@Suite struct NuGetTests {
    @Test func parsesPackageAndProjectReferences() {
        let xml = """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup>
              <ItemGroup>
                <PackageReference Include="Serilog" Version="4.4.0" />
                <PackageReference Version="1.2.3" Include="Polly" />
                <PackageReference Include="Humanizer">
                  <Version>2.14.1</Version>
                </PackageReference>
                <PackageReference Include="Central" />
                <PackageReference Update="NotMine" Version="9" />
              </ItemGroup>
              <ItemGroup>
                <ProjectReference Include="..\\Lib\\Lib.csproj" />
              </ItemGroup>
            </Project>
            """
        let project = DotnetProjects.parse(xml: xml, path: "src/App/App.csproj")
        #expect(project.packages == [
            PackageReference(name: "Serilog", version: "4.4.0"), PackageReference(name: "Polly", version: "1.2.3"),
            PackageReference(name: "Humanizer", version: "2.14.1"), PackageReference(name: "Central", version: nil),
        ])
        #expect(project.projectReferences == ["src/Lib/Lib.csproj"])
        #expect(DotnetProjects.parse(xml: #"<Project><ItemGroup><ProjectReference Include="Core.csproj"/></ItemGroup></Project>"#,
                                     path: "Root.csproj").projectReferences == ["Core.csproj"])
    }

    @Test func parsesSearchAndServiceIndex() throws {
        let index = #"{"version":"3.0.0","resources":[{"@id":"https://x/reg","@type":"RegistrationsBaseUrl"},{"@id":"https://s/query","@type":"SearchQueryService/3.5.0"}]}"#
        let service = try #require(NuGet.searchService(inIndex: Data(index.utf8)))
        #expect(service.absoluteString == "https://s/query")
        let url = NuGet.searchURL(service: service, query: "serilog sinks", prerelease: false, take: 5)
        #expect(url.absoluteString == "https://s/query?q=serilog%20sinks&take=5&prerelease=false&semVerLevel=2.0.0")

        let search = #"{"totalHits":2,"data":[{"id":"Serilog","version":"4.4.0","description":"Logging","totalDownloads":3517861739,"verified":true},{"id":"Broken"}]}"#
        #expect(NuGet.parseSearch(Data(search.utf8)) == [
            NuGetPackage(id: "Serilog", version: "4.4.0", description: "Logging", totalDownloads: 3_517_861_739, verified: true),
        ])
    }

    @Test func parsesOutdatedReport() {
        let output = """
              Determining projects to restore...
            {
              "version": 1,
              "projects": [
                { "path": "/w/T/T.csproj", "frameworks": [
                  { "framework": "net8.0", "topLevelPackages": [
                    { "id": "xunit", "requestedVersion": "2.5.0", "resolvedVersion": "2.5.0", "latestVersion": "2.9.3" } ] },
                  { "framework": "net10.0", "topLevelPackages": [
                    { "id": "xunit", "requestedVersion": "2.5.0", "resolvedVersion": "2.5.0", "latestVersion": "2.9.3" } ] } ] },
                { "path": "/w/Lib/Lib.csproj", "frameworks": [] }
              ]
            }
            """
        #expect(NuGet.parseOutdated(output) == [OutdatedPackage(project: "/w/T/T.csproj", id: "xunit", requested: "2.5.0", latest: "2.9.3")])
        #expect(NuGet.parseOutdated("error: no restore").isEmpty)
    }
}
