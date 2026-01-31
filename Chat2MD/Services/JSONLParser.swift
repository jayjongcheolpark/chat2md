import Foundation

class JSONLParser {
    private let systemMessagePatterns = [
        "<local-command",
        "<command-name>",
        "<system-reminder>",
        "<task-notification>",
        "<bash-stdout>",
        "<bash-stderr>",
        "<local-command-caveat>"
    ]

    struct ParseResult {
        let messages: [ConversationMessage]
        let totalLines: Int
    }

    /// Parse only new lines from the file starting after lastLine
    func parseNewLines(at path: String, afterLine lastLine: Int, since date: Date?) -> ParseResult {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ParseResult(messages: [], totalLines: lastLine)
        }

        // Count newlines like shell's wc -l
        let totalLines = content.filter { $0 == "\n" }.count

        // No new lines
        guard totalLines > lastLine else {
            return ParseResult(messages: [], totalLines: totalLines)
        }

        // Get only new lines (after lastLine) - like shell's tail -n +$((lastLine + 1))
        let allLines = content.components(separatedBy: "\n")
        let newLines = Array(allLines.dropFirst(lastLine).prefix(totalLines - lastLine))

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
                if let filterDate = date, let msgDate = message.parsedTimestamp {
                    if msgDate < filterDate { continue }
                }

                // Get text blocks (each block becomes a separate message, like shell script)
                let textBlocks = message.textBlocks
                guard !textBlocks.isEmpty else { continue }

                let role: ConversationMessage.MessageRole = message.isUserMessage ? .user : .assistant

                for text in textBlocks {
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

    private func shouldSkipMessage(_ text: String) -> Bool {
        for pattern in systemMessagePatterns {
            if text.contains(pattern) {
                return true
            }
        }
        return false
    }
}
