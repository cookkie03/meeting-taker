import Foundation

/// Represents a single segment of transcribed speech
public struct TranscriptionSegment: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    public let language: String?
    public let speaker: String?
    public let confidence: Double?

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        language: String? = nil,
        speaker: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.language = language
        self.speaker = speaker
        self.confidence = confidence
    }

    /// Formatted time range string (e.g. "00:01:23 - 00:01:45")
    public var timeRange: String {
        "\(formatTime(startTime)) - \(formatTime(endTime))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// A complete transcription result
public struct TranscriptionResult: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let segments: [TranscriptionSegment]
    public let fullText: String
    public let duration: TimeInterval
    public let language: String?
    public let modelName: String
    public let fileName: String?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        segments: [TranscriptionSegment],
        fullText: String,
        duration: TimeInterval,
        language: String? = nil,
        modelName: String,
        fileName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.segments = segments
        self.fullText = fullText
        self.duration = duration
        self.language = language
        self.modelName = modelName
        self.fileName = fileName
    }

    /// Unique speakers found in the transcription
    public var speakers: [String] {
        Array(Set(segments.compactMap { $0.speaker })).sorted()
    }

    /// Number of unique speakers
    public var speakerCount: Int {
        speakers.count
    }
}
