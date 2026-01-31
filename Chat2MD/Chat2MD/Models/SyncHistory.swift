import Foundation

struct SyncHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let status: SyncStatus
    let filesProcessed: Int
    let errorMessage: String?

    enum SyncStatus: String, Codable {
        case success
        case failure
        case skipped
    }

    init(status: SyncStatus, filesProcessed: Int = 0, errorMessage: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.status = status
        self.filesProcessed = filesProcessed
        self.errorMessage = errorMessage
    }
}

struct SyncHistory: Codable {
    var entries: [SyncHistoryEntry]
    static let maxEntries = 48

    init() {
        self.entries = []
    }

    mutating func add(_ entry: SyncHistoryEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    var lastEntry: SyncHistoryEntry? {
        entries.last
    }
}
