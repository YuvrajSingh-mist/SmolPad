import Foundation
import UIKit

enum AIError: LocalizedError {
    case missingConfig
    case badStatus(Int)
    case invalidURL
    case localNetworkDenied
    case timedOut(AIProvider)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfig: "API key or server URL is not configured."
        case .badStatus(let code): "Server returned HTTP \(code)."
        case .invalidURL: "Invalid server URL."
        case .localNetworkDenied:
            "SmolPad cannot reach devices on your local network. Turn on Local Network for SmolPad in Settings, then try again."
        case .timedOut(let provider):
            switch provider {
            case .ollama: "Local Ollama is still thinking. Try again with a smaller selected area, or wait for the model to warm up."
            case .mlx: "Local MLX is still thinking. Try again with a smaller selected area, or check that the MLX server is running."
            case .claude, .openai: "The request timed out."
            }
        case .cancelled:
            "The request was cancelled."
        }
    }
}

struct ChatMessage: Codable {
    enum Role: String, Codable {
        case user
        case assistant
        case system

        var displayName: String {
            switch self {
            case .user: "You"
            case .assistant: "AI"
            case .system: "System"
            }
        }
    }

    let role: Role
    let content: String
    let thinking: String?

    init(role: Role, content: String, thinking: String? = nil) {
        self.role = role
        self.content = content
        self.thinking = thinking
    }

    init(role: String, content: String, thinking: String? = nil) {
        self.init(role: Role(rawValue: role) ?? .user, content: content, thinking: thinking)
    }
}

struct StreamChunk {
    let text: String
    var isThinking: Bool = false
}

