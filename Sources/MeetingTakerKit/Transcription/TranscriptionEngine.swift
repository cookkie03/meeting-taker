import Foundation
import AVFoundation
import WhisperKit

public enum TranscriptionError: LocalizedError {
    case initializationFailed(String)
    case transcriptionFailed(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let r): return "WhisperKit init failed: \(r)"
        case .transcriptionFailed(let r):  return "Transcription failed: \(r)"
        case .fileNotFound(let p):         return "File not found: \(p)"
        }
    }
}

/// Transcription engine powered by WhisperKit.
/// Converts WhisperKit results to our MTTranscriptionResult type.
public actor TranscriptionEngine {

    public static let defaultModel = "large-v3-v20240930_626MB"

    public static let modelTiers: [(name: String, description: String, size: String)] = [
        ("tiny",                          "Fastest, lowest accuracy", "~75MB"),
        ("base",                          "Good for debugging",      "~140MB"),
        ("small",                         "Balanced speed/accuracy", "~250MB"),
        ("large-v3-v20240930_626MB",      "Recommended: best accuracy", "~626MB"),
    ]

    private var whisperKit: WhisperKit?
    private var currentModel: String

    public init(model: String = TranscriptionEngine.defaultModel) {
        self.currentModel = model
    }

    public func initialize(model: String? = nil) async throws {
        if let model = model { currentModel = model }
        let config = WhisperKitConfig(model: currentModel)
        config.download = true
        config.load = true
        whisperKit = try await WhisperKit(config)
    }

    public var isInitialized: Bool { whisperKit != nil }
    public var modelName: String { currentModel }

    /// Transcribe an audio file. Returns MTTranscriptionResult.
    public func transcribeFile(
        at audioPath: String,
        language: String? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MTTranscriptionResult {

        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.fileNotFound(audioPath)
        }

        if whisperKit == nil { try await initialize() }
        guard let wk = whisperKit else {
            throw TranscriptionError.initializationFailed("WhisperKit not available")
        }

        var options = DecodingOptions()
        if let language = language, language != "auto" {
            options.language = language
        }

        // Transcribe with WhisperKit
        let wkResult: TranscriptionResult?
        if let cb = progressCallback {
            wkResult = try await wk.transcribe(audioPath: audioPath, decodeOptions: options) { progress in
                cb(progress.progress)
                return true
            }
        } else {
            wkResult = try await wk.transcribe(audioPath: audioPath, decodeOptions: options)
        }

        guard let wkResult = wkResult else {
            throw TranscriptionError.transcriptionFailed("No result returned")
        }

        // Convert WhisperKit types to our types
        let segments = wkResult.segments.map { seg in
            MTTranscriptionSegment(
                startTime: TimeInterval(seg.start),
                endTime: TimeInterval(seg.end),
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: wkResult.language,
                confidence: seg.avgLogprob
            )
        }

        let fullText = segments.map(\.text).joined(separator: " ")
        let duration = (try? AVURLAsset(url: URL(fileURLWithPath: audioPath)).load(.duration)).map(CMTimeGetSeconds) ?? 0

        return MTTranscriptionResult(
            segments: segments,
            fullText: fullText,
            duration: duration,
            language: wkResult.language,
            modelName: currentModel,
            fileName: URL(fileURLWithPath: audioPath).lastPathComponent
        )
    }
}
