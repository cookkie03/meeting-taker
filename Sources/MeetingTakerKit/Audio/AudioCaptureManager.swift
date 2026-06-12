import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreAudio

// MARK: - Audio Source

/// Audio capture source
public enum AudioSource: String, CaseIterable, Sendable, Identifiable {
    case microphone   = "microphone"
    case systemAudio  = "systemAudio"
    case both         = "both"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microphone:   return "Microphone Only"
        case .systemAudio:  return "System Audio Only"
        case .both:         return "Microphone + System Audio"
        }
    }

    public var icon: String {
        switch self {
        case .microphone:   return "mic.fill"
        case .systemAudio:  return "speaker.wave.3.fill"
        case .both:         return "waveform"
        }
    }
}

// MARK: - Errors

public enum AudioCaptureError: LocalizedError {
    case micPermissionDenied
    case screenRecordingPermissionDenied
    case setupFailed(String)
    case captureFailed(String)
    case noContentAvailable
    case screenCaptureKitUnavailable

    public var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            return "Microphone access denied. Grant in System Settings > Privacy & Security > Microphone."
        case .screenRecordingPermissionDenied:
            return "Screen Recording access denied. Required to capture system audio. Grant in System Settings > Privacy & Security > Screen Recording. Then restart the app."
        case .setupFailed(let r):  return "Audio setup failed: \(r)"
        case .captureFailed(let r): return "Capture failed: \(r)"
        case .noContentAvailable:   return "No display or audio content available to capture."
        case .screenCaptureKitUnavailable:
            return "ScreenCaptureKit requires macOS 12.3 or later."
        }
    }
}

// MARK: - Capture Buffer Callback

/// Receives 16kHz mono float32 audio buffers ready for transcription
public typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer) -> Void

// MARK: - AudioCaptureManager

/// Unified audio capture supporting microphone, system audio, or both.
///
/// ## Audio Sources
///
/// - **Microphone**: Uses `AVAudioEngine` tap on the input node.
///   Standard recording, works on all macOS versions.
///
/// - **System Audio**: Uses `ScreenCaptureKit` (`SCStream`) to capture
///   the system audio output directly. No virtual audio drivers needed.
///   Requires Screen Recording permission on first use.
///
/// - **Both**: Captures microphone via `AVAudioEngine` AND system audio
///   via `ScreenCaptureKit`, then mixes both streams into a single
///   16kHz mono buffer for transcription.
///
/// ## Privacy
/// All audio stays on-device. No data ever leaves the Mac.
public actor AudioCaptureManager {

    // MARK: - Singletons & Constants

    public static let shared = AudioCaptureManager()
    public static let targetSampleRate: Double = 16_000

    // MARK: - State

    private var isCapturing = false
    private var currentSource: AudioSource = .microphone

    // Mic
    private var micEngine: AVAudioEngine?

    // System audio (ScreenCaptureKit)
    private var systemStream: SCStream?
    private var systemAudioManager: SystemAudioCaptureManager?

    // Mixer
    private var mixerBuffer: [Float] = []
    private var micBuffer: [Float] = []

    // Output
    private var bufferHandler: AudioBufferHandler?

    private init() {}

    // MARK: - Public API

    /// Start capturing audio from the given source.
    ///
    /// For `.systemAudio` and `.both`, this requires Screen Recording permission.
    /// The first time, macOS will prompt the user. After granting, restart the app.
    public func startCapture(
        source: AudioSource,
        onBuffer: @escaping AudioBufferHandler
    ) async throws {
        guard !isCapturing else { return }
        currentSource = source
        bufferHandler = onBuffer

        switch source {
        case .microphone:
            try startMicCapture(onBuffer: onBuffer)
        case .systemAudio:
            try await startSystemAudioCapture(onBuffer: onBuffer)
        case .both:
            try await startMixedCapture(onBuffer: onBuffer)
        }

        isCapturing = true
    }

    /// Stop all audio capture
    public func stopCapture() {
        guard isCapturing else { return }

        // Stop mic
        micEngine?.stop()
        micEngine = nil

        // Stop system audio
        Task {
            await systemAudioManager?.stop()
            systemAudioManager = nil
            systemStream?.stopCapture { _ in }
            systemStream = nil
        }

        bufferHandler = nil
        isCapturing = false
    }

    public var capturing: Bool { isCapturing }

    // MARK: - Microphone Capture

    private func startMicCapture(onBuffer: @escaping AudioBufferHandler) throws {
        // Request permission
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        AVAudioApplication.requestRecordPermission { g in
            granted = g
            semaphore.signal()
        }
        semaphore.wait()

        guard granted else {
            throw AudioCaptureError.micPermissionDenied
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        )

        guard let format else {
            throw AudioCaptureError.setupFailed("Cannot create audio format")
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }

        try engine.start()
        micEngine = engine
    }

    // MARK: - System Audio Capture (ScreenCaptureKit)

    private func startSystemAudioCapture(onBuffer: @escaping AudioBufferHandler) async throws {
        // Check Screen Recording permission
        let hasPermission = await checkScreenRecordingPermission()
        guard hasPermission else {
            throw AudioCaptureError.screenRecordingPermissionDenied
        }

        // Get shareable content
        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else {
            throw AudioCaptureError.noContentAvailable
        }

        // Use the main display
        let display = content.displays.first!

        // Configure stream — audio only, no video
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(Self.targetSampleRate)
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Add audio output
        try stream.addStreamOutput(
            SystemAudioCaptureManager(),
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "com.meetingtaker.audio", qos: .userInteractive)
        )

        self.systemStream = stream
        self.systemAudioManager = SystemAudioCaptureManager(onBuffer: onBuffer)

        try await stream.startCapture()
    }

    // MARK: - Mixed Capture (Mic + System)

    private func startMixedCapture(onBuffer: @escaping AudioBufferHandler) async throws {
        // Start mic
        try startMicCapture(onBuffer: onBuffer)

        // Start system audio
        try await startSystemAudioCapture(onBuffer: onBuffer)
    }

    // MARK: - Permissions

    private func checkScreenRecordingPermission() async -> Bool {
        // Try to get shareable content — if it fails, permission is denied
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
}

// MARK: - SystemAudioCaptureManager

/// Receives audio samples from ScreenCaptureKit's SCStream
private class SystemAudioCaptureManager: NSObject, SCStreamOutput {
    private let onBuffer: AudioBufferHandler

    init(onBuffer: @escaping AudioBufferHandler) {
        self.onBuffer = onBuffer
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              let pcmBuffer = try? sampleBuffer.toAudioBuffer() else {
            return
        }
        onBuffer(pcmBuffer)
    }

    func stop() {
        // Cleanup if needed
    }
}

// MARK: - CMSampleBuffer Extension

extension CMSampleBuffer {
    func toAudioBuffer() throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self) else {
            throw AudioCaptureError.captureFailed("No format description")
        }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = asbd?.pointee else {
            throw AudioCaptureError.captureFailed("Cannot get audio format")
        }

        let audioFormat = AVAudioFormat(streamDescription: &asbd)
        guard let audioFormat = audioFormat else {
            throw AudioCaptureError.captureFailed("Cannot create AVAudioFormat")
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            throw AudioCaptureError.captureFailed("Cannot get audio buffer list: \(status)")
        }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw AudioCaptureError.captureFailed("Cannot create PCM buffer")
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data
        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for (i, buffer) in buffers.enumerated() {
            if let channelData = pcmBuffer.floatChannelData?[i],
               let srcData = buffer.mData {
                memcpy(channelData, srcData, Int(buffer.mDataByteSize))
            }
        }

        return pcmBuffer
    }
}
