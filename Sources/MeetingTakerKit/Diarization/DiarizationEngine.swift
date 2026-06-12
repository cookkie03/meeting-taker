import Foundation
import SpeakerKit

/// Errors that can occur during speaker diarization
public enum DiarizationError: LocalizedError {
    case modelNotFound(String)
    case initializationFailed(String)
    case diarizationFailed(String)
    case invalidAudioFile(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Speaker model '\(name)' not found. Run setup to download models."
        case .initializationFailed(let reason):
            return "Failed to initialize SpeakerKit: \(reason)"
        case .diarizationFailed(let reason):
            return "Diarization failed: \(reason)"
        case .invalidAudioFile(let path):
            return "Invalid audio file: \(path)"
        }
    }
}

/// Speaker diarization result for a single segment
public struct DiarizationSegment: Codable, Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let speaker: String
    public let confidence: Double?

    public init(startTime: TimeInterval, endTime: TimeInterval, speaker: String, confidence: Double? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.confidence = confidence
    }
}

/// Speaker diarization engine powered by SpeakerKit
/// Identifies "who spoke when" in an audio file
public actor DiarizationEngine {

    // MARK: - Properties

    private var speakerKit: SpeakerKit?

    // MARK: - Initialization

    public init() {}

    /// Initialize the diarization engine
    public func initialize() async throws {
        speakerKit = try await SpeakerKit()
    }

    /// Check if the engine is initialized
    public var isInitialized: Bool {
        speakerKit != nil
    }

    // MARK: - Diarization

    /// Perform speaker diarization on an audio file
    /// - Parameters:
    ///   - audioPath: Path to the audio file
    ///   - maxSpeakers: Maximum number of speakers to detect (nil for auto)
    /// - Returns: Array of diarization segments with speaker labels
    public func diarize(
        audioPath: String,
        maxSpeakers: Int? = nil
    ) async throws -> [DiarizationSegment] {
        guard let sk = speakerKit else {
            try await initialize()
            guard let sk2 = speakerKit else {
                throw DiarizationError.initializationFailed("SpeakerKit not available")
            }
            return try await performDiarization(sk2, audioPath: audioPath, maxSpeakers: maxSpeakers)
        }

        return try await performDiarization(sk, audioPath: audioPath, maxSpeakers: maxSpeakers)
    }

    private func performDiarization(
        _ sk: SpeakerKit,
        audioPath: String,
        maxSpeakers: Int?
    ) async throws -> [DiarizationSegment] {
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw DiarizationError.invalidAudioFile(audioPath)
        }

        // Configure diarization options
        var options = DiarizationOptions()
        if let max = maxSpeakers {
            options.maxSpeakers = max
        }

        // Perform diarization
        let result = try await sk.diarize(audioPath: audioPath, options: options)

        // Convert to our model
        return result.segments.map { segment in
            DiarizationSegment(
                startTime: segment.start,
                endTime: segment.end,
                speaker: segment.speaker,
                confidence: segment.confidence
            )
        }
    }

    // MARK: - RTTM Export

    /// Export diarization results in RTTM format
    /// - Parameters:
    ///   - segments: Diarization segments
    ///   - fileId: Identifier for the audio file
    /// - Returns: RTTM formatted string
    public func exportRTTM(segments: [DiarizationSegment], fileId: String) -> String {
        var lines: [String] = []
        for segment in segments {
            let duration = segment.endTime - segment.startTime
            let line = "SPEAKER \(fileId) 1 \(String(format: "%.3f", segment.startTime)) \(String(format: "%.3f", duration)) <NA> <NA> \(segment.speaker) <NA> <NA>"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
