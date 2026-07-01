import Foundation
import UIKit
import Combine

#if canImport(Uzu)
import Uzu
#endif

@MainActor
final class OnDeviceRuntimeStatus: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case downloading
        case ready
        case generating
        case failed(String)
    }

    static let shared = OnDeviceRuntimeStatus()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelIdentifier = ""
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var bytesDownloaded: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    private var dismissalTask: Task<Void, Never>?

    var isVisible: Bool {
        switch phase {
        case .idle:
            return false
        case .preparing, .downloading, .ready, .generating, .failed:
            return true
        }
    }

    var title: String {
        switch phase {
        case .idle:
            return ""
        case .preparing:
            return "Preparing model"
        case .downloading:
            return "Downloading model"
        case .ready:
            return "Model ready"
        case .generating:
            return "Running on device"
        case .failed:
            return "On-device error"
        }
    }

    var detail: String {
        switch phase {
        case .idle:
            return ""
        case .preparing, .ready, .generating:
            return shortModelName(from: modelIdentifier)
        case .downloading:
            let percent = Int((progressFraction * 100).rounded())
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let downloaded = formatter.string(fromByteCount: bytesDownloaded)
            let total = bytesTotal > 0 ? formatter.string(fromByteCount: bytesTotal) : "Unknown"
            return "\(shortModelName(from: modelIdentifier)) • \(percent)% • \(downloaded) / \(total)"
        case .failed(let message):
            return message
        }
    }

    func reset() {
        dismissalTask?.cancel()
        dismissalTask = nil
        phase = .idle
        modelIdentifier = ""
        progressFraction = 0
        bytesDownloaded = 0
        bytesTotal = 0
    }

    func markPreparing(modelIdentifier: String) {
        dismissalTask?.cancel()
        dismissalTask = nil
        self.modelIdentifier = modelIdentifier
        phase = .preparing
        progressFraction = 0
        bytesDownloaded = 0
        bytesTotal = 0
    }

    func markDownloading(modelIdentifier: String, progressFraction: Double, bytesDownloaded: Int64, bytesTotal: Int64) {
        dismissalTask?.cancel()
        dismissalTask = nil
        self.modelIdentifier = modelIdentifier
        phase = .downloading
        self.progressFraction = progressFraction
        self.bytesDownloaded = bytesDownloaded
        self.bytesTotal = bytesTotal
    }

    func markReady(modelIdentifier: String) {
        dismissalTask?.cancel()
        self.modelIdentifier = modelIdentifier
        phase = .ready
        progressFraction = 1
        scheduleDismiss(after: 1.8)
    }

    func markGenerating(modelIdentifier: String) {
        dismissalTask?.cancel()
        dismissalTask = nil
        self.modelIdentifier = modelIdentifier
        phase = .generating
    }

    func markFailed(modelIdentifier: String, message: String) {
        dismissalTask?.cancel()
        self.modelIdentifier = modelIdentifier
        phase = .failed(message)
        scheduleDismiss(after: 4)
    }

    private func shortModelName(from identifier: String) -> String {
        identifier.split(separator: "/").last.map(String.init) ?? identifier
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }
}

enum OnDeviceInferenceError: LocalizedError {
    case runtimeUnavailable
    case unsupportedInferencePath
    case modelUnavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "The Mirai on-device runtime is not linked in this build yet."
        case .unsupportedInferencePath:
            "The on-device runtime currently supports Vision OCR + Text mode only."
        case .modelUnavailable(let model):
            "The on-device model \(model) is not available through the Mirai runtime."
        case .emptyResponse:
            "The on-device model returned an empty response."
        }
    }
}

enum OnDeviceTextClient {
    static var isRuntimeAvailable: Bool {
        #if canImport(Uzu)
        true
        #else
        false
        #endif
    }

    static func send(
        image: UIImage?,
        query: String,
        config: AIConfig,
        history: [ChatMessage],
        summary: String
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        guard config.inferencePath == .appleVisionOCRPlusText else {
            throw OnDeviceInferenceError.unsupportedInferencePath
        }

        #if canImport(Uzu)
        DiagnosticsLogger.ai.info("On-device request starting model=\(config.selectedTextModel.id, privacy: .public)")
        await MainActor.run {
            OnDeviceRuntimeStatus.shared.markPreparing(modelIdentifier: config.selectedTextModel.id)
        }
        let transcript: OCRTranscript
        if let image {
            transcript = try await AppleVisionOCRService.recognizeText(in: image)
        } else {
            transcript = OCRTranscript(fullText: "", averageConfidence: 0, lines: [])
        }

        let context = ConversationContextManager.buildContext(
            prompt: query,
            history: history,
            summary: summary,
            hasAttachedImage: image != nil
        )
        let prompt = augmentedPrompt(
            query: context.userPrompt,
            transcript: transcript,
            textModel: config.selectedTextModel
        )

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let engine = try await OnDeviceEngine.shared.engine()
                    guard let model = try await engine.model(identifier: config.selectedTextModel.id) else {
                        throw OnDeviceInferenceError.modelUnavailable(config.selectedTextModel.id)
                    }

                    try await OnDeviceEngine.shared.ensureModelDownloaded(model: model, engine: engine)
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markGenerating(modelIdentifier: config.selectedTextModel.id)
                    }
                    DiagnosticsLogger.ai.info("On-device model ready, starting generation model=\(config.selectedTextModel.id, privacy: .public)")
                    let session = try await engine.chat(model: model, config: .create())

