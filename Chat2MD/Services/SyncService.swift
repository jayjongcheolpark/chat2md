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
    private let parser = JSONLParser()
    private let converter = MarkdownConverter()
    private let historyStore = SyncHistoryStore()
    private var projectNameResolver: ProjectNameResolver

    private var timerSource: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.jaypark.chat2md.timer", qos: .utility)
    private var syncState: SyncState

    // Constants matching shell script
    private let sessionMinSizeBytes = 1000

    init(settings: Settings) {
        self.settings = settings
        self.projectNameResolver = ProjectNameResolver(settings: settings)
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
                    self.historyStore.addSuccess(filesProcessed: result.syncedCount)
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
    }

    private func syncAllSessions() throws -> SyncResult {
        // Validate paths before syncing
        guard settings.isClaudeProjectsPathValid else {
            throw SyncError.invalidPath("Claude projects path")
        }
        guard settings.isDestinationPathValid else {
            throw SyncError.invalidPath("Destination path")
        }

        let projectsPath = settings.expandedClaudeProjectsPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectsPath) else {
            throw SyncError.projectsPathNotFound
        }

        let projectFolders = try fm.contentsOfDirectory(atPath: projectsPath)
        var syncedCount = 0

        let cutoffDate = Date().addingTimeInterval(-Double(settings.sessionMaxAgeMinutes) * 60)
        let todayStart = Calendar.current.startOfDay(for: Date())

        for folder in projectFolders {
            let folderPath = (projectsPath as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Find session files (excluding subagents directory)
            let sessionFiles = try findSessionFiles(in: folderPath, excludingSubagents: true)

            for sessionPath in sessionFiles {
                // Check file attributes
                let attrs = try fm.attributesOfItem(atPath: sessionPath)
                guard let modDate = attrs[.modificationDate] as? Date,
                      let fileSize = attrs[.size] as? Int else { continue }

                // Skip old sessions
                if modDate < cutoffDate { continue }

                // Skip small files
                if fileSize < sessionMinSizeBytes { continue }

                // Skip if file hasn't been modified since last sync
                if let lastSyncTime = syncState.getLastSyncedTimestamp(for: sessionPath),
                   modDate <= lastSyncTime {
                    continue
                }

                // Get last synced line for this session
                let lastLine = syncState.getLastLine(for: sessionPath)

                // Parse only new lines
                let result = parser.parseNewLines(at: sessionPath, afterLine: lastLine, since: todayStart)

                // Skip if no new messages
                guard !result.messages.isEmpty else {
                    // Still update line count even if no valid messages (to avoid re-parsing)
                    if result.totalLines > lastLine {
                        syncState.updateSession(sessionPath, lastLine: result.totalLines)
                    }
                    continue
                }

                let projectName = projectNameResolver.resolveProjectName(forSession: sessionPath)

                // Append to markdown file
                try appendMarkdown(messages: result.messages, projectName: projectName)
                syncedCount += 1

                // Update sync state with new line count
                syncState.updateSession(sessionPath, lastLine: result.totalLines)
            }
        }

        // Cleanup orphan entries (files that no longer exist)
        syncState.cleanupOrphans()
        syncState.save()

        return SyncResult(
            syncedCount: syncedCount,
            watchingCount: syncState.sessionStates.count
        )
    }

    private func findSessionFiles(in folderPath: String, excludingSubagents: Bool) throws -> [String] {
        let fm = FileManager.default
        var sessionFiles: [String] = []

        let contents = try fm.contentsOfDirectory(atPath: folderPath)

        for item in contents {
            let itemPath = (folderPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false

            if fm.fileExists(atPath: itemPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Skip subagents directory
                    if excludingSubagents && item == "subagents" {
                        continue
                    }
                    // Recursively search subdirectories (but not subagents)
                    let subFiles = try findSessionFiles(in: itemPath, excludingSubagents: excludingSubagents)
                    sessionFiles.append(contentsOf: subFiles)
                } else if item.hasSuffix(".jsonl") {
                    sessionFiles.append(itemPath)
                }
            }
        }

        return sessionFiles
    }

    private func appendMarkdown(messages: [ConversationMessage], projectName: String) throws {
        let destPath = settings.expandedDestinationPath
        let fm = FileManager.default

        // Create destination directory if needed
        try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)

        let filename = converter.generateFilename(projectName: projectName, date: Date())
        let filePath = (destPath as NSString).appendingPathComponent(filename)

        let content = converter.convertForAppend(messages: messages)

        // Append to file
        if fm.fileExists(atPath: filePath) {
            let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
            defer { try? fileHandle.close() }
            fileHandle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                fileHandle.write(data)
            }
        } else {
            // Create new file
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
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
