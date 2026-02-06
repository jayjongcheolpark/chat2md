import Foundation

class CodexProvider: Provider {
    let type: ProviderType = .codex

    // Patterns to skip (system/tool messages)
    private let systemMessagePatterns = [
        "<turn_aborted>"
    ]

    // XML-like tags whose content should be stripped from messages
    private let stripTagPatterns = [
        "<skill>[\\s\\S]*?</skill>",
        "<system-reminder>[\\s\\S]*?</system-reminder>",
        "<proposed_plan>[\\s\\S]*?</proposed_plan>"
    ]

    func findSessionFiles(in basePath: String, maxAge: TimeInterval) throws -> [SessionFile] {
        let fm = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-maxAge)

        guard fm.fileExists(atPath: basePath) else {
            return []
        }

        var sessionFiles: [SessionFile] = []

        // Codex stores sessions in ~/.codex/sessions/YYYY/MM/DD/*.jsonl
        let jsonlFiles = try findJSONLFilesRecursively(in: basePath, cutoffDate: cutoffDate)

        for filePath in jsonlFiles {
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

        return sessionFiles
    }

    private func findJSONLFilesRecursively(in folderPath: String, cutoffDate: Date) throws -> [String] {
        let fm = FileManager.default
        var jsonlFiles: [String] = []

        let contents = try fm.contentsOfDirectory(atPath: folderPath)

        // Check if this is a leaf folder (contains .jsonl files)
        let hasJsonlFiles = contents.contains { $0.hasSuffix(".jsonl") }

        // Only check folder date on leaf folders (intermediate folders like YYYY/MM don't update)
        if hasJsonlFiles {
            if let folderAttrs = try? fm.attributesOfItem(atPath: folderPath),
               let folderModDate = folderAttrs[.modificationDate] as? Date,
               folderModDate < cutoffDate {
                return []
            }
        }

        for item in contents {
            let itemPath = (folderPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false

            if fm.fileExists(atPath: itemPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    let subFiles = try findJSONLFilesRecursively(in: itemPath, cutoffDate: cutoffDate)
                    jsonlFiles.append(contentsOf: subFiles)
                } else if item.hasSuffix(".jsonl") {
                    jsonlFiles.append(itemPath)
                }
            }
        }

        return jsonlFiles
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

        // Get only new lines
        let allLines = content.components(separatedBy: "\n")
        let newLines = Array(allLines.dropFirst(afterLine).prefix(totalLines - afterLine))

        var messages: [ConversationMessage] = []
        let decoder = JSONDecoder()

        for line in newLines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let codexMsg = try decoder.decode(CodexMessage.self, from: data)

                // Only process user and assistant messages
                guard codexMsg.isUserMessage || codexMsg.isAssistantMessage else { continue }

                // Filter by date if provided
                if let filterDate = since, let msgDate = codexMsg.parsedTimestamp {
                    if msgDate < filterDate { continue }
                }

                guard var text = codexMsg.textContent, !text.isEmpty else { continue }

                // Strip system tags (e.g. <skill>...</skill>)
                text = stripSystemTags(text)
                guard !text.isEmpty else { continue }

                // Skip system messages
                if shouldSkipMessage(text) { continue }

                let role: ConversationMessage.MessageRole = codexMsg.isUserMessage ? .user : .assistant

                messages.append(ConversationMessage(
                    role: role,
                    content: text,
                    timestamp: codexMsg.parsedTimestamp
                ))
            } catch {
                // Skip malformed lines
                continue
            }
        }

        return ParseResult(messages: messages, totalLines: totalLines)
    }

    func resolveProjectName(for file: SessionFile) -> String {
        // Read first line to get session_meta with cwd
        if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
            let firstLine = content.components(separatedBy: "\n").first ?? ""
            if let data = firstLine.data(using: .utf8),
               let msg = try? JSONDecoder().decode(CodexMessage.self, from: data),
               msg.type == "session_meta",
               let cwd = msg.payload?.cwd {
                // Extract last path component as project name
                let projectName = URL(fileURLWithPath: cwd).lastPathComponent
                return "codex-\(projectName)"
            }
        }
        // Fallback: use short filename
        let filename = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
        return "codex-\(String(filename.suffix(12)))"
    }

    func resolveMetadata(for file: SessionFile) -> SessionMetadata {
        let fileURL = URL(fileURLWithPath: file.path)
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let shortSessionId = String(filename.suffix(12))

        var cwd: String? = nil
        // Read first line to get session_meta with cwd
        if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
            let firstLine = content.components(separatedBy: "\n").first ?? ""
            if let data = firstLine.data(using: .utf8),
               let msg = try? JSONDecoder().decode(CodexMessage.self, from: data),
               msg.type == "session_meta" {
                cwd = msg.payload?.cwd
            }
        }

        return SessionMetadata(sessionId: shortSessionId, workingDirectory: cwd)
    }

    func clearCache() {
        // Codex provider doesn't use caching
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
}
