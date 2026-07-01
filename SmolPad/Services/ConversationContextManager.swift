import Foundation

struct ManagedConversationContext {
    let systemPrompt: String
    let summaryMessage: ChatMessage?
    let recentMessages: [ChatMessage]
    let userPrompt: String
}

struct CompactedConversationMemory {
    let summary: String
    let recentMessages: [ChatMessage]
}

enum ConversationContextManager {
    private static let maxRecentMessages = 8
    private static let maxSummaryCharacters = 1800
    private static let maxSnippetCharacters = 220

    static func buildContext(
        prompt: String,
        history: [ChatMessage],
        summary: String,
        hasAttachedImage: Bool
    ) -> ManagedConversationContext {
        let compacted = compact(history: history, existingSummary: summary)
        let systemPrompt = buildSystemPrompt(hasAttachedImage: hasAttachedImage)
        let summaryMessage: ChatMessage?

        if compacted.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summaryMessage = nil
        } else {
            summaryMessage = ChatMessage(
                role: .system,
                content: """
                Conversation summary for the same note:
                \(compacted.summary)
                """
            )
        }

        let context = ManagedConversationContext(
            systemPrompt: systemPrompt,
            summaryMessage: summaryMessage,
            recentMessages: compacted.recentMessages,
            userPrompt: buildUserPrompt(prompt: prompt, hasAttachedImage: hasAttachedImage)
        )

        DiagnosticsLogger.context.debug(
            """
            Built context historyCount=\(history.count, privacy: .public) recentCount=\(context.recentMessages.count, privacy: .public) summaryChars=\(compacted.summary.count, privacy: .public) hasImage=\(hasAttachedImage, privacy: .public)
            userPrompt=\(DiagnosticsLogger.truncated(context.userPrompt), privacy: .public)
            """
        )

        return context
    }

    static func compact(
        history: [ChatMessage],
        existingSummary: String,
        maxRecentMessages: Int = maxRecentMessages
    ) -> CompactedConversationMemory {
        guard history.count > maxRecentMessages else {
            return CompactedConversationMemory(
                summary: trimSummary(existingSummary),
                recentMessages: history
            )
        }

        let splitIndex = history.count - maxRecentMessages
        let olderMessages = Array(history[..<splitIndex])
        let recentMessages = Array(history[splitIndex...])

        let newSummaryPart = summarize(messages: olderMessages)
        let mergedSummary = [existingSummary, newSummaryPart]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        DiagnosticsLogger.context.debug(
            "Compacted conversation history originalCount=\(history.count, privacy: .public) recentCount=\(recentMessages.count, privacy: .public) olderCount=\(olderMessages.count, privacy: .public) mergedSummaryChars=\(mergedSummary.count, privacy: .public)"
        )

        return CompactedConversationMemory(
            summary: trimSummary(mergedSummary),
            recentMessages: recentMessages
        )
    }

    private static func buildSystemPrompt(hasAttachedImage: Bool) -> String {
        var sections: [String] = [
            """
            You are a careful AI assistant in a multi-turn conversation about the user's note.
            """,
            """
            Use previous turns only for follow-ups, references like "that", "this", or "what did I ask before".
            """,
            """
            If the user asks what they just said or asked previously, answer directly from the chat history.
            """,
            """
            Do not say context is missing if the needed context is already present in the recent chat or summary.
            """,
            """
            Keep answers readable, faithful to the evidence, and concise unless the user asks for more detail.
            Prefer plain readable math notation over raw LaTeX unless exact notation is necessary.
            """
        ]

        if hasAttachedImage {
            sections.append(
                """
                A new image is attached on this turn. Treat the image as the primary source of truth for the current note.
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private static func buildUserPrompt(prompt: String, hasAttachedImage: Bool) -> String {
        if hasAttachedImage {
            return """
            The attached image is the note the user is asking about.
            User request:
            \(prompt)
            """
        }

        return """
        User request:
        \(prompt)
        """
    }

    private static func summarize(messages: [ChatMessage]) -> String {
        messages.compactMap { message in
            let content = normalizedSnippet(from: message.content)
            guard !content.isEmpty else { return nil }

            switch message.role {
            case .user:
                return "- User asked: \(content)"
            case .assistant:
                return "- Assistant answered: \(content)"
            case .system:
                return nil
            }
        }
        .joined(separator: "\n")
    }

    private static func normalizedSnippet(from content: String) -> String {
        let flattened = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else { return "" }
        if flattened.count <= maxSnippetCharacters {
            return flattened
        }

        let end = flattened.index(flattened.startIndex, offsetBy: maxSnippetCharacters)
        return String(flattened[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func trimSummary(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxSummaryCharacters else { return trimmed }

        let start = trimmed.index(trimmed.endIndex, offsetBy: -maxSummaryCharacters)
        let suffix = String(trimmed[start...])

        if let newline = suffix.firstIndex(of: "\n") {
            return String(suffix[suffix.index(after: newline)...])
        }

        return suffix
    }
}
