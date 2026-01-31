import Foundation

struct SyncState: Codable {
    var sessionStates: [String: SessionState]

    struct SessionState: Codable {
        let sessionPath: String
        var lastSyncedLine: Int
        var lastSyncedTimestamp: Date
    }

    init() {
        self.sessionStates = [:]
    }

    mutating func updateSession(_ path: String, lastLine: Int) {
        sessionStates[path] = SessionState(
            sessionPath: path,
            lastSyncedLine: lastLine,
            lastSyncedTimestamp: Date()
        )
    }

    func getLastLine(for path: String) -> Int {
        return sessionStates[path]?.lastSyncedLine ?? 0
    }

    func getLastSyncedTimestamp(for path: String) -> Date? {
        return sessionStates[path]?.lastSyncedTimestamp
    }

    mutating func cleanupOrphans() {
        let fm = FileManager.default
        sessionStates = sessionStates.filter { path, _ in
            fm.fileExists(atPath: path)
        }
    }

    static func load() -> SyncState {
        let url = SyncState.stateFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SyncState()
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SyncState.self, from: data)
        } catch {
            return SyncState()
        }
    }

    func save() {
        let url = SyncState.stateFileURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: url)
        } catch {
            print("Failed to save sync state: \(error)")
        }
    }

    private static var stateFileURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".chat2md/sync_state.json")
    }
}
