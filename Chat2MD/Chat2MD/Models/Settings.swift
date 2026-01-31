import Foundation
import SwiftUI

class Settings: ObservableObject {
    @AppStorage("destinationPath") var destinationPath: String = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/vault/claude"
    @AppStorage("claudeProjectsPath") var claudeProjectsPath: String = "~/.claude/projects"
    @AppStorage("syncIntervalSeconds") var syncIntervalSeconds: Int = 5
    @AppStorage("syncEnabled") var syncEnabled: Bool = true
    @AppStorage("sessionMaxAgeMinutes") var sessionMaxAgeMinutes: Int = 60
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    var expandedDestinationPath: String {
        (destinationPath as NSString).expandingTildeInPath
    }

    var expandedClaudeProjectsPath: String {
        (claudeProjectsPath as NSString).expandingTildeInPath
    }

    // MARK: - Path Validation

    /// Validates that a path is safe (no path traversal, absolute path)
    func isPathSafe(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        // Must be absolute path and not contain path traversal
        return expanded.hasPrefix("/") && !expanded.contains("/../") && !expanded.hasSuffix("/..")
    }

    var isDestinationPathValid: Bool {
        isPathSafe(destinationPath)
    }

    var isClaudeProjectsPathValid: Bool {
        isPathSafe(claudeProjectsPath)
    }
}
