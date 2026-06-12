import Foundation
import AVFoundation
import Combine

/// Errors that can occur during audio recording
public enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case setupFailed(String)
    case recordingFailed(String)
    case noInputDevice

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Please grant permission in System Settings > Privacy & Security > Microphone."
        case .setupFailed(let reason):
            return "Audio setup failed: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .noInputDevice:
            return "No audio input device found."
        }
    }
}

/// Real-time audio recorder using AVAudioEngine
/// Captures microphone input and provides buffers for streaming transcription
public actor AudioRecorder {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isRecording = false

    /// Sample rate for audio capture (Whisper expects 16kHz)
    public static let sampleRate: Double = 16000.0

    /// Shared singleton instance
    public static let shared = AudioRecorder()

    // MARK: - Public Interface

    /// Check if microphone permission has been granted
    public func checkPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording from the microphone
    /// - Parameter onBuffer: Callback invoked with each audio buffer for real-time processing
    public func startRecording(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        guard !isRecording else { return }

        // Check permission
        let hasPermission = await checkPermission()
        guard hasPermission else {
            throw AudioRecorderError.permissionDenied
        }

        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Setup engine
        let engine = AVAudioEngine()
        let input = engine.inputNode

        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )

        guard let format = recordingFormat else {
            throw AudioRecorderError.setupFailed("Could not create audio format")
        }

        // Install tap on input node
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.inputNode = input
        self.isRecording = true
    }

    /// Stop recording
    public func stopRecording() {
        guard isRecording else { return }

        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        isRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Whether the recorder is currently capturing audio
    public var recording: Bool {
        get { isRecording }
    }

    deinit {
        if isRecording {
            audioEngine?.stop()
            inputNode?.removeTap(onBus: 0)
        }
    }
}
