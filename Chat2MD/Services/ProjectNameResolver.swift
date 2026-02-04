import Foundation

class ProjectNameResolver {
    private let settings: Settings
    private var sessionIndexCache: [String: SessionIndex] = [:]

    init(settings: Settings) {
        self.settings = settings
    }

    struct SessionIndex: Codable {
        let entries: [SessionEntry]
    }

    struct SessionEntry: Codable {
        let sessionId: String
        let projectPath: String?
    }

    /// Resolves project name from session file path using sessions-index.json
    func resolveProjectName(forSession sessionPath: String) -> String {
        let projectFolder = URL(fileURLWithPath: sessionPath).deletingLastPathComponent()
        let indexPath = projectFolder.appendingPathComponent("sessions-index.json")

        // Try to get projectPath from sessions-index.json
        if let index = loadSessionIndex(at: indexPath.path) {
            let sessionId = URL(fileURLWithPath: sessionPath)
                .deletingPathExtension()
                .lastPathComponent

            if let entry = index.entries.first(where: { $0.sessionId == sessionId }),
               let projectPath = entry.projectPath {
                // Return last component of projectPath
                return URL(fileURLWithPath: projectPath).lastPathComponent
            }
        }

        // Fallback: use folder name parsing
        let folderName = projectFolder.lastPathComponent
        return resolveFromFolderName(folderName)
    }

    /// Fallback: resolve from folder name like "-Users-jaypark-Developer-myproject"
    private func resolveFromFolderName(_ folderName: String) -> String {
        // If doesn't start with dash, it's already the project name
        guard folderName.hasPrefix("-") else {
            return folderName
        }

        // Split by dash and progressively build path
        let components = folderName.split(separator: "-", omittingEmptySubsequences: false)
        var pathSoFar = ""
        var remainingStartIndex = 1  // Skip first empty element

        for i in 1..<components.count {
            let nextPath = pathSoFar + "/" + components[i]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: nextPath, isDirectory: &isDirectory),
               isDirectory.boolValue {
                pathSoFar = nextPath
                remainingStartIndex = i + 1
            } else {
                break
            }
        }

        // Join remaining components with dash as project name
        if remainingStartIndex < components.count {
            return components[remainingStartIndex...].joined(separator: "-")
        }

        // All components were path, return last one
        return String(components.last ?? "")
    }

    private func loadSessionIndex(at path: String) -> SessionIndex? {
        // Check cache
        if let cached = sessionIndexCache[path] {
            return cached
        }

        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let index = try? JSONDecoder().decode(SessionIndex.self, from: data) else {
            return nil
        }

        sessionIndexCache[path] = index
        return index
    }

    /// Clears the cache (call when sync starts)
    func clearCache() {
        sessionIndexCache.removeAll()
    }
}
