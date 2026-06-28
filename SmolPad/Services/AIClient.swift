import Foundation
import UIKit

enum AIError: LocalizedError {
    case missingConfig
    case badStatus(Int)
    case invalidURL
    case localNetworkDenied
    case timedOut(AIProvider)

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
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct AIClient {
    static func send(
        image: UIImage?,
        query: String,
        config: AIConfig,
        history: [ChatMessage] = []
    ) async throws -> AsyncThrowingStream<String, Error> {
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
            Task {
                do {
                    let session = session(for: config.provider)
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
        }
    }

    private static func session(for provider: AIProvider) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
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
            let systemText: String
            if b64 != nil {
                systemText = "You are a helpful AI assistant. Read the handwritten note carefully. If it contains math, first transcribe the equation exactly as written, then solve it step by step with clear reasoning, and end with a boxed final answer. If it is not math, answer the user's question directly and thoroughly."
            } else {
                systemText = "You are a helpful AI assistant. Think step by step, explain your reasoning clearly, and provide accurate, thorough answers to the user's questions."
            }

            var messages: [[String: Any]] = [
                ["role": "system", "content": [["type": "text", "text": systemText]]]
            ]

            // Add conversation history (text-only)
            for msg in history {
                messages.append(["role": msg.role, "content": [["type": "text", "text": msg.content]]])
            }

            // Current user message
            var userContent: [[String: Any]] = []
            if let b64 {
                userContent.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]])
            }
            userContent.append(["type": "text", "text": prompt])
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

    private static func parseLine(_ line: String, provider: AIProvider) -> String? {
        switch provider {
        case .claude:
            guard line.hasPrefix("data: "),
                  let data = line.dropFirst(6).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String
            else { return nil }
            return text

        case .openai, .mlx:
            guard line.hasPrefix("data: "),
                  !line.hasPrefix("data: [DONE]"),
                  let data = line.dropFirst(6).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String
            else { return nil }
            return text

        case .ollama:
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { return nil }
            return text
        }
    }

    private static func isLocalNetworkDenied(_ error: NSError) -> Bool {
        guard error.code == NSURLErrorNotConnectedToInternet else { return false }
        return String(describing: error.userInfo).localizedCaseInsensitiveContains("local network prohibited")
    }
}
