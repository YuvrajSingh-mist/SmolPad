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

        let canvas = state.canvasView
        canvas.removeFromSuperview()
        canvas.frame = CGRect(x: 0, y: 0, width: 2048, height: 4096)
        canvas.backgroundColor = .clear
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
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
        scrollView.isScrollEnabled = state.activeTool == .hand
        canvas.isUserInteractionEnabled = !state.activeTool.isSelection

        switch state.activeTool {
        case .pen:
            canvas.drawingPolicy = .anyInput
            canvas.tool = PKInkingTool(
                .pen,
                color: state.selectedPenColor,
                width: state.penWidth
            )
        case .eraser:
            canvas.drawingPolicy = .anyInput
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

    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        let state: CanvasState

        init(state: CanvasState) {
            self.state = state
        }

        @objc func switchToHandMode() {
            state.activeTool = .hand
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if state.activeTool == .hand {
                state.activeTool = .pen
            }
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