                    let messages = buildMessages(systemPrompt: context.systemPrompt, prompt: prompt)
                    let stream = await session.replyWithStream(input: messages, config: .create())

                    var lastReasoning = ""
                    var lastText = ""

                    for try await update in stream.iterator() {
                        if Task.isCancelled {
                            break
                        }

                        switch update {
                        case .replies(let replies):
                            guard let message = replies.last?.message else {
                                continue
                            }

                            let reasoning = message.reasoning() ?? ""
                            if let delta = suffixDelta(from: lastReasoning, to: reasoning), !delta.isEmpty {
                                continuation.yield(StreamChunk(text: delta, isThinking: true))
                                lastReasoning = reasoning
                            } else {
                                lastReasoning = reasoning
                            }

                            let text = message.text() ?? ""
                            if let delta = suffixDelta(from: lastText, to: text), !delta.isEmpty {
                                continuation.yield(StreamChunk(text: delta, isThinking: false))
                                lastText = text
                            } else {
                                lastText = text
                            }

                        case .error(let error):
                            throw error
                        }
                    }

                    if lastText.isEmpty && lastReasoning.isEmpty {
                        throw OnDeviceInferenceError.emptyResponse
                    }

                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: config.selectedTextModel.id)
                    }
                    DiagnosticsLogger.ai.info("On-device generation finished model=\(config.selectedTextModel.id, privacy: .public)")
                    continuation.finish()
                } catch is CancellationError {
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: config.selectedTextModel.id)
                    }
                    DiagnosticsLogger.ai.notice("On-device request cancelled model=\(config.selectedTextModel.id, privacy: .public)")
                    continuation.finish(throwing: AIError.cancelled)
                } catch {
                    await MainActor.run {
                        OnDeviceRuntimeStatus.shared.markFailed(
                            modelIdentifier: config.selectedTextModel.id,
                            message: error.localizedDescription
                        )
                    }
                    DiagnosticsLogger.ai.error("On-device request failed model=\(config.selectedTextModel.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
        #else
        throw OnDeviceInferenceError.runtimeUnavailable
        #endif
    }

    #if canImport(Uzu)
    private static func buildMessages(systemPrompt: String, prompt: String) -> [Uzu.ChatMessage] {
        [
            Uzu.ChatMessage.system().withText(text: systemPrompt),
            Uzu.ChatMessage.user().withText(text: prompt)
        ]
    }

    private static func augmentedPrompt(
        query: String,
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

        Use the OCR transcript as the primary source. If the transcript looks uncertain, explain the uncertainty clearly instead of hallucinating.

        User request: \(query)
        """
    }

    private static func suffixDelta(from previous: String, to next: String) -> String? {
        guard !next.isEmpty else { return nil }
        guard !previous.isEmpty else { return next }
        guard next.hasPrefix(previous) else { return next }
        return String(next.dropFirst(previous.count))
    }
    #endif
}

#if canImport(Uzu)
private actor OnDeviceEngine {
    static let shared = OnDeviceEngine()

    private var cachedEngine: Engine?
    private var downloadedModelIDs = Set<String>()

    func engine() async throws -> Engine {
        if let cachedEngine {
            return cachedEngine
        }

        let config = EngineConfig.create()
        let engine = try await Engine.create(config: config)
        cachedEngine = engine
        return engine
    }

    func ensureModelDownloaded(model: Model, engine: Engine) async throws {
        let identifier = model.identifier
        guard !downloadedModelIDs.contains(identifier) else {
            DiagnosticsLogger.ai.info("On-device model already cached model=\(identifier, privacy: .public)")
            await MainActor.run {
                OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: identifier)
            }
            return
        }

        DiagnosticsLogger.ai.info("On-device model download started model=\(identifier, privacy: .public)")
        for try await update in try await engine.download(model: model).iterator() {
            await MainActor.run {
                OnDeviceRuntimeStatus.shared.markDownloading(
                    modelIdentifier: identifier,
                    progressFraction: Double(update.progress()),
                    bytesDownloaded: update.bytesDownloaded,
                    bytesTotal: update.bytesTotal
                )
            }
        }
        downloadedModelIDs.insert(identifier)
        DiagnosticsLogger.ai.info("On-device model download completed model=\(identifier, privacy: .public)")
        await MainActor.run {
            OnDeviceRuntimeStatus.shared.markReady(modelIdentifier: identifier)
        }
    }
}
#endif
