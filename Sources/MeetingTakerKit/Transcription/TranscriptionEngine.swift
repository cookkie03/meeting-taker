import Foundation
import WhisperKit
import AVFoundation

/// Errors that can occur during transcription
public enum TranscriptionError: LocalizedError {
    case modelNotFound(String)
    case initializationFailed(String)
    case transcriptionFailed(String)
    case invalidAudioFile(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found. Run setup to download models."
        case .initializationFailed(let reason):
            return "Failed to initialize WhisperKit: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .invalidAudioFile(let path):
            return "Invalid audio file: \(path)"
        }
    }
}

/// Transcription engine powered by WhisperKit
/// Handles both file-based and real-time streaming transcription
public actor TranscriptionEngine {

    // MARK: - Properties

    private var whisperKit: WhisperKit?
    private var currentModel: String

    /// Default model to use (large-v3 turbo compressed for best accuracy/speed balance)
    public static let defaultModel = "large-v3-v20240930_626MB"

    /// Available model tiers
    public static let modelTiers: [(name: String, description: String, size: String)] = [
        ("tiny", "Fastest, lowest accuracy", "~75MB"),
        ("base", "Good for debugging", "~140MB"),
        ("small", "Balanced speed/accuracy", "~250MB"),
        ("large-v3-v20240930_626MB", "Recommended: best accuracy", "~626MB"),
    ]

    // MARK: - Initialization

    public init(model: String = TranscriptionEngine.defaultModel) {
        self.currentModel = model
    }

    // MARK: - Model Management

    /// Initialize (or re-initialize) the transcription engine with a specific model
    public func initialize(model: String? = nil) async throws {
        if let model = model {
            currentModel = model
        }

        let config = WhisperKitConfig(model: currentModel)
        whisperKit = try await WhisperKit(config)
    }

    /// Check if the engine is initialized
    public var isInitialized: Bool {
        whisperKit != nil
    }

    /// Get the name of the currently loaded model
    public var modelName: String {
        currentModel
    }

    // MARK: - File Transcription

    /// Transcribe an audio file
    /// - Parameters:
    ///   - audioPath: Path to the audio file (wav, mp3, m4a, flac)
    ///   - language: Optional language code (e.g. "en", "it", "auto")
    ///   - progressCallback: Called with progress updates (0.0 to 1.0)
    /// - Returns: TranscriptionResult with segments and metadata
    public func transcribeFile(
        at audioPath: String,
        language: String? = nil,
        progressCallback: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        guard let wk = whisperKit else {
            try await initialize()
            guard let wk2 = whisperKit else {
                throw TranscriptionError.initializationFailed("WhisperKit not available")
            }
            return try await performTranscription(wk2, audioPath: audioPath, language: language, progressCallback: progressCallback)
        }

        return try await performTranscription(wk, audioPath: audioPath, language: language, progressCallback: progressCallback)
    }

    private func performTranscription(
        _ wk: WhisperKit,
        audioPath: String,
        language: String?,
        progressCallback: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptionResult {
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.invalidAudioFile(audioPath)
        }

        // Configure transcription options
        var options = DecodingOptions()
        if let language = language, language != "auto" {
            options.language = language
        }

        // Perform transcription
        let results = try await wk.transcribe(
            audioPath: audioPath,
            decodeOptions: options,
            callback: { progress in
                Task { @MainActor in
                    progressCallback?(progress.progress)
                }
                return true
            }
        )

        // Convert results
        guard let result = results.first else {
            throw TranscriptionError.transcriptionFailed("No transcription results returned")
        }

        let segments = result.segments.map { segment in
            TranscriptionSegment(
                startTime: segment.start,
                endTime: segment.end,
                text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                language: result.language,
                confidence: segment.avgLogProb
            )
        }

        let fullText = segments.map(\.text).joined(separator: " " )

        // Get audio duration
        let asset = AVURLAsset(url: url)
        try await asset.load(.duration)
        let duration = CMTimeGetSeconds(asset.duration)

        return TranscriptionResult(
            segments: segments,
            fullText: fullText,
            duration: duration,
            language: result.language,
            modelName: currentModel,
            fileName: url.lastPathComponent
        )
    }

    // MARK: - Streaming Transcription

    /// Start a streaming transcription session from microphone input
    /// - Parameters:
    ///   - language: Optional language code
    ///   - onSegment: Called with each new transcription segment
    /// - Returns: A handle to control the streaming session
    public func startStreaming(
        language: String? = nil,
        onSegment: @escaping @Sendable (TranscriptionSegment) -> Void
    ) async throws -> StreamingSession {
        guard let wk = whisperKit else {
            try await initialize()
        }

        guard let wk = whisperKit else {
            throw TranscriptionError.initializationFailed("WhisperKit not available after init")
        }

        let session = StreamingSession(engine: self, whisperKit: wk, language: language, onSegment: onSegment)
        return session
    }
}

// MARK: - Streaming Session

/// Manages a real-time streaming transcription session
public actor StreamingSession {
    private let engine: TranscriptionEngine
    private let whisperKit: WhisperKit
    private let language: String?
    private let onSegment: @Sendable (TranscriptionSegment) -> Void
    private var isActive = false
    private var buffer: [Float] = []

    init(engine: TranscriptionEngine, whisperKit: WhisperKit, language: String?, onSegment: @escaping @Sendable (TranscriptionSegment) -> Void) {
        self.engine = engine
        self.whisperKit = whisperKit
        self.language = language
        self.onSegment = onSegment
    }

    /// Feed audio data into the streaming session
    public func feedAudio(_ data: [Float]) {
        buffer.append(contentsOf: data)
        // Process when we have enough data (e.g. 1 second = 16000 samples)
        if buffer.count >= 16000 {
            let chunk = Array(buffer.prefix(16000))
            buffer.removeFirst(16000)
            processChunk(chunk)
        }
    }

    /// Stop the streaming session
    public func stop() {
        isActive = false
        // Process remaining buffer
        if !buffer.isEmpty {
            processChunk(buffer)
            buffer.removeAll()
        }
    }

    public var active: Bool { isActive }

    private func processChunk(_ samples: [Float]) {
        // WhisperKit streaming would go here
        // For now, this is a placeholder for the streaming API
        // In production, this would use WhisperKit's streaming interface
    }
}
