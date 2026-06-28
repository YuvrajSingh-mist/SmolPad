import SwiftUI

struct ToolbarView: View {
    @Bindable var state: CanvasState
    @Binding var showSettings: Bool

    private let tools: [(ActiveTool, String)] = [
        (.pen, "pencil.tip"),
        (.eraser, "eraser"),
        (.lassoSelect, "lasso"),
        (.rectSelect, "rectangle.dashed"),
        (.hand, "hand.raised")
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if state.activeTool == .pen {
                penOptions
            } else if state.activeTool == .eraser {
                eraserOptions
            }

            VStack(spacing: 4) {
                ForEach(tools, id: \.1) { tool, icon in
                    toolButton(tool: tool, icon: icon)
                }

                Divider()
                    .frame(width: 28)
                    .padding(.vertical, 2)

                Button {
                    state.undo()
                } label: {
                    toolbarIcon("arrow.uturn.backward")
                }
                .buttonStyle(.plain)

                Button {
                    state.redo()
                } label: {
                    toolbarIcon("arrow.uturn.forward")
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(width: 28)
                    .padding(.vertical, 2)

                Button {
                    showSettings = true
                } label: {
                    toolbarIcon("gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(width: 52)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(Color(white: 0.0, opacity: 0.08), lineWidth: 0.5)
                    }
            }
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        }
    }

    private var penOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CanvasState.penSwatches) { swatch in
                    Button {
                        state.selectedPenColorIndex = swatch.id
                        state.activeTool = .pen
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        state.selectedPenColorIndex == swatch.id
                                            ? Color(red: 0.961, green: 0.651, blue: 0.137)
                                            : Color.white.opacity(0.45),
                                        lineWidth: state.selectedPenColorIndex == swatch.id ? 3 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "pencil.tip")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.35))

                Slider(value: $state.penWidth, in: 1.5...12, step: 0.5)
                    .tint(Color(red: 0.961, green: 0.651, blue: 0.137))

                Circle()
                    .fill(CanvasState.penSwatches[safe: state.selectedPenColorIndex]?.color ?? CanvasState.penSwatches[0].color)
                    .frame(width: max(4, min(18, state.penWidth * 1.5)), height: max(4, min(18, state.penWidth * 1.5)))
                    .frame(width: 22, height: 22)
            }
        }
        .padding(14)
        .frame(width: 226)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(white: 0.0, opacity: 0.08), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var eraserOptions: some View {
        HStack(spacing: 10) {
            Image(systemName: "eraser")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.35))

            Slider(value: $state.eraserWidth, in: 6...44, step: 1)
                .tint(Color(red: 0.961, green: 0.651, blue: 0.137))

            Circle()
                .strokeBorder(Color(white: 0.3), lineWidth: 1.2)
                .background(Circle().fill(Color.white.opacity(0.5)))
                .frame(width: max(8, min(28, state.eraserWidth * 0.65)), height: max(8, min(28, state.eraserWidth * 0.65)))
                .frame(width: 30, height: 30)
        }
        .padding(14)
        .frame(width: 226)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(white: 0.0, opacity: 0.08), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func toolButton(tool: ActiveTool, icon: String) -> some View {
        let isActive = state.activeTool == tool

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.activeTool = tool
            }
        } label: {
            ZStack {
                if isActive {
                    Circle()
                        .fill(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.18))
                        .frame(width: 38, height: 38)
                }

                Image(systemName: icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(
                        isActive
                            ? Color(red: 0.961, green: 0.651, blue: 0.137)
                            : Color(white: 0.35)
                    )
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func toolbarIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color(white: 0.35))
            .frame(width: 44, height: 44)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
