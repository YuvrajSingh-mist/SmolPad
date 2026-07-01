import Foundation

enum SpeechRecognitionBackend: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case appleSpeech = "Apple Speech"
    case whisperKit = "WhisperKit"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .automatic:
            "Prefers WhisperKit when available, otherwise falls back to Apple Speech."
        case .appleSpeech:
            "Built-in Apple speech recognition backend."
        case .whisperKit:
            "On-device open-source transcription path recommended for production dictation."
        }
    }
}

struct SpeechRecognitionSessionConfiguration {
    let locale: Locale
    let whisperKitModel: String
}

@MainActor
protocol SpeechRecognitionProviderDelegate: AnyObject {
    func speechProvider(_ provider: SpeechRecognitionProviding, didChangeListeningState isListening: Bool)
    func speechProvider(_ provider: SpeechRecognitionProviding, didUpdateTranscript transcript: String, isFinal: Bool)
    func speechProvider(_ provider: SpeechRecognitionProviding, didFailWithMessage message: String)
}

@MainActor
protocol SpeechRecognitionProviding: AnyObject {
    var backend: SpeechRecognitionBackend { get }
    var displayName: String { get }
    var isSupported: Bool { get }
    var delegate: SpeechRecognitionProviderDelegate? { get set }

    func requestPermission()
    func start(configuration: SpeechRecognitionSessionConfiguration)
    func stop() -> String
    func stopAndDiscardTranscript()
}
