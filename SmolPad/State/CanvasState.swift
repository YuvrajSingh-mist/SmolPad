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

    var activeTool: ActiveTool = .pen
    var activeAccessory: ToolAccessory?
    @ObservationIgnored let canvasView = PKCanvasView()
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
    private var captureFingerprint: Int?

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
        showChat = false
        capturedImage = nil
        captureFingerprint = nil
    }

    func clearChatSession() {
        chatDraft = ""
        conversation = []
    }

    func appendUserMessage(_ content: String) {
        conversation.append(ChatMessage(role: .user, content: content))
    }

    func appendAssistantMessage(_ content: String, thinking: String?) {
        conversation.append(ChatMessage(role: .assistant, content: content, thinking: thinking))
    }

    func appendConversationTurn(user: String, assistant: String, thinking: String?) {
        appendUserMessage(user)
        appendAssistantMessage(assistant, thinking: thinking)
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
            clearChatSession()
        }

        capturedImage = image
        captureFingerprint = newFingerprint
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
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
