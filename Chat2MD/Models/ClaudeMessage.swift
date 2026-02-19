import Foundation

struct ClaudeMessage: Codable {
    let type: String
    let message: MessageContent?
    let timestamp: String?

    struct MessageContent: Codable {
        let role: String?
        let content: ContentValue?
    }

    // Content can be either a string or an array of content blocks
    enum ContentValue: Codable {
        case string(String)
        case array([ContentBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let arr = try? container.decode([ContentBlock].self) {
                self = .array(arr)
            } else {
                self = .string("")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let str):
                try container.encode(str)
            case .array(let arr):
                try container.encode(arr)
            }
        }

        var textContent: String? {
            switch self {
            case .string(let str):
                return str
            case .array(let blocks):
                // Extract text from blocks with type == "text"
                let texts = blocks.compactMap { block -> String? in
                    if block.type == "text" {
                        return block.text
                    }
                    return nil
                }
                return texts.isEmpty ? nil : texts.joined(separator: "\n")
            }
        }
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    var isUserMessage: Bool {
        return type == "user"
    }

    var isAssistantMessage: Bool {
        return type == "assistant"
    }

    /// Return joined text blocks for user/assistant messages.
    var textContent: String? {
        let blocks = textBlocks
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }

    /// Return each text block separately (user and assistant).
    /// Ignores non-text blocks like tool_use/tool_result.
    var textBlocks: [String] {
        guard let content = message?.content else { return [] }

        switch content {
        case .string(let str):
            // User text messages have string content
            return isUserMessage ? [str] : []
        case .array(let blocks):
            // Both user and assistant can contain text blocks in array form.
            guard isUserMessage || isAssistantMessage else { return [] }
            return blocks.compactMap { block -> String? in
                if block.type == "text" {
                    return block.text
                }
                return nil
            }
        }
    }

    var parsedTimestamp: Date? {
        guard let ts = timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: ts) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: ts)
    }
}

struct ConversationMessage {
    let role: MessageRole
    let content: String
    let timestamp: Date?

    enum MessageRole: String {
        case user
        case assistant
    }
}
