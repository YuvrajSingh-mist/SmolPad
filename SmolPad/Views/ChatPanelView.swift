import SwiftUI
import UIKit

struct ChatPanelView: View {
    var state: CanvasState
    var config: AIConfig
    var voiceManager: VoiceManager

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var response = ""
    @State private var isStreaming = false
    @State private var streamError: String?
    @State private var showsLocalNetworkSettings = false
    @FocusState private var queryFocused: Bool
    @State private var streamingTask: Task<Void, Never>?
    @State private var scrollTick = 0
    @State private var conversation: [ChatMessage] = []
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
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            queryFocused = false
                            if voiceManager.isListening {
                                _ = voiceManager.stop()
                            }
                            state.dismissChat()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
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
                                ForEach(Array(conversation.enumerated()), id: \.offset) { _, msg in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(msg.role == "user" ? "You" : "AI")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(msg.role == "user"
                                                ? Color(red: 0.961, green: 0.651, blue: 0.137)
                                                : .secondary)
                                        if msg.role == "assistant",
                                           let priorThinking = msg.thinking,
                                           !priorThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            PastThinkingView(thinking: priorThinking)
                                                .padding(.bottom, 4)
                                        }
                                        if msg.role == "assistant",
                                           let priorThinking = msg.thinking,
                                           !priorThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Divider()
                                                .background(.secondary.opacity(0.12))
                                                .padding(.bottom, 8)
                                        }
                                        MarkdownTextView(text: msg.content, textColor: .primary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    Divider().background(.secondary.opacity(0.15))
                                }

                                if let pendingUserQuery {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("You")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color(red: 0.961, green: 0.651, blue: 0.137))
                                        MarkdownTextView(text: pendingUserQuery, textColor: .primary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)

                                    if isStreaming {
                                        Divider().background(.secondary.opacity(0.15))
                                    }
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
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                } else if let voiceError = voiceManager.error {
                                    Text(voiceError)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                } else if !thinking.isEmpty || !response.isEmpty {
                                    if !thinking.isEmpty {
                                        ThinkingSectionView(
                                            thinking: thinking,
                                            isExpanded: $isThinkingExpanded,
                                            isStreaming: isStreaming,
                                            isLive: true
                                        )
                                        .padding(.horizontal, 20)
                                    }

                                    if !response.isEmpty {
                                        if !thinking.isEmpty {
                                            Divider()
                                                .background(.secondary.opacity(0.12))
                                                .padding(.horizontal, 20)
                                                .padding(.top, 6)
                                        }
                                        MarkdownTextView(text: response, textColor: .primary, baseFontSize: 15, spacing: 7)
                                            .padding(.horizontal, 20)
                                            .padding(.top, thinking.isEmpty ? 10 : 12)
                                            .padding(.bottom, 10)
                                    }
                                } else if isStreaming {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("AI is thinking...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                } else if !isStreaming {
                                    Text("Your answer will appear here.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
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
                        TextField("Ask about this...", text: $query)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .tint(.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.send)
                            .focused($queryFocused)
                            .onSubmit {
                                sendQuery()
                            }
                            .onChange(of: voiceManager.transcript) { _, transcript in
                                if !transcript.isEmpty {
                                    query = transcript
                                }
                            }

                        Button {
                            queryFocused = false
                            if voiceManager.isListening {
                                query = voiceManager.stop()
                            } else {
                                voiceManager.start()
                            }
                        } label: {
                            Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(voiceManager.isListening ? .red : .secondary)
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
                                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? .secondary.opacity(0.5)
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
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
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

        let userQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuery.isEmpty else { return }

        response = ""
        thinking = ""
        rawResponseStream = ""
        streamedReasoning = ""
        isThinkingExpanded = true
        streamError = nil
        showsLocalNetworkSettings = false
        scrollTick = 0
        isStreaming = true
        queryFocused = false
        pendingUserQuery = userQuery
        query = ""
        scrollTick &+= 1

        let task = Task {
            do {
                let stream = try await AIClient.send(
                    image: state.capturedImage,
                    query: userQuery,
                    config: config,
                    history: conversation + [ChatMessage(role: "user", content: userQuery)]
                )
                var chunkCount = 0
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run {
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
                }
                if Task.isCancelled {
                    await MainActor.run {
                        if !response.isEmpty {
                            response += "\n\n— Cancelled —"
                        }
                    }
                } else {
                    // Save turn to conversation history
                    await MainActor.run {
                        conversation.append(ChatMessage(role: "user", content: userQuery))
                        conversation.append(ChatMessage(role: "assistant", content: response, thinking: thinking))
                        pendingUserQuery = nil
                        response = ""
                        thinking = ""
                        rawResponseStream = ""
                        streamedReasoning = ""
                        scrollTick &+= 1
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    streamError = error.localizedDescription
                    if let pendingUserQuery {
                        conversation.append(ChatMessage(role: "user", content: pendingUserQuery))
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
        if let pendingUserQuery {
            conversation.append(ChatMessage(role: "user", content: pendingUserQuery))
            self.pendingUserQuery = nil
        }
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
                    textColor: .secondary,
                    baseFontSize: 13,
                    spacing: 5
                )
                if isStreaming && isLive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.secondary.opacity(0.7))
                            .frame(width: 7, height: 7)
                        Text("Loading")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.85))
                Text(isStreaming && isLive ? "Thinking..." : "Thinking")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            Rectangle()
                .fill(.secondary.opacity(0.16))
                .frame(width: 2)
                .padding(.vertical, 4)
        }
    }
}
