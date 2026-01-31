import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var syncService: SyncService

    private let launchAgentManager = LaunchAgentManager()

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PathSettingsView()
                .tabItem {
                    Label("Paths", systemImage: "folder")
                }

            DebugSettingsView()
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
        .environmentObject(settings)
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var syncService: SyncService

    private let launchAgentManager = LaunchAgentManager()
    @State private var launchAgentError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Sync", isOn: $settings.syncEnabled)
                    .onChange(of: settings.syncEnabled) { _, newValue in
                        if newValue {
                            syncService.startPeriodicSync()
                        } else {
                            syncService.stopPeriodicSync()
                        }
                    }

                Picker("Sync Interval", selection: $settings.syncIntervalSeconds) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }

                Picker("Session Max Age", selection: $settings.sessionMaxAgeMinutes) {
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("6 hours").tag(360)
                    Text("24 hours").tag(1440)
                }
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            try launchAgentManager.setEnabled(newValue)
                            launchAgentError = nil
                        } catch {
                            launchAgentError = error.localizedDescription
                            settings.launchAtLogin = !newValue
                        }
                    }

                if let error = launchAgentError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PathSettingsView: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Form {
            Section("Claude Projects") {
                HStack {
                    TextField("Path", text: $settings.claudeProjectsPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectFolder { path in
                            settings.claudeProjectsPath = path
                        }
                    }
                }
                Text("Location of Claude Code session files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Output Directory") {
                HStack {
                    TextField("Path", text: $settings.destinationPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectFolder { path in
                            settings.destinationPath = path
                        }
                    }
                }
                Text("Where to save markdown files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}

struct DebugSettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @State private var showResetConfirmation = false
    @State private var stateContent: String = ""
    @State private var lastRefresh: Date?

    private var stateFilePath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".chat2md/sync_state.json").path
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("State File")
                            .font(.headline)
                        Spacer()
                        Button(action: loadStateContent) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Refresh")
                    }

                    Text(stateFilePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    ScrollView {
                        Text(stateContent.isEmpty ? "No state file found" : stateContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)

                    if let refresh = lastRefresh {
                        Text("Last refreshed: \(refresh.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button("Reset Sync State") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
            } footer: {
                Text("Clears sync history and re-syncs all sessions from scratch. Use if messages are missing or duplicated.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadStateContent() }
        .alert("Reset Sync State?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                syncService.resetState()
                loadStateContent()
            }
        } message: {
            Text("This will clear all sync history and re-sync all sessions.")
        }
    }

    private func loadStateContent() {
        let url = URL(fileURLWithPath: stateFilePath)
        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: url) else {
            stateContent = "No state file found"
            lastRefresh = Date()
            return
        }

        // Pretty print JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            stateContent = prettyString
        } else {
            stateContent = String(data: data, encoding: .utf8) ?? "Unable to read state file"
        }
        lastRefresh = Date()
    }
}

#Preview {
    SettingsView()
        .environmentObject(Settings())
        .environmentObject(SyncService(settings: Settings()))
}
