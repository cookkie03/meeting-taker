import Foundation
import AVFoundation
import ScreenCaptureKit

// MARK: - Audio Source

public enum AudioSource: String, CaseIterable, Sendable, Identifiable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    case both = "both"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .microphone:  return "Microphone"
        case .systemAudio: return "System Audio"
        case .both:        return "Mic + System"
        }
    }

    public var icon: String {
        switch self {
        case .microphone:  return "mic.fill"
        case .systemAudio: return "speaker.wave.3.fill"
        case .both:        return "waveform"
        }
    }
}

// MARK: - Errors

public enum AudioCaptureError: LocalizedError {
    case micPermissionDenied
    case screenRecordingDenied
    case setupFailed(String)
    case noDisplay

    public var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            return "Microphone access denied. Grant in System Settings > Privacy & Security > Microphone."
        case .screenRecordingDenied:
            return "Screen Recording access denied. Required for system audio. Grant in System Settings > Privacy & Security > Screen Recording, then restart the app."
        case .setupFailed(let r): return "Audio setup failed: \(r)"
        case .noDisplay: return "No display found for audio capture."
        }
    }
}

// MARK: - AudioCaptureManager

/// Captures microphone via AVAudioEngine and/or system audio via ScreenCaptureKit.
/// Provides 16kHz mono float32 PCM buffers for transcription.
public actor AudioCaptureManager: @unchecked Sendable {

    public static let shared = AudioCaptureManager()
    public static let targetSampleRate: Double = 16_000

    private var isCapturing = false
    private var micEngine: AVAudioEngine?
    private var systemStream: SCStream?
    private var systemAudioHandler: SystemAudioHandler?

    private init() {}

    public func startCapture(
        source: AudioSource,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) async throws {
        guard !isCapturing else { return }
        isCapturing = true

        switch source {
        case .microphone:
            try startMic(onBuffer: onBuffer)
        case .systemAudio:
            try await startSystemAudio(onBuffer: onBuffer)
        case .both:
            try startMic(onBuffer: onBuffer)
            try await startSystemAudio(onBuffer: onBuffer)
        }
    }

    public func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

        micEngine?.stop()
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine = nil

        Task {
            await systemAudioHandler?.stop()
            systemAudioHandler = nil
            try? await systemStream?.stopCapture()
            systemStream = nil
        }
    }

    // MARK: - Microphone

    private func startMic(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        AVAudioApplication.requestRecordPermission { g in granted = g; semaphore.signal() }
        semaphore.wait()
        guard granted else { throw AudioCaptureError.micPermissionDenied }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.targetSampleRate, channels: 1, interleaved: false)!

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in onBuffer(buffer) }
        try engine.start()
        micEngine = engine
    }

    // MARK: - System Audio via ScreenCaptureKit

    private func startSystemAudio(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw AudioCaptureError.screenRecordingDenied
        }

        guard let display = content.displays.first else { throw AudioCaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(Self.targetSampleRate)
        config.channelCount = 1
        config.width = 2
        config.height = 2

        let handler = SystemAudioHandler(onBuffer: onBuffer)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        systemStream = stream
        systemAudioHandler = handler
    }
}

// MARK: - SystemAudioHandler

private class SystemAudioHandler: NSObject, SCStreamOutput {
    private let onBuffer: (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let pcmBuffer = sampleBuffer.toPCMBuffer() else { return }
        onBuffer(pcmBuffer)
    }

    func stop() {}
}

// MARK: - CMSampleBuffer Extension

extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        var asbdCopy = asbd.pointee
        guard let avFormat = AVAudioFormat(streamDescription: &asbdCopy) else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self, bufferListSizeNeededOut: nil, bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for (i, buffer) in buffers.enumerated() {
            if let channelData = pcmBuffer.floatChannelData?[i], let srcData = buffer.mData {
                memcpy(channelData, srcData, Int(buffer.mDataByteSize))
            }
        }
        return pcmBuffer
    }
}
