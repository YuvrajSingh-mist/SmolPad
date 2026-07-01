import Foundation
import Speech

@MainActor
final class AppleSpeechFileFallbackTranscriber {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    func transcribeAudioFile(at url: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw NSError(domain: "SmolPad.SpeechFallback", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech fallback is not authorized."
            ])
        }

        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SmolPad.SpeechFallback", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Apple Speech fallback is unavailable."
            ])
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false

            let task = recognizer.recognitionTask(with: request) { result, error in
                if finished { return }

                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }

            _ = task
        }
    }
}
