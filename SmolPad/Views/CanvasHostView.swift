import PencilKit
import SwiftUI

struct CanvasHostView: UIViewRepresentable {
    var state: CanvasState

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 3.0
        scrollView.zoomScale = 1.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true
        scrollView.overrideUserInterfaceStyle = .light

        let canvas = state.canvasView
        canvas.removeFromSuperview()
        canvas.frame = CGRect(x: 0, y: 0, width: 2048, height: 4096)
        canvas.backgroundColor = .clear
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = context.coordinator
        canvas.inputDelegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: state.selectedPenColor, width: state.penWidth)
        canvas.isRulerActive = false

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.switchToHandMode))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(doubleTap)

        scrollView.contentSize = canvas.frame.size
        scrollView.addSubview(canvas)
        context.coordinator.state.scrollOffset = scrollView.contentOffset
        context.coordinator.state.zoomScale = scrollView.zoomScale

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let canvas = state.canvasView
        scrollView.overrideUserInterfaceStyle = .light
        canvas.overrideUserInterfaceStyle = .light
        scrollView.isScrollEnabled = !state.activeTool.isSelection
        canvas.isUserInteractionEnabled = !state.activeTool.isSelection

        switch state.activeTool {
        case .pen:
            canvas.drawingPolicy = .pencilOnly
            canvas.tool = PKInkingTool(
                .pen,
                color: state.selectedPenColor,
                width: state.penWidth
            )
        case .eraser:
            canvas.drawingPolicy = .pencilOnly
            let eraser = PKEraserTool(.bitmap, width: state.eraserWidth)
            canvas.tool = eraser
        case .hand:
            canvas.drawingPolicy = .pencilOnly
            canvas.tool = PKInkingTool(
                .pen,
                color: state.selectedPenColor,
                width: state.penWidth
            )
        case .lassoSelect, .rectSelect:
            break
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate, InputAwareCanvasViewDelegate {
        let state: CanvasState

        init(state: CanvasState) {
            self.state = state
        }

        @objc func switchToHandMode() {
            state.closeAccessory()
            state.activeTool = .hand
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            state.closeAccessory()
            if state.activeTool == .hand {
                state.beginPencilCanvasEditing()
            }
        }

        func canvasViewDidBeginFingerInteraction(_ canvasView: InputAwareCanvasView) {
            state.beginFingerCanvasNavigation()
        }

        func canvasViewDidBeginPencilInteraction(_ canvasView: InputAwareCanvasView) {
            state.beginPencilCanvasEditing()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            state.scrollOffset = scrollView.contentOffset
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            state.zoomScale = scrollView.zoomScale
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            state.canvasView
        }
    }
}
