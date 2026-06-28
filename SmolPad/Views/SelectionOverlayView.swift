import SwiftUI

struct SelectionOverlayView: View {
    var state: CanvasState

    @State private var lassoPoints: [CGPoint] = []
    @State private var rectStart: CGPoint?
    @State private var rectEnd: CGPoint?

    var body: some View {
        ZStack {
            Color.black.opacity(0.04)

            Canvas { context, _ in
                switch state.activeTool {
                case .lassoSelect:
                    drawLasso(context: context)
                case .rectSelect:
                    drawRect(context: context)
                default:
                    break
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(gesture)
        .ignoresSafeArea()
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: state.activeTool == .rectSelect ? 4 : 0, coordinateSpace: .local)
            .onChanged { value in
                switch state.activeTool {
                case .lassoSelect:
                    if lassoPoints.isEmpty {
                        lassoPoints.append(value.startLocation)
                    }
                    lassoPoints.append(value.location)
                case .rectSelect:
                    if rectStart == nil {
                        rectStart = value.startLocation
                    }
                    rectEnd = value.location
                default:
                    break
                }
            }
            .onEnded { _ in
                switch state.activeTool {
                case .lassoSelect:
                    state.captureLasso(points: lassoPoints)
                    lassoPoints = []
                case .rectSelect:
                    if let rectStart, let rectEnd {
                        let rect = CGRect(
                            x: min(rectStart.x, rectEnd.x),
                            y: min(rectStart.y, rectEnd.y),
                            width: max(0, abs(rectEnd.x - rectStart.x)),
                            height: max(0, abs(rectEnd.y - rectStart.y))
                        )
                        state.captureRect(rect)
                    }
                    rectStart = nil
                    rectEnd = nil
                default:
                    break
                }
            }
    }

    private func drawLasso(context: GraphicsContext) {
        guard lassoPoints.count > 1 else { return }

        var path = Path()
        path.move(to: lassoPoints[0])
        for point in lassoPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()

        let gold = Color(red: 0.961, green: 0.651, blue: 0.137)
        context.fill(path, with: .color(gold.opacity(0.12)))
        context.stroke(
            path,
            with: .color(gold),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawRect(context: GraphicsContext) {
        guard let rectStart, let rectEnd else { return }

        let rect = CGRect(
            x: min(rectStart.x, rectEnd.x),
            y: min(rectStart.y, rectEnd.y),
            width: abs(rectEnd.x - rectStart.x),
            height: abs(rectEnd.y - rectStart.y)
        )
        let path = Path(rect)

        context.fill(path, with: .color(Color.blue.opacity(0.08)))
        context.stroke(
            path,
            with: .color(.blue),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
    }
}