struct AIClient {
    static func send(
        image: UIImage?,
        query: String,
        config: AIConfig,
        history: [ChatMessage] = []
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        let maxDimension: CGFloat
        switch config.provider {
        case .ollama: maxDimension = 384
        case .mlx: maxDimension = 512
        case .claude, .openai: maxDimension = 1400
        }

        let b64: String?
        if let img = image {
            let preparedImage = resizedImage(img, maxDimension: maxDimension)
            let compressionQuality: CGFloat = config.provider == .ollama ? 0.68 : 0.82
            guard let jpeg = preparedImage.jpegData(compressionQuality: compressionQuality),
                  jpeg.count > 0 else {
                throw AIError.missingConfig
            }
            b64 = jpeg.base64EncodedString()
        } else {
            b64 = nil
        }

        let prompt = query
        let request = try buildRequest(b64: b64, prompt: prompt, config: config, history: history)

        return AsyncThrowingStream { continuation in
            let session = session(for: config.provider)
            let worker = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.badStatus(0))
                        return
                    }

                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: AIError.badStatus(http.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        if let chunk = parseLine(line, provider: config.provider) {
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    let nsError = error as NSError
                    if nsError.code == NSURLErrorTimedOut {
                        continuation.finish(throwing: AIError.timedOut(config.provider))
                    } else if isLocalNetworkDenied(nsError) {
                        continuation.finish(throwing: AIError.localNetworkDenied)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    private static func session(for provider: AIProvider) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        switch provider {
        case .ollama:
            configuration.timeoutIntervalForRequest = 360
            configuration.timeoutIntervalForResource = 420
        case .mlx:
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 240
        case .claude, .openai:
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 180
        }
        return URLSession(configuration: configuration)
    }

    private static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0, !size.width.isNaN, !size.height.isNaN,
              !size.width.isInfinite, !size.height.isInfinite else {
            return image
        }
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let targetWidth = max(1, (size.width * scale).rounded())
        let targetHeight = max(1, (size.height * scale).rounded())
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func buildRequest(
        b64: String?,
        prompt: String,
        config: AIConfig,
        history: [ChatMessage] = []
    ) throws -> URLRequest {
        let urlString: String
        let headers: [String: String]
        let body: Any

        switch config.provider {
        case .claude:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.anthropic.com/v1/messages"
            headers = [
                "x-api-key": config.apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ]
            var claudeContent: [[String: Any]] = []
            if let b64 {
                claudeContent.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": b64
                    ]
                ])
            }
            claudeContent.append(["type": "text", "text": prompt])
            body = [
                "model": config.model,
                "max_tokens": 2048,
                "stream": true,
                "messages": [["role": "user", "content": claudeContent]]
            ] as [String: Any]

        case .openai:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.openai.com/v1/chat/completions"
            headers = [
                "Authorization": "Bearer \(config.apiKey)",
                "Content-Type": "application/json"
            ]
            var openAIContent: [[String: Any]] = []
            if let b64 {
                openAIContent.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
            openAIContent.append(["type": "text", "text": prompt])
            body = [
                "model": config.model,
                "stream": true,
                "messages": [["role": "user", "content": openAIContent]]
            ] as [String: Any]

        case .mlx:
            guard !config.mlxURL.isEmpty else { throw AIError.missingConfig }
            urlString = "\(config.mlxURL)/v1/chat/completions"
            headers = ["Content-Type": "application/json"]
            let historyContext = buildHistoryContext(from: history)
            let systemText: String
            if b64 != nil {
                systemText = """
                You are a helpful AI assistant in an ongoing multi-turn conversation about the same selected handwritten note.
                Read the handwritten note carefully. If it contains math, transcribe the expression exactly as written, then solve it step by step with clear reasoning.
                Use the prior conversation to answer follow-up questions about what the user previously asked, what you previously answered, or what is shown in the selected note.
                If the user asks about the previous turn, rely on the conversation history instead of acting like this is a fresh chat.
                Keep formatting elegant and easy to scan with short paragraphs, bullets when useful, and math written cleanly.
                Prefer plain readable math notation over raw LaTeX. Only use LaTeX when it is genuinely necessary.
                \(historyContext.isEmpty ? "" : "\nConversation so far:\n\(historyContext)")
                """
            } else {
                systemText = """
                You are a helpful AI assistant in an ongoing multi-turn conversation.
                Use the prior conversation to answer follow-up questions about what the user previously asked or what you previously answered.
                Think step by step, explain your reasoning clearly, and provide accurate, well-formatted answers.
                Prefer plain readable math notation over raw LaTeX. Only use LaTeX when it is genuinely necessary.
                \(historyContext.isEmpty ? "" : "\nConversation so far:\n\(historyContext)")
                """
            }

            var messages: [[String: Any]] = [
                ["role": "system", "content": [["type": "text", "text": systemText]]]
            ]

            // Add conversation history (text-only)
            for msg in history {
                messages.append(["role": msg.role.rawValue, "content": [["type": "text", "text": msg.content]]])
            }

            // Current user message
            var userContent: [[String: Any]] = []
            if let b64 {
                userContent.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]])
            }
            userContent.append(["type": "text", "text": buildContextualPrompt(prompt: prompt, history: history, hasAttachedImage: b64 != nil)])
            messages.append(["role": "user", "content": userContent])

            body = [
                "model": config.model,
                "stream": true,
                "temperature": 0.1,
                "top_p": 0.95,
                "max_tokens": 512,
                "messages": messages
            ] as [String: Any]

        case .ollama:
            guard !config.ollamaURL.isEmpty else { throw AIError.missingConfig }
            urlString = "\(config.ollamaURL)/api/chat"
            headers = ["Content-Type": "application/json"]
            let ollamaPrompt = """
            Answer directly and briefly. If the image contains math, read the expression exactly, solve it, and show the final answer.

            User request: \(prompt)
            """
            body = [
                "model": config.model,
                "stream": true,
                "think": false,
                "options": [
                    "temperature": 0,
                    "num_ctx": 2048,
                    "num_predict": 160
                ],
                "messages": [[
                    "role": "user",
                    "content": ollamaPrompt,
                    "images": [b64]
                ]]
            ] as [String: Any]
        }

        guard let url = URL(string: urlString) else { throw AIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.provider == .ollama ? 360 : 180
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    private static func parseLine(_ line: String, provider: AIProvider) -> StreamChunk? {
        switch provider {
        case .claude:
            guard let json = streamJSONObject(from: line),
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String
            else { return nil }
            return StreamChunk(text: text)

        case .openai, .mlx:
            guard let json = streamJSONObject(from: line),
                  let choices = json["choices"] as? [[String: Any]]
            else { return nil }

            let choice = choices.first ?? [:]
            let delta = choice["delta"] as? [String: Any] ?? [:]

            if let reasoning = extractReasoning(from: delta), !reasoning.isEmpty {
                return StreamChunk(text: reasoning, isThinking: true)
            }

            if let text = extractContent(from: delta), !text.isEmpty {
                return StreamChunk(text: text)
            }

            if let message = choice["message"] as? [String: Any],
               let text = extractContent(from: message),
               !text.isEmpty {
                return StreamChunk(text: text)
            }

            if let text = choice["text"] as? String, !text.isEmpty {
                return StreamChunk(text: text)
            }

            return nil

        case .ollama:
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any]
            else { return nil }
            // Check for thinking token first (GLM, Kimi, etc.)
            if let thinking = message["thinking"] as? String, !thinking.isEmpty {
                return StreamChunk(text: thinking, isThinking: true)
            }
            if let text = message["content"] as? String, !text.isEmpty {
                return StreamChunk(text: text, isThinking: false)
            }
            return nil
        }
    }

    private static func streamJSONObject(from line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("event:"),
              trimmed != "data: [DONE]",
              trimmed != "[DONE]"
        else { return nil }

        let payload: String
        if trimmed.hasPrefix("data: ") {
            payload = String(trimmed.dropFirst(6))
        } else if trimmed.hasPrefix("data:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            payload = trimmed
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func isLocalNetworkDenied(_ error: NSError) -> Bool {
        guard error.code == NSURLErrorNotConnectedToInternet else { return false }
        return String(describing: error.userInfo).localizedCaseInsensitiveContains("local network prohibited")
    }

    private static func extractReasoning(from delta: [String: Any]) -> String? {
        if let reasoning = delta["reasoning_content"] as? String {
            return reasoning
        }
        if let reasoning = delta["reasoning"] as? String {
            return reasoning
        }
        if let reasoningItems = delta["reasoning_content"] as? [[String: Any]] {
            let text = extractText(from: reasoningItems)
            return text.isEmpty ? nil : text
        }
        if let reasoningItems = delta["reasoning"] as? [[String: Any]] {
            let text = extractText(from: reasoningItems)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func extractContent(from delta: [String: Any]) -> String? {
        if let text = delta["content"] as? String {
            return text
        }
        if let items = delta["content"] as? [[String: Any]] {
            let text = extractText(from: items)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func extractText(from items: [[String: Any]]) -> String {
        items.compactMap { item in
            if let text = item["text"] as? String {
                return text
            }
            if let content = item["content"] as? String {
                return content
            }
            return nil
        }
        .joined()
    }

    private static func buildHistoryContext(from history: [ChatMessage], limit: Int = 6) -> String {
        history.suffix(limit).map { message in
            let role: String
            switch message.role {
            case .assistant: role = "Assistant"
            case .user: role = "User"
            case .system: role = "System"
            }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return "\(role): \(content)"
        }
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func buildContextualPrompt(
        prompt: String,
        history: [ChatMessage],
        hasAttachedImage: Bool
    ) -> String {
        let historyContext = buildHistoryContext(from: history)
        var sections: [String] = []

        if hasAttachedImage {
            sections.append("The attached image is the same selected note for this chat unless the user selects a new region.")
        }

        if !historyContext.isEmpty {
            sections.append("Recent conversation:\n\(historyContext)")
        }

        sections.append("Current user request:\n\(prompt)")
        return sections.joined(separator: "\n\n")
    }
}
