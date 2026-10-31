import CSharpIDECore
import SwiftUI

/// Sidebar page: projects with their project references and NuGet packages.
struct SolutionView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(workspace.solutions.first.map { ($0 as NSString).lastPathComponent }
                     ?? (workspace.projects.isEmpty ? "No projects" : "\(workspace.projects.count) projects"))
                    .font(.headline).lineLimit(1)
                Spacer()
                if workspace.isCheckingOutdated {
                    ProgressView().controlSize(.small)
                } else {
                    Button { workspace.checkOutdatedPackages() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderless)
                        .help("Check NuGet packages for updates")
                        .disabled(workspace.projects.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            List {
                ForEach(workspace.projects) { project in
                    ProjectRow(project: project)
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear { workspace.refreshProjects() }
    }
}

private struct ProjectRow: View {
    @Environment(Workspace.self) private var workspace
    let project: DotnetProject
    @State private var isExpanded = true
    @State private var dependenciesExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            DisclosureGroup(isExpanded: $dependenciesExpanded) {
                ForEach(project.projectReferences, id: \.self) { reference in
                    Label(((reference as NSString).lastPathComponent as NSString).deletingPathExtension,
                          systemImage: "cube")
                        .help(reference)
                        .onTapGesture(count: 2) { workspace.openProjectFile(reference) }
                        .contextMenu { Button("Open Project File") { workspace.openProjectFile(reference) } }
                }
                ForEach(project.packages) { package in
                    PackageRow(project: project, package: package)
                }
                if project.packages.isEmpty, project.projectReferences.isEmpty {
                    Text("No dependencies").foregroundStyle(.secondary)
                }
            } label: {
                Label("Dependencies", systemImage: "link")
                    .contextMenu { addPackageButton }
            }
        } label: {
            HStack(spacing: 4) {
                Label(project.name, systemImage: icon)
                    .fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(project.targetFrameworks.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help("\(project.path) — \(summary)")
            .onTapGesture(count: 2) { workspace.openProjectFile(project.path) }
            .contextMenu {
                Button("Open Project File") { workspace.openProjectFile(project.path) }
                addPackageButton
                Divider()
                Button("Build Project") { workspace.runDotnet(["build", project.path]) }
                if project.isTest {
                    Button("Run Tests") { workspace.runTests(.project(project.path)) }
                } else if project.isRunnable {
                    Button("Run Project") { workspace.runDotnet(["run", "--project", project.path]) }
                }
            }
        }
    }

    private var addPackageButton: some View {
        Button("Add NuGet Package…") { workspace.addingPackageToProject = project.path }
    }

    private var icon: String {
        project.isTest ? "checkmark.diamond" : project.isRunnable ? "terminal" : "shippingbox"
    }

    private var summary: String {
        let kind = project.isTest ? "Test" : project.isRunnable ? "App" : "Library"
        return ([kind] + project.targetFrameworks).joined(separator: " · ")
    }
}

private struct PackageRow: View {
    @Environment(Workspace.self) private var workspace
    let project: DotnetProject
    let package: PackageReference

    var body: some View {
        let latest = workspace.outdatedPackages[project.path]?[package.name]
        HStack(spacing: 4) {
            Label(package.name, systemImage: "shippingbox.fill")
                .lineLimit(1).truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let latest {
                Text("↑\(latest)")
                    .font(.caption.monospaced()).foregroundStyle(.orange)
                    .lineLimit(1).fixedSize()
            } else {
                Text(package.version ?? "central")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(latest.map { "\(package.name) \(package.version ?? "") — \($0) available" }
              ?? "\(package.name) \(package.version ?? "(central version)")")
        .contextMenu {
            if let latest {
                Button("Update to \(latest)") { workspace.updatePackage(package.name, in: project.path) }
            }
            Button("View on nuget.org") {
                if let url = URL(string: "https://www.nuget.org/packages/\(package.name)") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Remove Package") { workspace.removePackage(package.name, from: project.path) }
        }
    }
}

/// Searches nuget.org and adds the chosen package to a project.
struct AddPackageSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let project: String
    @State private var query = ""
    @State private var prerelease = false
    @State private var results: [NuGetPackage] = []
    @State private var selection: String?
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search nuget.org", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Toggle("Prerelease", isOn: $prerelease)
                    .onChange(of: prerelease) { search() }
            }
            .padding(12)
            Divider()
            Group {
                if isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, selection: $selection) { package in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(package.id).fontWeight(.semibold)
                                if package.verified {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).help("Verified owner")
                                }
                                Spacer()
                                Text(package.version).font(.caption.monospaced())
                                Text(Self.downloads(package.totalDownloads)).font(.caption).foregroundStyle(.secondary)
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                            Text(package.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .tag(package.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("Add to \((project as NSString).lastPathComponent)").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Package") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || workspace.isRunning)
            }
            .padding(10)
        }
        .frame(width: 620, height: 440)
        .onAppear {
            query = Self.initialQuery
            if !query.isEmpty { search() }
        }
    }

    /// Lets snapshot runs pre-fill the search.
    static var initialQuery: String {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot-nuget"), i + 1 < args.count else { return "" }
        return args[i + 1]
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        error = nil
        Task {
            do {
                results = try await NuGet.search(text, prerelease: prerelease)
                if results.isEmpty { error = "No packages match “\(text)”." }
                selection = results.first?.id
            } catch {
                self.error = "Search failed: \(error.localizedDescription)"
            }
            isSearching = false
        }
    }

    private func add() {
        guard let id = selection else { return }
        let version = results.first { $0.id == id }?.version
        workspace.addPackage(id, version: version, to: project)
        dismiss()
    }

    static func downloads(_ count: Int) -> String {
        switch count {
        case 1_000_000_000...: String(format: "%.1fB", Double(count) / 1e9)
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1e6)
        case 1_000...: String(format: "%.0fK", Double(count) / 1e3)
        default: "\(count)"
        }
    }
}
