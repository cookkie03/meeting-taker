import Foundation

/// Our own transcription segment type — independent from WhisperKit's internal types.
/// We convert from WhisperKit's result to this for use in the UI.
public struct MTTranscriptionSegment: Identifiable, Codable, Sendable, Hashable {
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

    public var timeRange: String {
        "\(fmt(startTime)) - \(fmt(endTime))"
    }

    private func fmt(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = (Int(time) % 3600) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

/// Our own transcription result type.
public struct MTTranscriptionResult: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let date: Date
    public let segments: [MTTranscriptionSegment]
    public let fullText: String
    public let duration: TimeInterval
    public let language: String?
    public let modelName: String
    public let fileName: String?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        segments: [MTTranscriptionSegment],
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

    public var speakers: [String] {
        Array(Set(segments.compactMap { $0.speaker })).sorted()
    }

    public var speakerCount: Int { speakers.count }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: MTTranscriptionResult, rhs: MTTranscriptionResult) -> Bool { lhs.id == rhs.id }
}

public struct DiarizationSegment: Codable, Sendable, Hashable {
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
