import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var settings: Settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text("Chat2MD")
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            // Status Graph
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 48 Syncs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                StatusGraphView(entries: syncService.recentHistory)
                    .frame(height: 24)
                HStack {
                    Spacer()
                    Text("now")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal)

            // Last sync info
            if syncService.lastSyncTime != nil, syncService.watchingProjectsCount > 0 {
                let count = syncService.watchingProjectsCount
                Text("Watching \(count) \(count == 1 ? "file" : "files")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            if let error = syncService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Divider()

            // Actions
            VStack(spacing: 4) {
                Button(action: { syncService.syncNow() }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Sync Now")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .contentShape(Rectangle())

                Button(action: openDestination) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Open Destination")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .contentShape(Rectangle())

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings...")
                        Spacer()
                        Text("⌘,")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }

            Divider()

            // Toggle and Quit
            Toggle(isOn: $settings.syncEnabled) {
                Text("Enable Sync")
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .onChange(of: settings.syncEnabled) { _, newValue in
                if newValue {
                    syncService.startPeriodicSync()
                } else {
                    syncService.stopPeriodicSync()
                }
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Quit Chat2MD")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .frame(width: 300)
    }

    private var statusIcon: String {
        switch syncService.status {
        case .idle: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch syncService.status {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }

    private var statusText: String {
        switch syncService.status {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .error: return "Error"
        }
    }

    private func openDestination() {
        let path = settings.expandedDestinationPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
