import Foundation
import UIKit

enum AIError: LocalizedError {
    case missingConfig
    case missingServerURL(AIProvider)
    case badStatus(Int)
    case invalidURL
    case localNetworkDenied
    case timedOut(AIProvider)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfig: "API key or server URL is not configured."
        case .missingServerURL(let provider):
            switch provider {
            case .llamaCpp:
                "The embedded llama.cpp model files are missing. Add the GGUF model and mmproj files on-device, then try again."
            case .mlx:
                "The MLX server URL is empty. Open Settings and set the MLX server address."
            case .ollama:
                "The Ollama server URL is empty. Open Settings and set the Ollama server address."
            case .onDevice:
                "The on-device runtime is not configured."
            case .claude, .openai:
                "The API key is missing."
            }
        case .badStatus(let code): "Server returned HTTP \(code)."
        case .invalidURL: "Invalid server URL."
        case .localNetworkDenied:
            "SmolPad cannot reach devices on your local network. Turn on Local Network for SmolPad in Settings, then try again."
        case .timedOut(let provider):
            switch provider {
            case .onDevice: "The on-device model took too long to respond."
            case .llamaCpp: "The embedded llama.cpp model is still thinking. Try the 3B Q4 profile or reduce the selected area."
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
        history: [ChatMessage] = [],
        summary: String = ""
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        if config.provider == .onDevice {
            return try await OnDeviceTextClient.send(
                image: image,
                query: query,
                config: config,
                history: history,
                summary: summary
            )
        }

        if config.provider == .llamaCpp {
            return try await EmbeddedLlamaVisionClient.send(
                image: image,
                query: query,
                config: config,
                history: history,
                summary: summary
            )
        }

        DiagnosticsLogger.ai.info(
            "Preparing AI request provider=\(config.provider.rawValue, privacy: .public) model=\(config.model, privacy: .public) historyCount=\(history.count, privacy: .public) summaryChars=\(summary.count, privacy: .public) hasImage=\(image != nil, privacy: .public) query=\(DiagnosticsLogger.truncated(query), privacy: .public)"
        )
        let maxDimension: CGFloat
        switch config.provider {
        case .onDevice: maxDimension = 1400
        case .llamaCpp: maxDimension = 1024
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

        let prompt: String
        if config.inferencePath == .appleVisionOCRPlusText, let image {
            let transcript = try await AppleVisionOCRService.recognizeText(in: image)
            prompt = augmentedPrompt(
                from: query,
                transcript: transcript,
                textModel: config.selectedTextModel
            )
            DiagnosticsLogger.ai.info(
                "Apple Vision OCR prepared transcriptChars=\(transcript.fullText.count, privacy: .public) confidence=\(transcript.averageConfidence, privacy: .public) textModel=\(config.selectedTextModel.id, privacy: .public)"
            )
        } else {
            prompt = query
        }
        let request = try buildRequest(
            b64: b64,
            prompt: prompt,
            config: config,
            history: history,
            summary: summary
        )

        return AsyncThrowingStream { continuation in
            let session = session(for: config.provider)
            let worker = Task {
                do {
                    DiagnosticsLogger.network.info("Starting streamed request to \(request.url?.absoluteString ?? "<nil>", privacy: .public)")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        DiagnosticsLogger.network.error("Received non-HTTP response")
                        continuation.finish(throwing: AIError.badStatus(0))
                        return
                    }

                    DiagnosticsLogger.network.info("Received HTTP status \(http.statusCode, privacy: .public)")
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: AIError.badStatus(http.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        logIncomingStreamLine(line, provider: config.provider)
                        if let chunk = parseLine(line, provider: config.provider) {
                            continuation.yield(chunk)
                        }
                    }

                    DiagnosticsLogger.ai.info("Streaming finished successfully for provider=\(config.provider.rawValue, privacy: .public)")
                    continuation.finish()
                } catch is CancellationError {
                    DiagnosticsLogger.ai.notice("Streaming cancelled for provider=\(config.provider.rawValue, privacy: .public)")
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    let nsError = error as NSError
                    DiagnosticsLogger.ai.error("Streaming failed provider=\(config.provider.rawValue, privacy: .public) error=\(nsError.localizedDescription, privacy: .public)")
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

    private static func augmentedPrompt(
        from query: String,
        transcript: OCRTranscript,
        textModel: TextModelOption
    ) -> String {
        guard transcript.isUseful else {
            return """
            Preferred text-model profile: \(textModel.displayName) (\(textModel.runtime)).

            User request: \(query)
            """
        }

        let confidence = String(format: "%.2f", transcript.averageConfidence)
        return """
        Preferred text-model profile: \(textModel.displayName) (\(textModel.runtime)).
        OCR mode: Apple Vision on-device.
        OCR average confidence: \(confidence)

        OCR transcript:
        \(transcript.fullText)

        Use the OCR transcript as the first pass, but verify against the image if symbols, layout, or handwriting seem ambiguous.

        User request: \(query)
        """
    }

    private static func session(for provider: AIProvider) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        switch provider {
        case .onDevice:
            configuration.timeoutIntervalForRequest = 240
            configuration.timeoutIntervalForResource = 300
        case .llamaCpp:
            configuration.timeoutIntervalForRequest = 360
            configuration.timeoutIntervalForResource = 420
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
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func buildRequest(
        b64: String?,
        prompt: String,
        config: AIConfig,
        history: [ChatMessage] = [],
        summary: String = ""
    ) throws -> URLRequest {
        let urlString: String
        let headers: [String: String]
        let body: Any

        switch config.provider {
        case .onDevice:
            throw OnDeviceInferenceError.unsupportedInferencePath
        case .llamaCpp:
            throw AIError.missingServerURL(.llamaCpp)
        case .claude:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.anthropic.com/v1/messages"
            headers = [
                "x-api-key": config.apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            ]
            let context = ConversationContextManager.buildContext(
                prompt: prompt,
                history: history,
                summary: summary,
                hasAttachedImage: b64 != nil
            )
            let systemPrompt = mergedSystemPrompt(from: context)
            var messages: [[String: Any]] = []

            for message in context.recentMessages {
                messages.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }

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
            claudeContent.append(["type": "text", "text": context.userPrompt])
            messages.append(["role": "user", "content": claudeContent])
            body = [
                "model": config.model,
                "max_tokens": 2048,
                "stream": true,
                "system": systemPrompt,
                "messages": messages
            ] as [String: Any]

        case .openai:
            guard !config.apiKey.isEmpty else { throw AIError.missingConfig }
            urlString = "https://api.openai.com/v1/chat/completions"
            headers = [
                "Authorization": "Bearer \(config.apiKey)",
                "Content-Type": "application/json"
            ]
            let context = ConversationContextManager.buildContext(
                prompt: prompt,
                history: history,
                summary: summary,
                hasAttachedImage: b64 != nil
            )
            let systemPrompt = mergedSystemPrompt(from: context)
            var messages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]

            for message in context.recentMessages {
                messages.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }

            messages.append([
                "role": "user",
                "content": openAIUserContent(text: context.userPrompt, imageBase64: b64)
            ])
            body = [
                "model": config.model,
                "stream": true,
                "messages": messages
            ] as [String: Any]

        case .mlx:
            guard !config.mlxURL.isEmpty else { throw AIError.missingServerURL(.mlx) }
            urlString = "\(config.mlxURL)/v1/chat/completions"
            headers = ["Content-Type": "application/json"]
            let context = ConversationContextManager.buildContext(
                prompt: prompt,
                history: history,
                summary: summary,
                hasAttachedImage: b64 != nil
            )
            let systemPrompt = mergedSystemPrompt(from: context)

            var messages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]

            for msg in context.recentMessages {
                messages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }

            messages.append([
                "role": "user",
                "content": mlxUserContent(text: context.userPrompt, imageBase64: b64)
            ])

            body = [
                "model": config.model,
                "stream": true,
                "temperature": 0.1,
                "top_p": 0.95,
                "max_tokens": 512,
                "messages": messages
            ] as [String: Any]

        case .ollama:
            guard !config.ollamaURL.isEmpty else { throw AIError.missingServerURL(.ollama) }
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
        request.timeoutInterval = (config.provider == .ollama || config.provider == .llamaCpp) ? 360 : 180
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        DiagnosticsLogger.ai.debug("Built request payload:\n\(DiagnosticsLogger.jsonPreview(from: body), privacy: .public)")
        return request
    }

    private static func mergedSystemPrompt(from context: ManagedConversationContext) -> String {
        guard let summaryMessage = context.summaryMessage else {
            return context.systemPrompt
        }

        return """
        \(context.systemPrompt)

        \(summaryMessage.content)
        """
    }

    private static func openAIUserContent(text: String, imageBase64: String?) -> Any {
        guard let imageBase64 else {
            return text
        }

        return [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]
            ],
            [
                "type": "text",
                "text": text
            ]
        ]
    }

    private static func mlxUserContent(text: String, imageBase64: String?) -> Any {
        guard let imageBase64 else {
            return text
        }

        return [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]
            ],
            [
                "type": "text",
                "text": text
            ]
        ]
    }

    private static func parseLine(_ line: String, provider: AIProvider) -> StreamChunk? {
        switch provider {
        case .onDevice:
            return nil
        case .claude:
            guard let json = streamJSONObject(from: line),
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String
            else { return nil }
            return StreamChunk(text: text)

        case .openai, .mlx, .llamaCpp:
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

    private static func logIncomingStreamLine(_ line: String, provider: AIProvider) {
        let preview = DiagnosticsLogger.truncated(line, limit: 500)
        guard !preview.isEmpty else { return }
        DiagnosticsLogger.ai.debug("SSE line provider=\(provider.rawValue, privacy: .public): \(preview, privacy: .public)")
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

}
