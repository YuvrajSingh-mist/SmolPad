import Foundation
import UIKit

enum EmbeddedLlamaInferenceError: LocalizedError {
    case modelFilesMissing(String)
    case cancelled
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelFilesMissing(let detail):
            "The embedded llama.cpp model files are not available yet. \(detail)"
        case .cancelled:
            "The embedded llama.cpp request was cancelled."
        case .emptyResponse:
            "The embedded llama.cpp model returned an empty response."
        }
    }
}

private struct EmbeddedLlamaModelFiles {
    let modelIdentifier: String
    let textModelURL: URL
    let projectorURL: URL
}

enum EmbeddedLlamaVisionClient {
    static var isRuntimeAvailable: Bool { true }

    static func isModelInstalled(for config: AIConfig) -> Bool {
        resolveModelFiles(for: config.model) != nil
    }

    static func send(
        image: UIImage?,
        query: String,
        config: AIConfig,
        history: [ChatMessage],
        summary: String
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        guard let files = resolveModelFiles(for: config.model) else {
            DiagnosticsLogger.ai.notice(
                "Embedded llama.cpp model files missing for model=\(config.model, privacy: .public)"
            )
            await MainActor.run {
                OnDeviceRuntimeStatus.shared.markFailed(
                    modelIdentifier: config.model,
                    message: "Local VLM files missing"
                )
            }
            throw EmbeddedLlamaInferenceError.modelFilesMissing(
                "Install both the GGUF model and matching mmproj files for \(config.model)."
            )
        }

        let context = ConversationContextManager.buildContext(
            prompt: query,
            history: history,
            summary: summary,
            hasAttachedImage: image != nil
        )

        return AsyncThrowingStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markPreparing(modelIdentifier: files.modelIdentifier)
                    }

                    let session = await EmbeddedLlamaSessionPool.shared.session(for: files)
                    try await session.prepare()

                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markGenerating(modelIdentifier: files.modelIdentifier)
                    }

                    let request = EmbeddedLlamaGenerationRequest()
                    request.systemPrompt = mergedSystemPrompt(from: context)
                    request.history = context.recentMessages.map {
                        [
                            "role": $0.role.rawValue,
                            "content": $0.content
                        ]
                    }
                    request.userPrompt = context.userPrompt
                    request.image = image
                    request.maxTokens = 448

                    try await session.generate(request: request) { chunk in
                        continuation.yield(chunk)
                    }

                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: files.modelIdentifier)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    await EmbeddedLlamaSessionPool.shared.cancel(modelIdentifier: files.modelIdentifier)
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: files.modelIdentifier)
                    }
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    let message = error.localizedDescription
                    DiagnosticsLogger.ai.error(
                        "Embedded llama.cpp request failed model=\(files.modelIdentifier, privacy: .public) error=\(message, privacy: .public)"
                    )
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markFailed(
                            modelIdentifier: files.modelIdentifier,
                            message: message
                        )
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                Task {
                    await EmbeddedLlamaSessionPool.shared.cancel(modelIdentifier: files.modelIdentifier)
                }
            }
        }
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

    private static func resolveModelFiles(for modelIdentifier: String) -> EmbeddedLlamaModelFiles? {
        let candidates = modelRootCandidates()

        for root in candidates {
            let folderURL = root.appendingPathComponent(modelIdentifier, isDirectory: true)
            if let files = findModelFiles(in: folderURL, modelIdentifier: modelIdentifier) {
                return files
            }

            if let files = findModelFiles(in: root, modelIdentifier: modelIdentifier, strictPrefix: modelIdentifier) {
                return files
            }
        }

        return nil
    }

    private static func modelRootCandidates() -> [URL] {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            candidates.append(applicationSupport.appendingPathComponent("Models/llama.cpp", isDirectory: true))
        }

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(documents.appendingPathComponent("Models/llama.cpp", isDirectory: true))
        }

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models/llama.cpp", isDirectory: true) {
            candidates.append(bundled)
        }

        return candidates
    }

    private static func findModelFiles(
        in directory: URL,
        modelIdentifier: String,
        strictPrefix: String? = nil
    ) -> EmbeddedLlamaModelFiles? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var projectorURL: URL?
        var textModelURL: URL?

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "gguf" else { continue }
            let name = url.lastPathComponent.lowercased()

            if let strictPrefix, !name.contains(strictPrefix.lowercased()) {
                continue
            }

            if name.contains("mmproj") || name.contains("projector") {
                projectorURL = projectorURL ?? url
            } else {
                textModelURL = textModelURL ?? url
            }
        }

        guard let textModelURL, let projectorURL else { return nil }
        return EmbeddedLlamaModelFiles(
            modelIdentifier: modelIdentifier,
            textModelURL: textModelURL,
            projectorURL: projectorURL
        )
    }
}

private actor EmbeddedLlamaSessionPool {
    static let shared = EmbeddedLlamaSessionPool()

    private var sessions: [String: EmbeddedLlamaSession] = [:]

    func session(for files: EmbeddedLlamaModelFiles) -> EmbeddedLlamaSession {
        let key = "\(files.textModelURL.path)|\(files.projectorURL.path)"
        if let existing = sessions[key] {
            return existing
        }

        let created = EmbeddedLlamaSession(files: files)
        sessions[key] = created
        return created
    }

    func cancel(modelIdentifier: String) {
        for (_, session) in sessions {
            Task {
                await session.cancel()
            }
        }
    }
}

private actor EmbeddedLlamaSession {
    private let files: EmbeddedLlamaModelFiles
    private let bridge: EmbeddedLlamaBridge

    init(files: EmbeddedLlamaModelFiles) {
        self.files = files
        self.bridge = EmbeddedLlamaBridge(
            modelPath: files.textModelURL.path,
            mmprojPath: files.projectorURL.path,
            modelIdentifier: files.modelIdentifier
        )
    }

    func prepare() throws {
        try bridge.prepare()
    }

    func generate(
        request: EmbeddedLlamaGenerationRequest,
        onChunk: @escaping @Sendable (StreamChunk) -> Void
    ) throws {
        do {
            try bridge.generate(request, onChunk: { text, isThinking in
                onChunk(StreamChunk(text: text, isThinking: isThinking))
            })
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.smol.smolpad.embedded-llama", nsError.code == 1099 {
                throw AIError.cancelled
            }
            throw error
        }
    }

    func cancel() {
        bridge.cancel()
    }
}
