import Foundation
import UIKit

enum OnDeviceInferenceError: LocalizedError {
    case runtimeUnavailable
    case unsupportedInferencePath

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            "The Mirai on-device runtime currently requires a newer iOS deployment target than this app uses, so On Device mode is unavailable in this build."
        case .unsupportedInferencePath:
            "The on-device runtime currently supports Vision OCR + Text mode only."
        }
    }
}

enum OnDeviceTextClient {
    static let isRuntimeAvailable = false

    static func send(
        image: UIImage?,
        query: String,
        config: AIConfig,
        history: [ChatMessage],
        summary: String
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        _ = image
        _ = query
        _ = config
        _ = history
        _ = summary

        guard config.inferencePath == .appleVisionOCRPlusText else {
            throw OnDeviceInferenceError.unsupportedInferencePath
        }

        throw OnDeviceInferenceError.runtimeUnavailable
    }
}
