import AVFoundation
import Foundation
import Speech

@MainActor
final class AppleSpeechRecognitionProvider: NSObject, SpeechRecognitionProviding {
    let backend: SpeechRecognitionBackend = .appleSpeech
    let displayName = "Apple Speech"
    let isSupported = true

    weak var delegate: SpeechRecognitionProviderDelegate?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var isFinishing = false
    private var shouldIgnoreIncomingTranscript = false
    private var transcript = ""

    func requestPermission() {
        DiagnosticsLogger.voice.info("AppleSpeech requesting speech and microphone permissions")

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                DiagnosticsLogger.voice.info("AppleSpeech authorization status=\(String(describing: status), privacy: .public)")
                if status != .authorized {
                    self.delegate?.speechProvider(self, didFailWithMessage: "Speech recognition is not enabled for SmolPad.")
                }
            }
        }

        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                DiagnosticsLogger.voice.info("AppleSpeech microphone permission granted=\(granted, privacy: .public)")
                if !granted {
                    self.delegate?.speechProvider(self, didFailWithMessage: "Microphone access is not enabled for SmolPad.")
                }
            }
        }
    }

    func start(configuration: SpeechRecognitionSessionConfiguration) {
        DiagnosticsLogger.voice.info("AppleSpeech start locale=\(configuration.locale.identifier, privacy: .public)")

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            requestPermission()
            delegate?.speechProvider(self, didFailWithMessage: "Allow speech recognition, then tap the mic again.")
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            delegate?.speechProvider(self, didFailWithMessage: "Speech recognition is not enabled for SmolPad.")
            return
        }

        guard recognizer?.isAvailable == true else {
            delegate?.speechProvider(self, didFailWithMessage: "Speech recognition is temporarily unavailable.")
            return
        }

        guard !engine.isRunning else { return }

        transcript = ""
        isFinishing = false
        shouldIgnoreIncomingTranscript = false

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.request?.append(buffer)
                }
            }

            engine.prepare()
            try engine.start()

            task = recognizer?.recognitionTask(with: request) { [weak self] result, recognitionError in
                Task { @MainActor in
                    guard let self else { return }

                    if let result, !self.shouldIgnoreIncomingTranscript {
                        self.transcript = result.bestTranscription.formattedString
                        DiagnosticsLogger.voice.debug(
                            "AppleSpeech transcript final=\(result.isFinal, privacy: .public) text=\(DiagnosticsLogger.truncated(self.transcript, limit: 240), privacy: .public)"
                        )
                        self.delegate?.speechProvider(self, didUpdateTranscript: self.transcript, isFinal: result.isFinal)
                    }

                    if let recognitionError {
                        if self.isFinishing || self.isExpectedStopError(recognitionError) {
                            DiagnosticsLogger.voice.notice("AppleSpeech expected stop: \(recognitionError.localizedDescription, privacy: .public)")
                            self.cleanupRecognition()
                        } else {
                            DiagnosticsLogger.voice.error("AppleSpeech error: \(recognitionError.localizedDescription, privacy: .public)")
                            self.delegate?.speechProvider(self, didFailWithMessage: recognitionError.localizedDescription)
                            self.stopEngine()
                        }
                    } else if result?.isFinal ?? false {
                        DiagnosticsLogger.voice.info("AppleSpeech produced final transcript")
                        self.cleanupRecognition()
                    }
                }
            }

            delegate?.speechProvider(self, didChangeListeningState: true)
        } catch {
            DiagnosticsLogger.voice.error("AppleSpeech failed to start: \(error.localizedDescription, privacy: .public)")
            delegate?.speechProvider(self, didFailWithMessage: error.localizedDescription)
            stopEngine()
        }
    }

    func stop() -> String {
        DiagnosticsLogger.voice.info("AppleSpeech stop keeping transcript chars=\(transcript.count, privacy: .public)")
        isFinishing = true
        stopAudioCapture()
        return transcript
    }

    func stopAndDiscardTranscript() {
        DiagnosticsLogger.voice.notice("AppleSpeech stop and discard transcript")
        isFinishing = true
        shouldIgnoreIncomingTranscript = true
        transcript = ""
        stopAudioCapture()
    }

    private func stopEngine() {
        DiagnosticsLogger.voice.notice("AppleSpeech stopping engine")
        stopAudioCapture()
        task?.cancel()
        cleanupRecognition()
    }

    private func stopAudioCapture() {
        request?.endAudio()
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        delegate?.speechProvider(self, didChangeListeningState: false)
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func cleanupRecognition() {
        DiagnosticsLogger.voice.debug("AppleSpeech cleanup")
        task = nil
        request = nil
        isFinishing = false
        shouldIgnoreIncomingTranscript = false
        delegate?.speechProvider(self, didChangeListeningState: false)
    }

    private func isExpectedStopError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 4099 {
            return true
        }
        if nsError.domain == "kAFAssistantErrorDomain" {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("aborted")
    }
}
