import Foundation
import AVFoundation
import SpeakerKit

public enum DiarizationError: LocalizedError {
    case initializationFailed(String)
    case diarizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let r): return "SpeakerKit init failed: \(r)"
        case .diarizationFailed(let r):   return "Diarization failed: \(r)"
        }
    }
}

/// Speaker diarization engine powered by SpeakerKit (Pyannote).
/// Identifies "who spoke when" from an audio file.
public actor DiarizationEngine {

    private var speakerKit: SpeakerKit?

    public init() {}

    public func initialize() async throws {
        let config = PyannoteConfig()
        config.download = true
        config.load = true
        speakerKit = try await SpeakerKit(config)
    }

    public var isInitialized: Bool { speakerKit != nil }

    /// Diarize an audio file. Returns speaker segments with timings.
    public func diarize(
        audioPath: String,
        maxSpeakers: Int? = nil
    ) async throws -> [DiarizationSegment] {

        if speakerKit == nil { try await initialize() }
        guard let sk = speakerKit else {
            throw DiarizationError.initializationFailed("SpeakerKit not available")
        }

        // Load audio file into float array at 16kHz mono
        let audioArray = try loadAudioFile(path: audioPath)

        // Diarize — SpeakerKit.diarize takes audioArray: [Float], options can be nil
        let result = try await sk.diarize(audioArray: audioArray, options: nil)

        // Convert SpeakerSegment to our DiarizationSegment
        return result.segments.map { segment in
            DiarizationSegment(
                startTime: TimeInterval(segment.startTime),
                endTime: TimeInterval(segment.endTime),
                speaker: segment.speaker.speakerId.map { "Speaker \($0)" } ?? "unknown",
                confidence: nil
            )
        }
    }

    /// Export diarization results in RTTM format
    public func exportRTTM(segments: [DiarizationSegment], fileId: String) -> String {
        segments.map { s in
            let duration = s.endTime - s.startTime
            return "SPEAKER \(fileId) 1 \(fmt(s.startTime)) \(fmt(duration)) <NA> <NA> \(s.speaker) <NA> <NA>"
        }.joined(separator: "\n")
    }

    // MARK: - Audio Loading

    private func loadAudioFile(path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: file.processingFormat.channelCount, interleaved: false)!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw DiarizationError.diarizationFailed("Cannot create audio buffer")
        }

        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizationError.diarizationFailed("No audio data")
        }

        let frames = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frames)
        for i in 0..<frames { samples[i] = channelData[i] }

        // Resample to 16kHz if needed
        if file.processingFormat.sampleRate != 16000 {
            samples = resample(samples, from: file.processingFormat.sampleRate, to: 16000)
        }

        // If stereo, we already only took channel 0. If more than 1 channel in the format,
        // we should mix down — but AVAudioFile typically gives us interleaved or mono.
        // For simplicity, we take the first channel.

        return samples
    }

    private func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        let ratio = targetRate / sourceRate
        let newLength = Int(Double(samples.count) * ratio)
        guard newLength > 0 else { return samples }
        var result = [Float](repeating: 0, count: newLength)
        for i in 0..<newLength {
            let srcIndex = Double(i) / ratio
            let index = Int(srcIndex)
            if index < samples.count {
                result[i] = samples[index]
            }
        }
        return result
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
