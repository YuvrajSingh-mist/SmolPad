import Foundation
import UIKit
import Vision

struct OCRLine: Sendable {
    let text: String
    let confidence: Float
}

struct OCRTranscript: Sendable {
    let fullText: String
    let averageConfidence: Float
    let lines: [OCRLine]

    var isUseful: Bool {
        !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppleVisionOCRService {
    static func recognizeText(in image: UIImage) async throws -> OCRTranscript {
        guard let cgImage = image.cgImage else {
            return OCRTranscript(fullText: "", averageConfidence: 0, lines: [])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    return OCRLine(text: candidate.string, confidence: candidate.confidence)
                }

                let joined = lines.map(\.text).joined(separator: "\n")
                let averageConfidence: Float
                if lines.isEmpty {
                    averageConfidence = 0
                } else {
                    averageConfidence = lines.reduce(0) { $0 + $1.confidence } / Float(lines.count)
                }

                continuation.resume(
                    returning: OCRTranscript(
                        fullText: joined,
                        averageConfidence: averageConfidence,
                        lines: lines
                    )
                )
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
