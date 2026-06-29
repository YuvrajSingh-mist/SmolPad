import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class VoiceManager: NSObject {
    var transcript = ""
    var isListening = false
    var error: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var isFinishing = false

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                if status != .authorized {
                    self?.error = "Speech recognition is not enabled for SmolPad."
                }
            }
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if !granted {
                    self?.error = "Microphone access is not enabled for SmolPad."
                }
            }
        }
    }

    func start() {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            requestPermission()
            error = "Allow speech recognition, then tap the mic again."
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition is not enabled for SmolPad."
            return
        }

        guard recognizer?.isAvailable == true else {
            error = "Speech recognition is temporarily unavailable."
            return
        }

        guard !engine.isRunning else { return }

        error = nil
        transcript = ""
        isFinishing = false

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

                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }

                    if let recognitionError {
                        if self.isFinishing || self.isExpectedStopError(recognitionError) {
                            self.cleanupRecognition()
                        } else {
                            self.error = recognitionError.localizedDescription
                            self.stopEngine()
                        }
                    } else if result?.isFinal ?? false {
                        self.cleanupRecognition()
                    }
                }
            }

            isListening = true
        } catch {
            self.error = error.localizedDescription
            stopEngine()
        }
    }

    func stop() -> String {
        error = nil
        isFinishing = true
        stopAudioCapture()
        return transcript
    }

    private func stopEngine() {
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
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func cleanupRecognition() {
        task = nil
        request = nil
        isListening = false
        isFinishing = false
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
