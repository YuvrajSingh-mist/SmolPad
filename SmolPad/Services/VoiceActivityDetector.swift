import AVFoundation
import Foundation

protocol VoiceActivityDetecting {
    var displayName: String { get }
    func reset()
    func shouldKeepAudio(from buffer: AVAudioPCMBuffer) -> Bool
}

enum VoiceActivityDetectorFactory {
    static func makeProductionDetector() -> VoiceActivityDetecting {
        #if canImport(SherpaOnnx)
        return SherpaOnnxVoiceActivityDetector()
        #else
        return EnergyVoiceActivityDetector()
        #endif
    }
}

final class EnergyVoiceActivityDetector: VoiceActivityDetecting {
    let displayName = "Energy VAD"

    private let threshold: Float
    private let hangoverFrames: Int
    private var remainingHangoverFrames = 0

    init(threshold: Float = 0.010, hangoverFrames: Int = 6) {
        self.threshold = threshold
        self.hangoverFrames = hangoverFrames
    }

    func reset() {
        remainingHangoverFrames = 0
    }

    func shouldKeepAudio(from buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return false }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        let rms = sqrt(samples.reduce(0) { partial, sample in
            partial + (sample * sample)
        } / Float(frameCount))

        if rms >= threshold {
            remainingHangoverFrames = hangoverFrames
            return true
        }

        if remainingHangoverFrames > 0 {
            remainingHangoverFrames -= 1
            return true
        }

        return false
    }
}

#if canImport(SherpaOnnx)
final class SherpaOnnxVoiceActivityDetector: VoiceActivityDetecting {
    let displayName = "sherpa-onnx VAD"

    func reset() {}

    func shouldKeepAudio(from buffer: AVAudioPCMBuffer) -> Bool {
        true
    }
}
#endif
