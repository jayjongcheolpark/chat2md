import Foundation

class SyncHistoryStore {
    private var history: SyncHistory
    private let fileURL: URL

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = homeDir.appendingPathComponent(".chat2md/history.json")
        self.history = SyncHistory()
        load()
    }

    func addEntry(_ entry: SyncHistoryEntry) {
        history.add(entry)
        save()
    }

    func addSuccess(filesProcessed: Int) {
        addEntry(SyncHistoryEntry(status: .success, filesProcessed: filesProcessed))
    }

    func addFailure(error: String) {
        addEntry(SyncHistoryEntry(status: .failure, errorMessage: error))
    }

    func addSkipped() {
        addEntry(SyncHistoryEntry(status: .skipped))
    }

    func getHistory() -> SyncHistory {
        return history
    }

    func getRecentEntries() -> [SyncHistoryEntry] {
        return history.entries
    }

    var lastEntry: SyncHistoryEntry? {
        return history.lastEntry
    }

    func clear() {
        history = SyncHistory()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            history = try JSONDecoder().decode(SyncHistory.self, from: data)
        } catch {
            print("Failed to load sync history: \(error)")
            history = SyncHistory()
        }
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save sync history: \(error)")
        }
    }
}
