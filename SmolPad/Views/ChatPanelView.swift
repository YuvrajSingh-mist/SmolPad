import SwiftUI
import UIKit

struct ChatPanelView: View {
    @Bindable var state: CanvasState
    var config: AIConfig
    var voiceManager: VoiceManager

    @Environment(\.openURL) private var openURL
    @State private var response = ""
    @State private var isStreaming = false
    @State private var streamError: String?
    @State private var showsLocalNetworkSettings = false
    @FocusState private var queryFocused: Bool
    @State private var streamingTask: Task<Void, Never>?
    @State private var scrollTick = 0
    @State private var pendingUserQuery: String?
    @State private var thinking = ""
    @State private var rawResponseStream = ""
    @State private var streamedReasoning = ""
    @State private var isThinkingExpanded = true

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
                                cancelStream()
                                state.clearChatSession()
                                response = ""
                                thinking = ""
                                streamError = nil
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.96, green: 0.75, blue: 0.44))
                        }

                        Button {
                            queryFocused = false
                            cancelStream()
                            if voiceManager.isListening {
                                _ = voiceManager.stop()
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

                                if let pendingUserQuery {
                                    MessageBubbleView(message: ChatMessage(role: .user, content: pendingUserQuery))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                }

                                if let streamError {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(streamError)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.red)

                                        if showsLocalNetworkSettings {
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
                                } else if !thinking.isEmpty || !response.isEmpty {
                                    Group {
                                        if !thinking.isEmpty {
                                            ThinkingSectionView(
                                                thinking: thinking,
                                                isExpanded: $isThinkingExpanded,
                                                isStreaming: isStreaming,
                                                isLive: true
                                            )
                                        }

                                        if !response.isEmpty {
                                            MarkdownTextView(text: response, textColor: .white, baseFontSize: 16, spacing: 10)
                                                .padding(.top, thinking.isEmpty ? 0 : 6)
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
                                } else if isStreaming {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("AI is thinking...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                } else if !isStreaming {
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
                            if isStreaming {
                                cancelStream()
                            } else {
                                sendQuery()
                            }
                        } label: {
                            if isStreaming {
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
        }
    }

    private func sendQuery() {
        guard !isStreaming else { return }

        let userQuery = state.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuery.isEmpty else { return }

        resetStreamingPresentation()
        scrollTick = 0
        isStreaming = true
        queryFocused = false
        pendingUserQuery = userQuery
        state.chatDraft = ""
        scrollTick &+= 1

        let task = Task {
            do {
                let stream = try await AIClient.send(
                    image: state.capturedImage,
                    query: userQuery,
                    config: config,
                    history: state.conversation
                )
                var chunkCount = 0
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        present(chunk: chunk, chunkCount: &chunkCount)
                    }
                }
                if Task.isCancelled {
                    await MainActor.run {
                        finishCancellation()
                    }
                } else {
                    await MainActor.run {
                        commitCompletedTurn(for: userQuery)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let aiError = error as? AIError, case .cancelled = aiError {
                    await MainActor.run {
                        finishCancellation()
                    }
                    return
                }
                await MainActor.run {
                    present(error: error)
                }
            }

            await MainActor.run {
                isStreaming = false
                streamingTask = nil
            }
        }

        streamingTask = task
    }

    private func cancelStream() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        finishCancellation()
    }

    private func finishCancellation() {
        if let pendingUserQuery {
            state.appendUserMessage(pendingUserQuery)
            self.pendingUserQuery = nil
        }
        resetStreamingPresentation()
        scrollTick &+= 1
    }

    private func reconcileStreamBuffers() {
        let parsed = Self.splitThinkingAndResponse(from: rawResponseStream)
        let combinedThinking = [streamedReasoning, parsed.thinking]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: streamedReasoning.isEmpty || parsed.thinking.isEmpty ? "" : "\n\n")

        thinking = combinedThinking
        response = parsed.response
    }

    private static func splitThinkingAndResponse(from raw: String) -> (thinking: String, response: String) {
        guard !raw.isEmpty else { return ("", "") }

        var remaining = raw
        var thinkingParts: [String] = []
        var responseParts: [String] = []

        while let openRange = remaining.range(of: "<think>") {
            let before = remaining[..<openRange.lowerBound]
            if !before.isEmpty {
                responseParts.append(String(before))
            }

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "</think>") {
                let thought = afterOpen[..<closeRange.lowerBound]
                if !thought.isEmpty {
                    thinkingParts.append(String(thought))
                }
                remaining = String(afterOpen[closeRange.upperBound...])
            } else {
                let unfinished = afterOpen.trimmingCharacters(in: .whitespacesAndNewlines)
                if !unfinished.isEmpty {
                    thinkingParts.append(unfinished)
                }
                remaining = ""
                break
            }
        }

        if !remaining.isEmpty {
            responseParts.append(remaining)
        }

        let thinking = thinkingParts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let response = responseParts
            .joined()
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (thinking, response)
    }

    private func resetStreamingPresentation() {
        response = ""
        thinking = ""
        rawResponseStream = ""
        streamedReasoning = ""
        isThinkingExpanded = true
        streamError = nil
        showsLocalNetworkSettings = false
    }

    private func present(chunk: StreamChunk, chunkCount: inout Int) {
        if chunk.isThinking {
            streamedReasoning += chunk.text
        } else {
            rawResponseStream += chunk.text
        }
        reconcileStreamBuffers()
        chunkCount += 1
        if chunkCount % 3 == 0 {
            scrollTick &+= 1
        }
    }

    private func commitCompletedTurn(for userQuery: String) {
        state.appendConversationTurn(user: userQuery, assistant: response, thinking: thinking)
        pendingUserQuery = nil
        response = ""
        thinking = ""
        rawResponseStream = ""
        streamedReasoning = ""
        scrollTick &+= 1
    }

    private func present(error: Error) {
        streamError = error.localizedDescription
        if let pendingUserQuery {
            state.appendUserMessage(pendingUserQuery)
            self.pendingUserQuery = nil
        }
        showsLocalNetworkSettings = {
            guard let aiError = error as? AIError else { return false }
            if case .localNetworkDenied = aiError {
                return true
            }
            return false
        }()
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
