import SwiftUI
import PencilKit
import Observation

enum ActiveTool: Equatable {
    case pen
    case eraser
    case lassoSelect
    case rectSelect
    case hand

    var isSelection: Bool { self == .lassoSelect || self == .rectSelect }
    var isEditing: Bool { self == .pen || self == .eraser }
}

struct PenSwatch: Identifiable {
    let id: Int
    let color: Color
    let uiColor: UIColor
}

@Observable
final class CanvasState {
    enum ToolAccessory: Equatable {
        case pen
        case eraser
    }

    var activeTool: ActiveTool = .pen {
        didSet {
            if activeTool == .pen || activeTool == .eraser {
                preferredEditingTool = activeTool
            }
        }
    }
    var activeAccessory: ToolAccessory?
    @ObservationIgnored let canvasView = InputAwareCanvasView()
    var scrollOffset: CGPoint = .zero
    var zoomScale: CGFloat = 1.0
    var capturedImage: UIImage?
    var showChat = false
    var selectionError: String?
    var selectedPenColorIndex = 0
    var penWidth: CGFloat = 3.5
    var eraserWidth: CGFloat = 22.0
    var chatDraft = ""
    var conversation: [ChatMessage] = []
    var conversationSummary = ""
    var streamResponse = ""
    var streamThinking = ""
    var streamError: String?
    var showsLocalNetworkSettings = false
    var pendingUserQuery: String?
    var isStreaming = false
    var isThinkingExpanded = true
    @ObservationIgnored private var streamingTask: Task<Void, Never>?
    private var captureFingerprint: Int?
    private var preferredEditingTool: ActiveTool = .pen

    static let penSwatches: [PenSwatch] = [
        PenSwatch(
            id: 0,
            color: Color(red: 0.05, green: 0.05, blue: 0.07),
            uiColor: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        ),
        PenSwatch(
            id: 1,
            color: Color(red: 0.0, green: 0.28, blue: 0.92),
            uiColor: UIColor(red: 0.0, green: 0.28, blue: 0.92, alpha: 1.0)
        ),
        PenSwatch(
            id: 2,
            color: Color(red: 0.89, green: 0.08, blue: 0.10),
            uiColor: UIColor(red: 0.89, green: 0.08, blue: 0.10, alpha: 1.0)
        ),
        PenSwatch(
            id: 3,
            color: Color(red: 0.05, green: 0.60, blue: 0.18),
            uiColor: UIColor(red: 0.05, green: 0.60, blue: 0.18, alpha: 1.0)
        ),
        PenSwatch(
            id: 4,
            color: Color(red: 0.55, green: 0.08, blue: 0.92),
            uiColor: UIColor(red: 0.55, green: 0.08, blue: 0.92, alpha: 1.0)
        )
    ]

    var selectedPenColor: UIColor {
        Self.penSwatches[safe: selectedPenColorIndex]?.uiColor ?? Self.penSwatches[0].uiColor
    }

    func undo() {
        canvasView.undoManager?.undo()
    }

    func redo() {
        canvasView.undoManager?.redo()
    }

    func toCanvasRect(_ screenRect: CGRect) -> CGRect {
        CGRect(
            x: (screenRect.minX + scrollOffset.x) / zoomScale,
            y: (screenRect.minY + scrollOffset.y) / zoomScale,
            width: screenRect.width / zoomScale,
            height: screenRect.height / zoomScale
        )
    }

    func captureRect(_ screenRect: CGRect) {
        guard screenRect.width > 20, screenRect.height > 20 else {
            selectionError = "Selection too small. Draw a larger area around your writing."
            activeTool = .pen
            return
        }

        let canvasRect = toCanvasRect(screenRect).intersection(canvasView.bounds)
        guard !canvasRect.isNull, canvasRect.width > 1, canvasRect.height > 1 else {
            selectionError = "The selected area contains no writing. Try selecting a region with ink."
            activeTool = .pen
            return
        }

        let drawnImage = canvasView.drawing.image(from: canvasRect, scale: 2.0)
        guard drawnImage.size.width > 0, drawnImage.size.height > 0 else {
            selectionError = "Couldn't capture the selected region. Try again."
            activeTool = .pen
            return
        }

        beginChatCaptureSession(with: drawnImage)
        selectionError = nil
        showChat = true
        activeTool = .pen
    }

