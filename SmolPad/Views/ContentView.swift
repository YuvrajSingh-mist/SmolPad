import SwiftUI

struct ContentView: View {
    @State private var canvasState = CanvasState()
    @State private var aiConfig = AIConfig()
    @State private var voiceManager = VoiceManager()
    @State private var showSettings = false
    @State private var backendStatus = BackendStatusSnapshot(label: "Connect: MLX", isConnected: false)

    var body: some View {
        ZStack {
            Color(red: 0.969, green: 0.965, blue: 0.957)
                .ignoresSafeArea()

            GeometryReader { _ in
                Canvas { context, size in
                    guard size.width > 0, size.height > 0,
                          !size.width.isNaN, !size.height.isNaN,
                          !size.width.isInfinite, !size.height.isInfinite else { return }
                    var y: CGFloat = 36
                    while y < size.height {
                        var rule = Path()
                        rule.move(to: CGPoint(x: 20, y: y))
                        rule.addLine(to: CGPoint(x: size.width - 20, y: y))
                        context.stroke(
                            rule,
                            with: .color(Color(red: 0, green: 0, blue: 0.47, opacity: 0.055)),
                            lineWidth: 0.5
                        )
                        y += 36
                    }

                    var margin = Path()
                    margin.move(to: CGPoint(x: 64, y: 0))
                    margin.addLine(to: CGPoint(x: 64, y: size.height))
                    context.stroke(
                        margin,
                        with: .color(Color(red: 0.86, green: 0, blue: 0, opacity: 0.10)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
            }

            CanvasHostView(state: canvasState)
                .ignoresSafeArea()

            if canvasState.activeTool.isSelection {
                SelectionOverlayView(state: canvasState)
            }

            VStack {
                HStack {
                    Spacer()
                    backendStatusPill
                }
                .padding(.top, 18)
                .padding(.horizontal, 20)

                Spacer()
            }

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    ToolbarView(state: canvasState, showSettings: $showSettings)
                        .padding(.trailing, 20)
                        .padding(.bottom, 36)
                }
            }

            // Floating chat button — always accessible
            if !canvasState.showChat {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            canvasState.showChat = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Color(white: 0.28))
                                .frame(width: 44, height: 44)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color(white: 0.0, opacity: 0.08), lineWidth: 0.5)
                                }
                        }
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .padding(.trailing, 92)
                        .padding(.bottom, 32)
                    }
                }
            }

            if canvasState.showChat {
                ChatPanelView(
                    state: canvasState,
                    config: aiConfig,
                    voiceManager: voiceManager
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let error = canvasState.selectionError {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            canvasState.dismissError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(white: 0.5))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.18, green: 0.18, blue: 0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: canvasState.showChat)
        .animation(.easeInOut(duration: 0.15), value: canvasState.activeTool)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: canvasState.selectionError)
        .sheet(isPresented: $showSettings) {
            SettingsView(config: aiConfig, voiceManager: voiceManager)
        }
        .task(id: backendStatusTaskKey) {
            while !Task.isCancelled {
                let snapshot = await BackendStatusService.check(config: aiConfig)
                await MainActor.run {
                    backendStatus = snapshot
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var backendStatusTaskKey: String {
        [
            aiConfig.provider.rawValue,
            aiConfig.inferencePath.rawValue,
            aiConfig.textModelID,
            aiConfig.mlxURL,
            aiConfig.ollamaURL,
            aiConfig.apiKey
        ].joined(separator: "|")
    }

    private var backendStatusPill: some View {
        let tint = backendStatus.isConnected
            ? Color(red: 0.11, green: 0.63, blue: 0.31)
            : Color(red: 0.83, green: 0.17, blue: 0.17)

        return HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .shadow(color: tint.opacity(0.85), radius: 8)

            Text(backendStatus.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.24))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: tint.opacity(backendStatus.isConnected ? 0.18 : 0.12), radius: 12, y: 3)
    }
}

private struct BackendStatusSnapshot {
    let label: String
    let isConnected: Bool
}

private enum BackendStatusService {
    static func check(config: AIConfig) async -> BackendStatusSnapshot {
        switch config.provider {
        case .onDevice:
            let ok = OnDeviceTextClient.isRuntimeAvailable
            let label = ok ? "Connect: \(config.provider.rawValue)" : "On Device Unavailable"
            return BackendStatusSnapshot(label: label, isConnected: ok)
        case .mlx:
            let ok = await isReachable(urlString: "\(config.mlxURL)/v1/models")
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .ollama:
            let ok = await isReachable(urlString: "\(config.ollamaURL)/api/tags")
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .openai, .claude:
            let ok = !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        }
    }

    private static func isReachable(urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false

        do {
            let (_, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
