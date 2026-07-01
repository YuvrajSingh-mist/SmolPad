import AVFoundation
import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
final class WhisperKitSpeechRecognitionProvider: SpeechRecognitionProviding {
    let backend: SpeechRecognitionBackend = .whisperKit
    let displayName = "WhisperKit"
    weak var delegate: SpeechRecognitionProviderDelegate?

    var isSupported: Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }

    private var transcript = ""
    private let engine = AVAudioEngine()
    private let vad: VoiceActivityDetecting = VoiceActivityDetectorFactory.makeProductionDetector()
    private let appleFallbackTranscriber = AppleSpeechFileFallbackTranscriber()
    private var selectedModelIdentifier = "large-v3-v20240930_626MB"
    private var loadedModelIdentifier: String?
    private var capturedSamples: [Float] = []
    private var latestPartialSampleCount = 0
    private var sampleRate: Double = 16_000
    private var partialTranscriptionTask: Task<Void, Never>?
    private var finalTranscriptionTask: Task<Void, Never>?
    private var isDiscarding = false

    #if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    #endif

    func requestPermission() {
        DiagnosticsLogger.voice.info("WhisperKit provider permission request")
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                DiagnosticsLogger.voice.info("WhisperKit microphone permission granted=\(granted, privacy: .public)")
                if !granted {
                    self.delegate?.speechProvider(self, didFailWithMessage: "Microphone access is not enabled for SmolPad.")
                }
            }
        }
    }

    func start(configuration: SpeechRecognitionSessionConfiguration) {
        DiagnosticsLogger.voice.info(
            "WhisperKit provider start requested model=\(configuration.whisperKitModel, privacy: .public)"
        )

        #if canImport(WhisperKit)
        guard !engine.isRunning else { return }

        resetSessionState()
        if selectedModelIdentifier != configuration.whisperKitModel {
            selectedModelIdentifier = configuration.whisperKitModel
            whisperKit = nil
            loadedModelIdentifier = nil
        }

        finalTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.resolvedWhisperKit()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.finalTranscriptionTask = nil
                    self.startCapturingAudio()
                }
            } catch {
                await MainActor.run {
                    self.finalTranscriptionTask = nil
                    DiagnosticsLogger.voice.error("WhisperKit warmup failed: \(error.localizedDescription, privacy: .public)")
                    self.delegate?.speechProvider(self, didFailWithMessage: "WhisperKit failed to load. Falling back to Apple Speech.")
                }
            }
        }
        #else
        delegate?.speechProvider(self, didFailWithMessage: "WhisperKit is not linked in this build yet.")
        #endif
    }

    func stop() -> String {
        DiagnosticsLogger.voice.info("WhisperKit stop requested chars=\(self.transcript.count, privacy: .public)")
        #if canImport(WhisperKit)
        stopCapturingAudio()
        beginFinalTranscription(useFallbackOnFailure: true)
        #else
        delegate?.speechProvider(self, didChangeListeningState: false)
        #endif
        return transcript
    }

    func stopAndDiscardTranscript() {
        DiagnosticsLogger.voice.notice("WhisperKit stop and discard")
        transcript = ""
        #if canImport(WhisperKit)
        isDiscarding = true
        stopCapturingAudio()
        partialTranscriptionTask?.cancel()
        finalTranscriptionTask?.cancel()
        finalTranscriptionTask = nil
        delegate?.speechProvider(self, didChangeListeningState: false)
        #else
        delegate?.speechProvider(self, didChangeListeningState: false)
        #endif
    }

    #if canImport(WhisperKit)
    private func startCapturingAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.consumeAudioBuffer(buffer)
                }
            }

            engine.prepare()
            try engine.start()
            delegate?.speechProvider(self, didChangeListeningState: true)
            startPartialTranscriptionLoop()
            DiagnosticsLogger.voice.info("WhisperKit live capture started sampleRate=\(self.sampleRate, privacy: .public)")
        } catch {
            DiagnosticsLogger.voice.error("WhisperKit live capture failed: \(error.localizedDescription, privacy: .public)")
            delegate?.speechProvider(self, didFailWithMessage: "WhisperKit could not start recording audio.")
        }
    }

    private func stopCapturingAudio() {
        partialTranscriptionTask?.cancel()
        partialTranscriptionTask = nil

        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        delegate?.speechProvider(self, didChangeListeningState: false)
    }

    private func consumeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isDiscarding else { return }
        guard vad.shouldKeepAudio(from: buffer) else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        capturedSamples.append(contentsOf: samples)
    }

    private func startPartialTranscriptionLoop() {
        partialTranscriptionTask?.cancel()
        partialTranscriptionTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                if Task.isCancelled { break }
                await self.emitPartialTranscriptIfNeeded()
            }
        }
    }

    private func emitPartialTranscriptIfNeeded() async {
        let sampleCount = capturedSamples.count
        guard sampleCount > max(Int(sampleRate * 1.4), 8_000) else { return }
        guard sampleCount - latestPartialSampleCount > Int(sampleRate * 1.0) else { return }

        latestPartialSampleCount = sampleCount
        let snapshot = capturedSamples

        do {
            let text = try await transcribe(samples: snapshot)
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            transcript = normalized
            delegate?.speechProvider(self, didUpdateTranscript: normalized, isFinal: false)
            DiagnosticsLogger.voice.debug("WhisperKit partial transcript chars=\(normalized.count, privacy: .public)")
        } catch {
            DiagnosticsLogger.voice.error("WhisperKit partial transcription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func beginFinalTranscription(useFallbackOnFailure: Bool) {
        finalTranscriptionTask?.cancel()
        let snapshot = capturedSamples

        finalTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finalTranscriptionTask = nil }

            guard !snapshot.isEmpty else {
                await MainActor.run {
                    self.delegate?.speechProvider(self, didUpdateTranscript: "", isFinal: true)
                }
                return
            }

            do {
                let text = try await self.transcribe(samples: snapshot)
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self.transcript = normalized
                    self.delegate?.speechProvider(self, didUpdateTranscript: normalized, isFinal: true)
                }
            } catch {
                DiagnosticsLogger.voice.error("WhisperKit final transcription failed: \(error.localizedDescription, privacy: .public)")
                guard useFallbackOnFailure else {
                    await MainActor.run {
                        self.delegate?.speechProvider(self, didFailWithMessage: error.localizedDescription)
                    }
                    return
                }

                do {
                    let fallbackText = try await self.transcribeWithAppleFallback(samples: snapshot)
                    let normalized = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        self.transcript = normalized
                        self.delegate?.speechProvider(self, didUpdateTranscript: normalized, isFinal: true)
                    }
                } catch {
                    await MainActor.run {
                        self.delegate?.speechProvider(self, didFailWithMessage: "Both WhisperKit and Apple Speech fallback failed.")
                    }
                }
            }
        }
    }

    private func transcribe(samples: [Float]) async throws -> String {
        let url = try writeTemporaryWav(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let kit = try await resolvedWhisperKit()
        DiagnosticsLogger.voice.info("WhisperKit transcribing snapshot samples=\(samples.count, privacy: .public)")
        let result = try await kit.transcribe(audioPath: url.path)
        return extractTranscriptText(from: result)
    }

    private func transcribeWithAppleFallback(samples: [Float]) async throws -> String {
        let url = try writeTemporaryWav(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        DiagnosticsLogger.voice.notice("Falling back to Apple Speech file transcription")
        return try await appleFallbackTranscriber.transcribeAudioFile(at: url)
    }

    private func resolvedWhisperKit() async throws -> WhisperKit {
        if let whisperKit, loadedModelIdentifier == selectedModelIdentifier {
            return whisperKit
        }

        let config = WhisperKitConfig(model: selectedModelIdentifier)
        let instance = try await WhisperKit(config)
        whisperKit = instance
        loadedModelIdentifier = selectedModelIdentifier
        return instance
    }

    private func writeTemporaryWav(samples: [Float], sampleRate: Double) throws -> URL {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SmolPad.WhisperKit", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate audio buffer."
            ])
        }

        buffer.frameLength = frameCount
        let destination = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: samples.count)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smolpad-whisper-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func resetSessionState() {
        transcript = ""
        capturedSamples = []
        latestPartialSampleCount = 0
        isDiscarding = false
        vad.reset()
        partialTranscriptionTask?.cancel()
        partialTranscriptionTask = nil
        finalTranscriptionTask?.cancel()
        finalTranscriptionTask = nil
    }

    private func extractTranscriptText(from result: Any) -> String {
        if let text = result as? String {
            return text
        }

        if let optional = unwrapOptional(result) {
            return extractTranscriptText(from: optional)
        }

        if let array = result as? [Any] {
            let parts = array.map { extractTranscriptText(from: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }

        let mirror = Mirror(reflecting: result)
        if let textChild = mirror.children.first(where: { $0.label == "text" }),
           let text = textChild.value as? String {
            return text
        }

        if let segmentsChild = mirror.children.first(where: { $0.label == "segments" }) {
            return extractTranscriptText(from: segmentsChild.value)
        }

        return String(describing: result)
    }

    private func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return mirror.children.first?.value
    }
    #endif
}
