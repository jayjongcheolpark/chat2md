import Foundation

class MarkdownConverter {
    /// Convert messages to markdown format for appending (matches shell script behavior)
    func convertForAppend(messages: [ConversationMessage]) -> String {
        var lines: [String] = []

        for message in messages {
            let prefix = message.role == .user ? "**User**:" : "**Claude**:"
            let content = message.content

            lines.append(prefix)
            // Table needs extra blank line to render properly
            if content.hasPrefix("|") {
                lines.append("")
            }
            lines.append(content)
            lines.append("")
            lines.append("")  // Two empty strings = one blank line after join
        }

        return lines.joined(separator: "\n")
    }

    func generateFilename(projectName: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let sanitizedProject = sanitizeFilename(projectName)
        return "\(dateString)-\(sanitizedProject).md"
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "-")
    }
}
