import PencilKit
import UIKit

protocol InputAwareCanvasViewDelegate: AnyObject {
    func canvasViewDidBeginFingerInteraction(_ canvasView: InputAwareCanvasView)
    func canvasViewDidBeginPencilInteraction(_ canvasView: InputAwareCanvasView)
}

final class InputAwareCanvasView: PKCanvasView {
    weak var inputDelegate: InputAwareCanvasViewDelegate?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        notifyInputType(for: touches)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        notifyInputType(for: touches)
        super.touchesMoved(touches, with: event)
    }

    private func notifyInputType(for touches: Set<UITouch>) {
        guard let touch = touches.first else { return }

        switch touch.type {
        case .pencil:
            inputDelegate?.canvasViewDidBeginPencilInteraction(self)
        case .direct, .indirectPointer:
            inputDelegate?.canvasViewDidBeginFingerInteraction(self)
        default:
            break
        }
    }
}
