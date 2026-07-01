import SwiftUI

struct ContentView: View {
    @State private var canvasState = CanvasState()
    @State private var aiConfig = AIConfig()
    @State private var voiceManager = VoiceManager()
    @State private var showSettings = false
    @State private var backendStatus = BackendStatusSnapshot(label: "Connect: MLX", isConnected: false)
    @StateObject private var onDeviceRuntimeStatus = OnDeviceRuntimeStatus.shared

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
                let interval = await BackendStatusService.nextPollInterval(config: aiConfig)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private var backendStatusTaskKey: String {
        [
            aiConfig.provider.rawValue,
            aiConfig.inferencePath.rawValue,
            aiConfig.textModelID,
            aiConfig.model,
            aiConfig.mlxURL,
            aiConfig.ollamaURL,
            aiConfig.apiKey
        ].joined(separator: "|")
    }

    private var backendStatusPill: some View {
        let runtimeOverlay = runtimeOverlayStatus
        let tint = runtimeOverlay?.tint ?? (
            backendStatus.isConnected
                ? Color(red: 0.11, green: 0.63, blue: 0.31)
                : Color(red: 0.83, green: 0.17, blue: 0.17)
        )

        return HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .shadow(color: tint.opacity(0.85), radius: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(backendStatus.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.24))

                if let runtimeOverlay {
                    Text(runtimeOverlay.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.36))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .id(runtimeOverlay.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: tint.opacity(backendStatus.isConnected ? 0.18 : 0.12), radius: 12, y: 3)
        .animation(.easeInOut(duration: 0.24), value: runtimeOverlay?.id ?? "idle")
    }

    private var runtimeOverlayStatus: RuntimeOverlayStatus? {
        guard (aiConfig.provider == .onDevice || aiConfig.provider == .llamaCpp), onDeviceRuntimeStatus.isVisible else { return nil }

        switch onDeviceRuntimeStatus.phase {
        case .idle:
            return nil
        case .preparing:
            return RuntimeOverlayStatus(
                id: "preparing-\(onDeviceRuntimeStatus.modelIdentifier)",
                text: "Preparing model",
                tint: Color(red: 0.82, green: 0.58, blue: 0.15)
            )
        case .downloading:
            let percent = Int((onDeviceRuntimeStatus.progressFraction * 100).rounded())
            return RuntimeOverlayStatus(
                id: "downloading-\(onDeviceRuntimeStatus.modelIdentifier)-\(percent)",
                text: "Downloading model \(percent)%",
                tint: Color(red: 0.20, green: 0.52, blue: 0.87)
            )
        case .ready:
            return RuntimeOverlayStatus(
                id: "ready-\(onDeviceRuntimeStatus.modelIdentifier)",
                text: "Model ready",
                tint: Color(red: 0.11, green: 0.63, blue: 0.31)
            )
        case .generating:
            return RuntimeOverlayStatus(
                id: "generating-\(onDeviceRuntimeStatus.modelIdentifier)",
                text: "Running on device",
                tint: Color(red: 0.55, green: 0.34, blue: 0.84)
            )
        case .failed:
            return RuntimeOverlayStatus(
                id: "failed-\(onDeviceRuntimeStatus.modelIdentifier)",
                text: "On-device error",
                tint: Color(red: 0.83, green: 0.17, blue: 0.17)
            )
        }
    }
}

private struct BackendStatusSnapshot {
    let label: String
    let isConnected: Bool
}

private struct RuntimeOverlayStatus {
    let id: String
    let text: String
    let tint: Color
}

private enum BackendStatusService {
    static func check(config: AIConfig) async -> BackendStatusSnapshot {
        switch config.provider {
        case .onDevice:
            let ok = OnDeviceTextClient.isRuntimeAvailable
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .llamaCpp:
            let ok = EmbeddedLlamaVisionClient.isRuntimeAvailable && EmbeddedLlamaVisionClient.isModelInstalled(for: config)
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .mlx:
            guard let probeURL = probeURL(baseURL: config.mlxURL, path: "/v1/models") else {
                return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: false)
            }
            let ok = await BackendProbeCoordinator.shared.probe(url: probeURL)
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .ollama:
            guard let probeURL = probeURL(baseURL: config.ollamaURL, path: "/api/tags") else {
                return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: false)
            }
            let ok = await BackendProbeCoordinator.shared.probe(url: probeURL)
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        case .openai, .claude:
            let ok = !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return BackendStatusSnapshot(label: "Connect: \(config.provider.rawValue)", isConnected: ok)
        }
    }

    static func nextPollInterval(config: AIConfig) async -> TimeInterval {
        switch config.provider {
        case .llamaCpp:
            return 15
        case .mlx:
            guard let probeURL = probeURL(baseURL: config.mlxURL, path: "/v1/models") else { return 30 }
            return await BackendProbeCoordinator.shared.nextPollInterval(for: probeURL)
        case .ollama:
            guard let probeURL = probeURL(baseURL: config.ollamaURL, path: "/api/tags") else { return 30 }
            return await BackendProbeCoordinator.shared.nextPollInterval(for: probeURL)
        case .onDevice, .openai, .claude:
            return 15
        }
    }

    private static func probeURL(baseURL: String, path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed + path) else { return nil }
        return url
    }

    fileprivate static func isReachable(url: URL) async -> Bool {
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

private actor BackendProbeCoordinator {
    static let shared = BackendProbeCoordinator()

    private struct ProbeState {
        var consecutiveFailures = 0
        var nextAllowedAttempt = Date.distantPast
        var lastKnownReachable = false
    }

    private var states: [String: ProbeState] = [:]

    func probe(url: URL) async -> Bool {
        let key = url.absoluteString
        let now = Date()
        var state = states[key] ?? ProbeState()

        if now < state.nextAllowedAttempt {
            return state.lastKnownReachable
        }

        let ok = await BackendStatusService.isReachable(url: url)
        if ok {
            state.consecutiveFailures = 0
            state.nextAllowedAttempt = now.addingTimeInterval(15)
            state.lastKnownReachable = true
        } else {
            state.consecutiveFailures += 1
            let cooldown = min(pow(2, Double(max(0, state.consecutiveFailures - 1))) * 5, 120)
            state.nextAllowedAttempt = now.addingTimeInterval(cooldown)
            state.lastKnownReachable = false
        }

        states[key] = state
        return ok
    }

    func nextPollInterval(for url: URL) -> TimeInterval {
        let key = url.absoluteString
        let state = states[key] ?? ProbeState()
        let remaining = state.nextAllowedAttempt.timeIntervalSinceNow
        return max(5, remaining > 0 ? remaining : 15)
    }
}
