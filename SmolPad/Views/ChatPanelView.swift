import SwiftUI
import UIKit

struct ChatPanelView: View {
    @Bindable var state: CanvasState
    var config: AIConfig
    var voiceManager: VoiceManager

    @Environment(\.openURL) private var openURL
    @FocusState private var queryFocused: Bool
    @State private var scrollTick = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(white: 0.0, opacity: 0.15))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    HStack {
                        Text("Ask AI")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        if !state.conversation.isEmpty {
                            Button("Clear") {
                                state.clearChatSession()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.96, green: 0.75, blue: 0.44))
                        }

                        Button {
                            queryFocused = false
                            if voiceManager.isListening {
                                voiceManager.stopAndDiscardTranscript()
                            }
                            state.dismissChat()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    if let image = state.capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.secondary.opacity(0.2), lineWidth: 0.5)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // Conversation history
                                ForEach(Array(state.conversation.enumerated()), id: \.offset) { _, msg in
                                    MessageBubbleView(message: msg)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                }

                                if let pendingUserQuery = state.pendingUserQuery {
                                    MessageBubbleView(message: ChatMessage(role: .user, content: pendingUserQuery))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                }

                                if let streamError = state.streamError {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(streamError)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.red)

                                        if state.showsLocalNetworkSettings {
                                            Button("Open Settings") {
                                                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                                    return
                                                }
                                                openURL(settingsURL)
                                            }
                                            .font(.system(size: 14, weight: .semibold))
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                } else if let voiceError = voiceManager.error {
                                    Text(voiceError)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                } else if !state.streamThinking.isEmpty || !state.streamResponse.isEmpty {
                                    Group {
                                        if !state.streamThinking.isEmpty {
                                            ThinkingSectionView(
                                                thinking: state.streamThinking,
                                                isExpanded: $state.isThinkingExpanded,
                                                isStreaming: state.isStreaming,
                                                isLive: true
                                            )
                                        }

                                        if !state.streamResponse.isEmpty {
                                            MarkdownTextView(text: state.streamResponse, textColor: .white, baseFontSize: 16, spacing: 10)
                                                .padding(.top, state.streamThinking.isEmpty ? 0 : 6)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.065))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                            }
                                    )
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                } else if state.isStreaming {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("AI is thinking...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                } else if !state.isStreaming {
                                    Text("Your answer will appear here.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                }

                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: .infinity)
                        .scrollDismissesKeyboard(.interactively)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            queryFocused = false
                        }
                        .onChange(of: scrollTick) { _, _ in
                            proxy.scrollTo("bottom")
                        }
                    }

                    Divider().background(.secondary.opacity(0.15))

                    HStack(spacing: 8) {
                        if config.inferencePath == .appleVisionOCRPlusText {
                            Text("OCR + \(config.selectedTextModel.displayName)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.80, green: 0.88, blue: 0.96))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        } else {
                            Text("Direct VLM")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.80, green: 0.88, blue: 0.96))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }

                        Circle()
                            .fill(voiceManager.activeBackend == .whisperKit ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text("SR: \(voiceManager.activeBackendDisplayName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        if voiceManager.isListening {
                            Text("Listening")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.96, green: 0.75, blue: 0.44))
                        } else if voiceManager.isProcessingSpeech {
                            Text("Transcribing")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.55, green: 0.83, blue: 0.96))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    HStack(spacing: 10) {
                        TextField("Ask about this...", text: $state.chatDraft)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .tint(Color(red: 0.96, green: 0.75, blue: 0.44))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.send)
                            .focused($queryFocused)
                            .onSubmit {
                                sendQuery()
                            }
                            .onChange(of: voiceManager.transcript) { _, transcript in
                                if !transcript.isEmpty {
                                    state.chatDraft = transcript
                                }
                            }

                        Button {
                            queryFocused = false
                            if voiceManager.isListening {
                                state.chatDraft = voiceManager.stop()
                            } else {
                                voiceManager.start()
                            }
                        } label: {
                            Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(voiceManager.isListening ? .red : .white.opacity(0.7))
                                .frame(width: 38, height: 38)
                                .scaleEffect(voiceManager.isListening ? 1.08 : 1.0)
                                .animation(
                                    voiceManager.isListening
                                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                                        : .default,
                                    value: voiceManager.isListening
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            if state.isStreaming {
                                state.cancelStreaming()
                                scrollTick &+= 1
                            } else {
                                sendQuery()
                            }
                        } label: {
                            if state.isStreaming {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.red)
                                    .frame(width: 38, height: 38)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(
                                        state.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? .white.opacity(0.28)
                                            : Color(red: 0.961, green: 0.651, blue: 0.137)
                                    )
                                    .frame(width: 38, height: 38)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom : 12)
                }
                .frame(height: geometry.size.height * 0.62)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.17, blue: 0.20),
                            Color(red: 0.11, green: 0.12, blue: 0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.26), radius: 22, y: -8)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            voiceManager.requestPermission()
            scrollTick &+= 1
        }
        .onChange(of: state.pendingUserQuery) { _, _ in
            scrollTick &+= 1
        }
        .onChange(of: state.streamResponse) { _, _ in
            scrollTick &+= 1
        }
        .onChange(of: state.streamThinking) { _, _ in
            scrollTick &+= 1
        }
        .onChange(of: state.conversation.count) { _, _ in
            scrollTick &+= 1
        }
    }

    private func sendQuery() {
        queryFocused = false
        if voiceManager.isListening {
            voiceManager.stopAndDiscardTranscript()
        }
        scrollTick = 0
        state.sendQuery(config: config)
        scrollTick &+= 1
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user

        VStack(alignment: .leading, spacing: 10) {
            Text(message.role.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    isUser
                        ? Color(red: 0.96, green: 0.75, blue: 0.44)
                        : Color.white.opacity(0.52)
                )

            if message.role == .assistant,
               let priorThinking = message.thinking,
               !priorThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PastThinkingView(thinking: priorThinking)
            }

            MarkdownTextView(
                text: message.content,
                textColor: .white,
                baseFontSize: isUser ? 15 : 16,
                spacing: isUser ? 8 : 10
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isUser
                        ? Color(red: 0.96, green: 0.75, blue: 0.44).opacity(0.12)
                        : Color.white.opacity(0.065)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isUser
                                ? Color(red: 0.96, green: 0.75, blue: 0.44).opacity(0.24)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
        )
    }
}

private struct PastThinkingView: View {
    let thinking: String
    @State private var isExpanded = false

    var body: some View {
        ThinkingSectionView(
            thinking: thinking,
            isExpanded: $isExpanded,
            isStreaming: false,
            isLive: false
        )
    }
}

private struct ThinkingSectionView: View {
    let thinking: String
    @Binding var isExpanded: Bool
    let isStreaming: Bool
    let isLive: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                MarkdownTextView(
                    text: thinking,
                    textColor: Color.white.opacity(0.76),
                    baseFontSize: 13,
                    spacing: 5
                )
                if isStreaming && isLive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: 7, height: 7)
                        Text("Loading")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(isStreaming && isLive ? "Thinking..." : "Thinking")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
        )
    }
}
