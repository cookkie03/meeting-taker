import Foundation

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
        case .txt:  return "Plain Text"
        case .json: return "JSON"
        case .srt:  return "SubRip (SRT)"
        case .vtt:  return "WebVTT"
        case .rttm: return "RTTM (Diarization)"
        case .csv:  return "CSV"
        }
    }
}

/// Handles exporting MTTranscriptionResult to various file formats
public struct ExportEngine {

    public init() {}

    public func export(
        _ result: MTTranscriptionResult,
        to format: ExportFormat,
        at url: URL,
        includeSpeakerLabels: Bool = true
    ) throws {
        let content: String
        switch format {
        case .txt:  content = exportAsText(result, includeSpeakers: includeSpeakerLabels)
        case .json: content = try exportAsJSON(result)
        case .srt:  content = exportAsSRT(result, includeSpeakers: includeSpeakerLabels)
        case .vtt:  content = exportAsVTT(result, includeSpeakers: includeSpeakerLabels)
        case .rttm: content = exportAsRTTM(result)
        case .csv:  content = exportAsCSV(result)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportAsText(_ result: MTTranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []
        lines.append("MeetingTaker Transcription")
        lines.append("Date: \(ISO8601DateFormatter().string(from: result.date))")
        lines.append("Model: \(result.modelName)")
        if let lang = result.language { lines.append("Language: \(lang)") }
        lines.append("Duration: \(fmtDuration(result.duration))")
        lines.append("Speakers: \(result.speakerCount)")
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
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

    private func exportAsJSON(_ result: MTTranscriptionResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func exportAsSRT(_ result: MTTranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []
        for (index, segment) in result.segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(fmtSRT(segment.startTime)) --> \(fmtSRT(segment.endTime))")
            if includeSpeakers, let speaker = segment.speaker {
                lines.append("[\(speaker)] \(segment.text)")
            } else {
                lines.append(segment.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsVTT(_ result: MTTranscriptionResult, includeSpeakers: Bool) -> String {
        var lines: [String] = []
        lines.append("WEBVTT")
        lines.append("")
        for segment in result.segments {
            lines.append("\(fmtVTT(segment.startTime)) --> \(fmtVTT(segment.endTime))")
            if includeSpeakers, let speaker = segment.speaker {
                lines.append("<v \(speaker)>\(segment.text)")
            } else {
                lines.append(segment.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsRTTM(_ result: MTTranscriptionResult) -> String {
        var lines: [String] = []
        let fileId = result.fileName ?? "meeting"
        for segment in result.segments {
            guard let speaker = segment.speaker else { continue }
            let duration = segment.endTime - segment.startTime
            lines.append("SPEAKER \(fileId) 1 \(fmt3(segment.startTime)) \(fmt3(duration)) <NA> <NA> \(speaker) <NA> <NA>")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsCSV(_ result: MTTranscriptionResult) -> String {
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

    private func fmtDuration(_ d: TimeInterval) -> String {
        let h = Int(d) / 3600; let m = (Int(d) % 3600) / 60; let s = Int(d) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func fmtSRT(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60; let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private func fmtVTT(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60; let s = Int(t) % 60
        let ms = Int((t.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    private func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
}