    func captureLasso(points: [CGPoint]) {
        guard points.count > 3 else {
            selectionError = "Lasso too short. Draw a closed loop around your writing."
            activeTool = .pen
            return
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let maxX = xs.max() ?? 0
        let maxY = ys.max() ?? 0
        let rect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )

        guard rect.width > 20, rect.height > 20 else {
            selectionError = "Lasso selection too small. Encircle more of your writing."
            activeTool = .pen
            return
        }

        captureRect(rect)
    }

    func dismissChat() {
        DiagnosticsLogger.app.info("Chat panel dismissed")
        showChat = false
    }

    func clearChatSession() {
        DiagnosticsLogger.app.notice("Clearing chat session conversationCount=\(self.conversation.count, privacy: .public)")
        streamingTask?.cancel()
        streamingTask = nil
        chatDraft = ""
        conversation = []
        conversationSummary = ""
        pendingUserQuery = nil
        resetStreamingPresentation()
    }

    func appendUserMessage(_ content: String) {
        conversation.append(ChatMessage(role: .user, content: content))
    }

    func appendAssistantMessage(_ content: String, thinking: String?) {
        conversation.append(ChatMessage(role: .assistant, content: content, thinking: thinking))
    }

    func appendConversationTurn(user: String, assistant: String, thinking: String?) {
        DiagnosticsLogger.context.info(
            "Appending completed turn userChars=\(user.count, privacy: .public) assistantChars=\(assistant.count, privacy: .public) thinkingChars=\((thinking ?? "").count, privacy: .public)"
        )
        appendUserMessage(user)
        appendAssistantMessage(assistant, thinking: thinking)

        let compacted = ConversationContextManager.compact(
            history: conversation,
            existingSummary: conversationSummary
        )
        conversation = compacted.recentMessages
        conversationSummary = compacted.summary
    }

