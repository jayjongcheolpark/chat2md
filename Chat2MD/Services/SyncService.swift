import Foundation
import Combine

class SyncService: ObservableObject {
    enum SyncStatus {
        case idle
        case syncing
        case error
    }

    @Published var status: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var lastError: String?
    @Published var watchingProjectsCount: Int = 0

    var settings: Settings
    private let converter = MarkdownConverter()
    private let historyStore = SyncHistoryStore()
    private let providerRegistry = ProviderRegistry()

    private var timerSource: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.jaypark.chat2md.timer", qos: .utility)
    private var syncState: SyncState

    // Constants matching shell script
    private let sessionMinSizeBytes = 1000

    init(settings: Settings) {
        self.settings = settings
        self.syncState = SyncState.load()
    }

    var recentHistory: [SyncHistoryEntry] {
        historyStore.getRecentEntries()
    }

    func startPeriodicSync() {
        stopPeriodicSync()

        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(
            deadline: .now(),
            repeating: .seconds(settings.syncIntervalSeconds),
            leeway: .seconds(1)
        )
        source.setEventHandler { [weak self] in
            self?.performSync()
        }
        timerSource = source
        source.resume()
    }

    func stopPeriodicSync() {
        timerSource?.cancel()
        timerSource = nil
    }

    func syncNow() {
        performSync()
    }

    func resetState() {
        // Clear sync state
        syncState = SyncState()
        syncState.save()

        // Clear history
        historyStore.clear()

        // Re-sync
        performSync()
    }

    private func performSync() {
        guard settings.syncEnabled else {
            historyStore.addSkipped()
            return
        }

        DispatchQueue.main.async {
            self.status = .syncing
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            do {
                let result = try self.syncAllSessions()
                DispatchQueue.main.async {
                    self.status = .idle
                    self.lastSyncTime = Date()
                    self.lastError = nil
                    self.watchingProjectsCount = result.watchingCount
                }
                if result.syncedCount > 0 {
                    self.historyStore.addSuccess(filesProcessed: result.syncedCount, providers: result.syncedProviders)
                } else {
                    self.historyStore.addSkipped()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .error
                    self.lastError = error.localizedDescription
                }
                self.historyStore.addFailure(error: error.localizedDescription)
            }
        }
    }

    private struct SyncResult {
        let syncedCount: Int
        let watchingCount: Int
        let syncedProviders: [ProviderType]
    }

    private func syncAllSessions() throws -> SyncResult {
        // Validate destination path
        guard settings.isDestinationPathValid else {
            throw SyncError.invalidPath("Destination path")
        }

        var totalSyncedCount = 0
        var syncedProviders: Set<ProviderType> = []
        let enabledProviders = providerRegistry.enabledProviders(settings: settings)

        // Clear caches at start of sync cycle
        for provider in enabledProviders {
            provider.clearCache()
        }

        let todayStart = Calendar.current.startOfDay(for: Date())

        // Cold start: state is empty (first sync, after reset, or app just started)
        // Use time since today start to get all of today's conversations
        // Warm sync: use configured maxAge for efficiency
        let isColdStart = syncState.sessionStates.isEmpty
        let maxAge: TimeInterval
        if isColdStart {
            maxAge = Date().timeIntervalSince(todayStart)
        } else {
            maxAge = Double(settings.sessionMaxAgeMinutes) * 60
        }
        let messageCutoffDate = Date().addingTimeInterval(-maxAge)

        // Sync each enabled provider
        for provider in enabledProviders {
            let providerPath = settings.expandedPath(for: provider.type)

            // Validate provider path
            guard settings.isPathValid(for: provider.type) else {
                continue  // Skip invalid paths silently
            }

            do {
                let sessionFiles = try provider.findSessionFiles(in: providerPath, maxAge: maxAge)

                for file in sessionFiles {
                    // Skip small files
                    if file.size < sessionMinSizeBytes { continue }

                    // Skip if file hasn't been modified since last sync
                    if let lastSyncTime = syncState.getLastSyncedTimestamp(for: file.path),
                       file.modificationDate <= lastSyncTime {
                        continue
                    }

                    // Get last synced line for this session
                    let lastLine = syncState.getLastLine(for: file.path)

                    // Parse only new messages
                    let result = provider.parseMessages(from: file, afterLine: lastLine, since: messageCutoffDate)

                    // Skip if no new messages
                    guard !result.messages.isEmpty else {
                        // Still update line count even if no valid messages
                        if result.totalLines > lastLine {
                            syncState.updateSession(file.path, lastLine: result.totalLines)
                        }
                        continue
                    }

                    let projectName = provider.resolveProjectName(for: file)
                    let metadata = provider.resolveMetadata(for: file)

                    // Append to markdown file
                    try appendMarkdown(
                        messages: result.messages,
                        projectName: projectName,
                        providerType: provider.type,
                        providerDisplayName: provider.displayName,
                        metadata: metadata
                    )
                    totalSyncedCount += 1
                    syncedProviders.insert(provider.type)

                    // Update sync state with new line count
                    syncState.updateSession(file.path, lastLine: result.totalLines)
                }
            } catch {
                // Log error but continue with other providers
                continue
            }
        }

        // Cleanup orphan entries (files that no longer exist)
        syncState.cleanupOrphans()
        syncState.save()

        return SyncResult(
            syncedCount: totalSyncedCount,
            watchingCount: syncState.sessionStates.count,
            syncedProviders: Array(syncedProviders)
        )
    }

    private func appendMarkdown(messages: [ConversationMessage], projectName: String, providerType: ProviderType, providerDisplayName: String, metadata: SessionMetadata) throws {
        let basePath = settings.expandedDestinationPath
        let fm = FileManager.default

        // Determine destination path and filename based on organization setting
        let destPath: String
        let filename: String

        switch settings.outputOrganization {
        case .flat:
            // vault/yyyy-mm-dd-provider-project-sessionid.md
            destPath = basePath
            filename = converter.generateFilename(projectName: projectName, sessionId: metadata.sessionId, date: Date(), providerID: providerType.rawValue, usePrefix: true)
        case .subfolder:
            // vault/provider/yyyy-mm-dd-project-sessionid.md
            destPath = (basePath as NSString).appendingPathComponent(providerType.rawValue)
            filename = converter.generateFilename(projectName: projectName, sessionId: metadata.sessionId, date: Date(), providerID: providerType.rawValue, usePrefix: false)
        }

        // Create destination directory if needed
        try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)

        let filePath = (destPath as NSString).appendingPathComponent(filename)

        let content = converter.convertForAppend(messages: messages, assistantName: providerDisplayName)
        let isNewFile = !fm.fileExists(atPath: filePath)

        // Append to file
        if isNewFile {
            // Create new file with frontmatter
            let frontmatter = converter.generateFrontmatter(provider: providerType, projectName: projectName, metadata: metadata)
            let fullContent = frontmatter + content
            try fullContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } else {
            // Append to existing file (no frontmatter)
            let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                fileHandle.write(data)
            }
        }
    }
}

enum SyncError: LocalizedError {
    case projectsPathNotFound
    case destinationPathNotFound
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .projectsPathNotFound:
            return "Claude projects path not found"
        case .destinationPathNotFound:
            return "Destination path not found"
        case .invalidPath(let name):
            return "\(name) contains invalid characters (path traversal not allowed)"
        }
    }
}
