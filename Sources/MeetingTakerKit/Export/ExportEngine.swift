import Foundation

/// Export formats supported by MeetingTaker
public enum ExportFormat: String, CaseIterable, Sendable {
    case txt = "txt"
    case json = "json"
    case srt = "srt"
    case vtt = "vtt"
    case rttm = "rttm"
    case csv = "csv"

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .txt: return "Plain Text"
        case .json: return "JSON"
        case .srt: return "SubRip (SRT)"
        case .vtt: return "WebVTT"
        case .rttm: return "RTTM (Diarization)"
        case .csv: return "CSV"
        }
    }
}

/// Handles exporting transcription results to various file formats
public struct ExportEngine {

    public init() {}

    /// Export a transcription result to a file
    /// - Parameters:
    ///   - result: The transcription result to export
    ///   - format: The export format
    ///   - url: The destination file URL
    ///   - includeSpeakerLabels: Whether to include speaker labels in the output
    public func export(
        _ result: TranscriptionResult,
        to format: ExportFormat,
        at url: URL,
        includeSpeakerLabels: Bool = true
    ) throws {
        let content: String
        switch format {
        case .txt:
            content = exportAsText(result, includeSpeakers: includeSpeakerLabels)
        case .json:
            content = try exportAsJSON(result)
        case .srt:
            content = exportAsSRT(result, includeSpeakers: includeSpeakerLabels)
        case .vtt:
            content = exportAsVTT(result, includeSpeakers: includeSpeakerLabels)
        case .rttm:
            content = exportAsRTTM(result)
        case .csv:
            content = exportAsCSV(result)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Format Exporters

    private func exportAsText(_ result: TranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []

        // Header
        lines.append("MeetingTaker Transcription")
        lines.append("Date: \(ISO8601DateFormatter().string(from: result.date))")
        lines.append("Model: \(result.modelName)")
        if let lang = result.language {
            lines.append("Language: \(lang)")
        }
        lines.append("Duration: \(formatDuration(result.duration))")
        lines.append("Speakers: \(result.speakerCount)")
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        // Segments
        for segment in result.segments {
            if includeSpeakers, let speaker = segment.speaker {
                lines.append("[\(segment.timeRange)] \(speaker): \(segment.text)")
            } else {
                lines.append("[\(segment.timeRange)] \(segment.text)")
            }
        }

        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        lines.append("Full Text:")
        lines.append(result.fullText)

        return lines.joined(separator: "\n")
    }

    private func exportAsJSON(_ result: TranscriptionResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func exportAsSRT(_ result: TranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []
        for (index, segment) in result.segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))")
            if includeSpeakers, let speaker = segment.speaker {
                lines.append("[\(speaker)] \(segment.text)")
            } else {
                lines.append(segment.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsVTT(_ result: TranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []
        lines.append("WEBVTT")
        lines.append("")
        for segment in result.segments {
            lines.append("\(formatVTTTime(segment.startTime)) --> \(formatVTTTime(segment.endTime))")
            if includeSpeakers, let speaker = segment.speaker {
                lines.append("<v \(speaker)>\(segment.text)")
            } else {
                lines.append(segment.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsRTTM(_ result: TranscriptionResult) -> String {
        var lines: [String] = []
        let fileId = result.fileName ?? "meeting"
        for segment in result.segments {
            guard let speaker = segment.speaker else { continue }
            let duration = segment.endTime - segment.startTime
            lines.append("SPEAKER \(fileId) 1 \(fmt(segment.startTime)) \(fmt(duration)) <NA> <NA> \(speaker) <NA> <NA>")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsCSV(_ result: TranscriptionResult) -> String {
        var lines: [String] = []
        lines.append("Start,End,Speaker,Text,Language")
        for segment in result.segments {
            let speaker = segment.speaker ?? ""
            let text = segment.text.replacingOccurrences(of: "\"", with: "\"\"")
            let lang = segment.language ?? ""
            lines.append("\(segment.startTime),\(segment.endTime),\"\(speaker)\",\"\(text)\",\"\(lang)\"")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formatSRTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private func formatVTTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