    func sendQuery(config: AIConfig) {
        guard !isStreaming else { return }

        let userQuery = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuery.isEmpty else { return }

        DiagnosticsLogger.app.info(
            "Sending query provider=\(config.provider.rawValue, privacy: .public) query=\(DiagnosticsLogger.truncated(userQuery), privacy: .public) conversationCount=\(self.conversation.count, privacy: .public) hasImage=\(self.capturedImage != nil, privacy: .public)"
        )

        resetStreamingPresentation()
        isStreaming = true
        pendingUserQuery = userQuery
        chatDraft = ""

        let task = Task {
            let suppressThinking = config.provider == .llamaCpp
            do {
                let stream = try await AIClient.send(
                    image: capturedImage,
                    query: userQuery,
                    config: config,
                    history: conversation,
                    summary: conversationSummary
                )

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        present(chunk: chunk, suppressThinking: suppressThinking)
                    }
                }

                await MainActor.run {
                    if Task.isCancelled {
                        finishCancellation(suppressThinking: suppressThinking)
                    } else {
                        commitCompletedTurn(for: userQuery, suppressThinking: suppressThinking)
                    }
                    DiagnosticsLogger.app.info("Completed query successfully")
                    isStreaming = false
                    streamingTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if let aiError = error as? AIError, case .cancelled = aiError {
                        finishCancellation(suppressThinking: suppressThinking)
                    } else {
                        present(error: error)
                    }
                    DiagnosticsLogger.app.error("Query failed error=\(error.localizedDescription, privacy: .public)")
                    isStreaming = false
                    streamingTask = nil
                }
            }
        }

        streamingTask = task
    }

    func cancelStreaming() {
        DiagnosticsLogger.app.notice("Cancelling active stream")
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        finishCancellation()
    }

    func beginFingerCanvasNavigation() {
        guard !activeTool.isSelection else { return }
        closeAccessory()
        activeTool = .hand
    }

    func beginPencilCanvasEditing() {
        guard !activeTool.isSelection else { return }
        closeAccessory()
        if activeTool == .hand {
            activeTool = preferredEditingTool
        }
    }

    func dismissError() {
        selectionError = nil
    }

    func closeAccessory() {
        activeAccessory = nil
    }

    private func beginChatCaptureSession(with image: UIImage) {
        let newFingerprint = fingerprint(for: image)
        if let currentFingerprint = captureFingerprint, currentFingerprint != newFingerprint {
            DiagnosticsLogger.app.notice("Selection changed; resetting chat session")
            clearChatSession()
        }

        capturedImage = image
        captureFingerprint = newFingerprint
        DiagnosticsLogger.app.info("Started chat capture session imageSize=\(Int(image.size.width), privacy: .public)x\(Int(image.size.height), privacy: .public)")
    }

    private func fingerprint(for image: UIImage) -> Int {
        let size = image.size
        var hasher = Hasher()
        hasher.combine(Int(size.width.rounded()))
        hasher.combine(Int(size.height.rounded()))

        if let data = image.jpegData(compressionQuality: 0.3) {
            hasher.combine(data.count)
            for byte in data.prefix(4096) {
                hasher.combine(byte)
            }
        }

        return hasher.finalize()
    }

    private func present(chunk: StreamChunk, suppressThinking: Bool) {
        if chunk.isThinking && !suppressThinking {
            streamThinking += chunk.text
        } else {
            streamResponse += chunk.text
        }
        DiagnosticsLogger.ai.debug(
            "Presented chunk kind=\(chunk.isThinking ? "thinking" : "response", privacy: .public) chunkChars=\(chunk.text.count, privacy: .public) totalResponseChars=\(self.streamResponse.count, privacy: .public) totalThinkingChars=\(self.streamThinking.count, privacy: .public)"
        )
    }

    private func commitCompletedTurn(for userQuery: String, suppressThinking: Bool) {
        appendConversationTurn(
            user: userQuery,
            assistant: streamResponse,
            thinking: suppressThinking ? nil : streamThinking
        )
        pendingUserQuery = nil
        resetStreamingPresentation()
    }

    private func finishCancellation(suppressThinking: Bool) {
        if let pendingUserQuery = pendingUserQuery {
            let partialResponse = streamResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            let partialThinking = streamThinking.trimmingCharacters(in: .whitespacesAndNewlines)

            appendUserMessage(pendingUserQuery)
            self.pendingUserQuery = nil

            if !partialResponse.isEmpty || !partialThinking.isEmpty {
                appendAssistantMessage(
                    partialResponse,
                    thinking: suppressThinking || partialThinking.isEmpty ? nil : partialThinking
                )
            }
        }

        let compacted = ConversationContextManager.compact(
            history: conversation,
            existingSummary: conversationSummary
        )
        conversation = compacted.recentMessages
        conversationSummary = compacted.summary

        DiagnosticsLogger.app.notice(
            "Stream cancelled; preserved pending turn userPresent=\(self.pendingUserQuery == nil, privacy: .public) partialResponseChars=\(self.streamResponse.count, privacy: .public) partialThinkingChars=\(self.streamThinking.count, privacy: .public)"
        )
        resetStreamingPresentation()
    }

    private func present(error: Error) {
        streamError = error.localizedDescription
        if let pendingUserQuery {
            appendUserMessage(pendingUserQuery)
            self.pendingUserQuery = nil
        }
        showsLocalNetworkSettings = {
            guard let aiError = error as? AIError else { return false }
            if case .localNetworkDenied = aiError {
                return true
            }
            return false
        }()
        DiagnosticsLogger.app.error("Presented stream error: \(error.localizedDescription, privacy: .public)")
    }

    private func resetStreamingPresentation() {
        streamResponse = ""
        streamThinking = ""
        streamError = nil
        showsLocalNetworkSettings = false
        isThinkingExpanded = true
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
