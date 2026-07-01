import Foundation
import Observation

@Observable
@MainActor
final class VoiceManager: NSObject, SpeechRecognitionProviderDelegate {
    var transcript = ""
    var isListening = false
    var isProcessingSpeech = false
    var error: String?
    var preferredBackend: SpeechRecognitionBackend {
        didSet {
            guard self.preferredBackend != oldValue else { return }
            activeBackend = resolvedBackend(for: self.preferredBackend)
            savePreferences()
            DiagnosticsLogger.voice.info("Preferred speech backend changed to \(self.preferredBackend.rawValue, privacy: .public)")
        }
    }
    var whisperKitModelIdentifier: String {
        didSet {
            guard self.whisperKitModelIdentifier != oldValue else { return }
            savePreferences()
            DiagnosticsLogger.voice.info("WhisperKit model identifier updated to \(self.whisperKitModelIdentifier, privacy: .public)")
        }
    }
    private(set) var activeBackend: SpeechRecognitionBackend

    @ObservationIgnored private let appleProvider = AppleSpeechRecognitionProvider()
    @ObservationIgnored private let whisperKitProvider = WhisperKitSpeechRecognitionProvider()
    @ObservationIgnored private var activeProvider: (any SpeechRecognitionProviding)?

    private enum Key: String {
        case preferredBackend
        case whisperKitModelIdentifier
    }

    override init() {
        let defaults = UserDefaults.standard
        let storedBackend = defaults.string(forKey: Key.preferredBackend.rawValue)
        preferredBackend = SpeechRecognitionBackend(rawValue: storedBackend ?? "") ?? .automatic

        let storedModel = defaults.string(forKey: Key.whisperKitModelIdentifier.rawValue) ?? ""
        whisperKitModelIdentifier = storedModel.isEmpty ? "large-v3-v20240930_626MB" : storedModel
        activeBackend = .appleSpeech

        super.init()

        appleProvider.delegate = self
        whisperKitProvider.delegate = self
        activeBackend = resolvedBackend(for: preferredBackend)
    }

    var preferredBackendDescription: String {
        self.preferredBackend.description
    }

    var activeBackendDisplayName: String {
        provider(for: self.activeBackend).displayName
    }

    var whisperKitAvailable: Bool {
        whisperKitProvider.isSupported
    }

    func requestPermission() {
        DiagnosticsLogger.voice.info("VoiceManager requesting permissions preferredBackend=\(self.preferredBackend.rawValue, privacy: .public)")

        appleProvider.requestPermission()
        if whisperKitProvider.isSupported {
            whisperKitProvider.requestPermission()
        }
    }

    func start() {
        let backend = resolvedBackend(for: self.preferredBackend)
        activeBackend = backend
        let provider = provider(for: backend)

        guard provider.isSupported else {
            error = unsupportedMessage(for: backend)
            DiagnosticsLogger.voice.error("Selected unsupported speech backend \(backend.rawValue, privacy: .public)")
            return
        }

        error = nil
        transcript = ""
        isProcessingSpeech = false
        activeProvider = provider

        DiagnosticsLogger.voice.info("VoiceManager starting backend=\(backend.rawValue, privacy: .public)")
        provider.start(
            configuration: SpeechRecognitionSessionConfiguration(
                locale: Locale.current,
                whisperKitModel: self.whisperKitModelIdentifier
            )
        )
    }

    func stop() -> String {
        guard let activeProvider else {
            return transcript
        }

        DiagnosticsLogger.voice.info("VoiceManager stop backend=\(self.activeBackend.rawValue, privacy: .public)")
        if self.activeBackend == .whisperKit {
            isProcessingSpeech = true
        }
        let finalTranscript = activeProvider.stop()
        if !finalTranscript.isEmpty {
            transcript = finalTranscript
        }
        return transcript
    }

    func stopAndDiscardTranscript() {
        DiagnosticsLogger.voice.notice("VoiceManager stop and discard backend=\(self.activeBackend.rawValue, privacy: .public)")
        activeProvider?.stopAndDiscardTranscript()
        transcript = ""
        isProcessingSpeech = false
    }

    func speechProvider(_ provider: any SpeechRecognitionProviding, didChangeListeningState isListening: Bool) {
        self.isListening = isListening
        if !isListening, self.activeBackend == provider.backend {
            if provider.backend != .whisperKit || !self.isProcessingSpeech {
                activeProvider = nil
            }
        }
        DiagnosticsLogger.voice.debug("VoiceManager listening state backend=\(provider.backend.rawValue, privacy: .public) isListening=\(self.isListening, privacy: .public)")
    }

    func speechProvider(_ provider: any SpeechRecognitionProviding, didUpdateTranscript transcript: String, isFinal: Bool) {
        self.transcript = transcript
        self.error = nil
        if isFinal {
            isProcessingSpeech = false
            if self.activeBackend == provider.backend {
                activeProvider = nil
            }
        }
        DiagnosticsLogger.voice.debug(
            "VoiceManager transcript update backend=\(provider.backend.rawValue, privacy: .public) final=\(isFinal, privacy: .public) text=\(DiagnosticsLogger.truncated(self.transcript, limit: 240), privacy: .public)"
        )
    }

    func speechProvider(_ provider: any SpeechRecognitionProviding, didFailWithMessage message: String) {
        if provider.backend == .whisperKit, self.preferredBackend == .automatic, !self.isListening, !self.isProcessingSpeech {
            DiagnosticsLogger.voice.notice("Automatic SR fallback switching from WhisperKit to Apple Speech")
            activeBackend = .appleSpeech
            activeProvider = appleProvider
            error = nil
            appleProvider.start(
                configuration: SpeechRecognitionSessionConfiguration(
                    locale: Locale.current,
                    whisperKitModel: self.whisperKitModelIdentifier
                )
            )
            return
        }

        error = message
        isProcessingSpeech = false
        if self.activeBackend == provider.backend {
            isListening = false
            activeProvider = nil
        }
        DiagnosticsLogger.voice.error("VoiceManager backend failure \(provider.backend.rawValue, privacy: .public): \(message, privacy: .public)")
    }

    private func resolvedBackend(for preference: SpeechRecognitionBackend) -> SpeechRecognitionBackend {
        switch preference {
        case .automatic:
            return whisperKitProvider.isSupported ? .whisperKit : .appleSpeech
        case .appleSpeech:
            return .appleSpeech
        case .whisperKit:
            return .whisperKit
        }
    }

    private func provider(for backend: SpeechRecognitionBackend) -> any SpeechRecognitionProviding {
        switch backend {
        case .automatic:
            return provider(for: resolvedBackend(for: .automatic))
        case .appleSpeech:
            return appleProvider
        case .whisperKit:
            return whisperKitProvider
        }
    }

    private func unsupportedMessage(for backend: SpeechRecognitionBackend) -> String {
        switch backend {
        case .automatic:
            return "No supported speech backend is available."
        case .appleSpeech:
            return "Apple Speech is unavailable on this device."
        case .whisperKit:
            return "WhisperKit is not linked in this build yet."
        }
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(self.preferredBackend.rawValue, forKey: Key.preferredBackend.rawValue)
        defaults.set(self.whisperKitModelIdentifier, forKey: Key.whisperKitModelIdentifier.rawValue)
    }
}
