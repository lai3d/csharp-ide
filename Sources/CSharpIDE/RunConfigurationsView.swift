import CSharpIDECore
import SwiftUI

/// Toolbar menu: pick the configuration ⌘R and ⌥⌘R use.
struct RunConfigurationPicker: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        Menu {
            ForEach(workspace.runConfigurations) { config in
                Button {
                    workspace.selectedRunConfigurationID = config.id
                } label: {
                    if config.id == workspace.selectedRunConfiguration?.id {
                        Label(config.name, systemImage: "checkmark")
                    } else {
                        Text(config.name)
                    }
                }
            }
            Divider()
            Button("Edit Configurations…") { workspace.isEditingRunConfigurations = true }
        } label: {
            Label(workspace.selectedRunConfiguration?.name ?? "No runnable project", systemImage: "terminal")
                .labelStyle(.titleAndIcon)
        }
        .help("Run configuration (⌘R runs it, ⌥⌘R debugs it)")
        .disabled(workspace.rootURL == nil)
    }
}

/// Sheet for adding/editing run configurations.
struct RunConfigurationsSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        @Bindable var workspace = workspace
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(workspace.runConfigurations) { Text($0.name).tag($0.id) }
                    }
                    HStack(spacing: 2) {
                        Button { add() } label: { Image(systemName: "plus") }
                        Button { remove() } label: { Image(systemName: "minus") }
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                }
                .frame(minWidth: 160, idealWidth: 180)

                Group {
                    if let index = workspace.runConfigurations.firstIndex(where: { $0.id == selection }) {
                        Form {
                            TextField("Name", text: $workspace.runConfigurations[index].name)
                            Picker("Project", selection: $workspace.runConfigurations[index].project) {
                                ForEach(projectChoices(including: workspace.runConfigurations[index].project), id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            Picker("Configuration", selection: $workspace.runConfigurations[index].configuration) {
                                Text("Debug").tag("Debug")
                                Text("Release").tag("Release")
                            }
                            .pickerStyle(.segmented)
                            Picker("Launch Profile", selection: $workspace.runConfigurations[index].launchProfile) {
                                Text("Default").tag("")
                                ForEach(profileChoices(for: workspace.runConfigurations[index]), id: \.self) { Text($0).tag($0) }
                            }
                            TextField("Arguments", text: $workspace.runConfigurations[index].arguments,
                                      prompt: Text("--port 8080 --name \"my app\""))
                                .font(.system(.body, design: .monospaced))
                            LabeledContent("Environment") {
                                TextEditor(text: $workspace.runConfigurations[index].environment)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 90)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                            }
                            Text("One KEY=value per line. Used by Run (⌘R) and Debug (⌥⌘R).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    } else {
                        Text("Select or add a configuration.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 470)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    if let selection { workspace.selectedRunConfigurationID = selection }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 720, height: 400)
        .onAppear {
            workspace.refreshProjects()
            selection = workspace.selectedRunConfiguration?.id
        }
    }

    private func projectChoices(including current: String) -> [String] {
        let paths = workspace.runnableProjects.map(\.path)
        return paths.contains(current) || current.isEmpty ? paths : [current] + paths
    }

    private func profileChoices(for config: RunConfiguration) -> [String] {
        guard let rootURL = workspace.rootURL, !config.project.isEmpty else { return [] }
        let profiles = LaunchSettings.profiles(forProject: rootURL.appendingPathComponent(config.project))
        return profiles.contains(config.launchProfile) || config.launchProfile.isEmpty ? profiles : [config.launchProfile] + profiles
    }

    private func add() {
        let project = workspace.runnableProjects.first
        let config = RunConfiguration(name: project?.name ?? "New Configuration", project: project?.path ?? "")
        workspace.runConfigurations.append(config)
        selection = config.id
    }

    private func remove() {
        workspace.runConfigurations.removeAll { $0.id == selection }
        selection = workspace.runConfigurations.first?.id
    }
}
