import Foundation

class ClaudeProvider: Provider {
    let type: ProviderType = .claude

    private var sessionIndexCache: [String: SessionIndex] = [:]

    // Patterns to skip (system/tool messages)
    private let systemMessagePatterns = [
        "<local-command",
        "<command-name>",
        "<system-reminder>",
        "<task-notification>",
        "<bash-stdout>",
        "<bash-stderr>",
        "<local-command-caveat>"
    ]

    // XML-like tags whose content should be stripped from messages
    private let stripTagPatterns = [
        "<skill>[\\s\\S]*?</skill>",
        "<proposed_plan>[\\s\\S]*?</proposed_plan>"
    ]

    // MARK: - Session Index for project name resolution

    struct SessionIndex: Codable {
        let entries: [SessionEntry]
    }

    struct SessionEntry: Codable {
        let sessionId: String
        let projectPath: String?
    }

    // MARK: - Provider Protocol

    func findSessionFiles(in basePath: String, maxAge: TimeInterval) throws -> [SessionFile] {
        let fm = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-maxAge)

        guard fm.fileExists(atPath: basePath) else {
            return []
        }

        var sessionFiles: [SessionFile] = []
        let projectFolders = try fm.contentsOfDirectory(atPath: basePath)

        for folder in projectFolders {
            let folderPath = (basePath as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = try findJSONLFiles(in: folderPath, excludingSubagents: true)

            for filePath in files {
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date,
                      let fileSize = attrs[.size] as? Int else { continue }

                // Skip old sessions
                if modDate < cutoffDate { continue }

                sessionFiles.append(SessionFile(
                    path: filePath,
                    modificationDate: modDate,
                    size: fileSize
                ))
            }
        }

        return sessionFiles
    }

    func parseMessages(from file: SessionFile, afterLine: Int, since: Date?) -> ParseResult {
        guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
            return ParseResult(messages: [], totalLines: afterLine)
        }

        // Count newlines like shell's wc -l
        let totalLines = content.filter { $0 == "\n" }.count

        // No new lines
        guard totalLines > afterLine else {
            return ParseResult(messages: [], totalLines: totalLines)
        }

        // Get only new lines (after lastLine)
        let allLines = content.components(separatedBy: "\n")
        let newLines = Array(allLines.dropFirst(afterLine).prefix(totalLines - afterLine))

        var messages: [ConversationMessage] = []
        let decoder = JSONDecoder()

        for line in newLines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let message = try decoder.decode(ClaudeMessage.self, from: data)

                // Only process user and assistant messages
                guard message.isUserMessage || message.isAssistantMessage else { continue }

                // Filter by date if provided
                if let filterDate = since, let msgDate = message.parsedTimestamp {
                    if msgDate < filterDate { continue }
                }

                // Get text blocks (each block becomes a separate message)
                let textBlocks = message.textBlocks
                guard !textBlocks.isEmpty else { continue }

                let role: ConversationMessage.MessageRole = message.isUserMessage ? .user : .assistant

                for var text in textBlocks {
                    guard !text.isEmpty else { continue }

                    // Strip system tags (e.g. <skill>...</skill>)
                    text = stripSystemTags(text)
                    guard !text.isEmpty else { continue }

                    // Skip system messages
                    if shouldSkipMessage(text) { continue }

                    // Skip "No response requested"
                    if message.isAssistantMessage && text.lowercased().hasPrefix("no response requested") {
                        continue
                    }

                    messages.append(ConversationMessage(
                        role: role,
                        content: text,
                        timestamp: message.parsedTimestamp
                    ))
                }
            } catch {
                // Skip malformed lines
                continue
            }
        }

        return ParseResult(messages: messages, totalLines: totalLines)
    }

    func resolveProjectName(for file: SessionFile) -> String {
        let projectFolder = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        let indexPath = projectFolder.appendingPathComponent("sessions-index.json")

        // Try to get projectPath from sessions-index.json
        if let index = loadSessionIndex(at: indexPath.path) {
            let sessionId = URL(fileURLWithPath: file.path)
                .deletingPathExtension()
                .lastPathComponent

            if let entry = index.entries.first(where: { $0.sessionId == sessionId }),
               let projectPath = entry.projectPath {
                // Return last component of projectPath
                return URL(fileURLWithPath: projectPath).lastPathComponent
            }
        }

        // Fallback: extract cwd from session file content
        if let cwd = resolveCWDFromSessionFile(at: file.path) {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        // Fallback: use folder name parsing
        let folderName = projectFolder.lastPathComponent
        return resolveFromFolderName(folderName)
    }

    func resolveMetadata(for file: SessionFile) -> SessionMetadata {
        let fileURL = URL(fileURLWithPath: file.path)
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        let shortSessionId = String(sessionId.prefix(8))

        let projectFolder = fileURL.deletingLastPathComponent()
        let indexPath = projectFolder.appendingPathComponent("sessions-index.json")

        var cwd: String? = nil
        if let index = loadSessionIndex(at: indexPath.path),
           let entry = index.entries.first(where: { $0.sessionId == sessionId }) {
            cwd = entry.projectPath
        }
        if cwd == nil {
            cwd = resolveCWDFromSessionFile(at: file.path)
        }

        return SessionMetadata(sessionId: shortSessionId, workingDirectory: cwd)
    }

    func clearCache() {
        sessionIndexCache.removeAll()
    }

    // MARK: - Private Helpers

    private func findJSONLFiles(in folderPath: String, excludingSubagents: Bool) throws -> [String] {
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
                    // Recursively search subdirectories
                    let subFiles = try findJSONLFiles(in: itemPath, excludingSubagents: excludingSubagents)
                    sessionFiles.append(contentsOf: subFiles)
                } else if item.hasSuffix(".jsonl") {
                    sessionFiles.append(itemPath)
                }
            }
        }

        return sessionFiles
    }

    private func shouldSkipMessage(_ text: String) -> Bool {
        for pattern in systemMessagePatterns {
            if text.contains(pattern) {
                return true
            }
        }
        return false
    }

    private func stripSystemTags(_ text: String) -> String {
        var result = text
        for pattern in stripTagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveFromFolderName(_ folderName: String) -> String {
        // Fallback when sessions-index.json is unavailable.
        // Folder names encode paths with dashes (e.g. "-Users-jay-Dev-project"),
        // so extract a best-effort project token from the tail.
        guard folderName.hasPrefix("-") else {
            return folderName
        }
        let components = folderName
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)

        guard let last = components.last else { return folderName }

        // Preserve common "*-YYYYMMDD" suffixes (e.g. "projects-20260209")
        if components.count >= 2,
           last.count == 8,
           last.allSatisfy({ $0.isNumber }) {
            return "\(components[components.count - 2])-\(last)"
        }

        return last
    }

    private func resolveCWDFromSessionFile(at path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        // Some files start with snapshot/system rows. Scan early lines for cwd.
        for line in content.split(separator: "\n").prefix(200) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = String(trimmed).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cwd = obj["cwd"] as? String,
                  !cwd.isEmpty else {
                continue
            }
            return cwd
        }

        return nil
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
}
