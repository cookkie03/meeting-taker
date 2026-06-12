import Foundation
import AVFoundation

/// Utility for writing audio buffers to a file
public actor AudioFileWriter {

    private var audioFile: AVAudioFile?
    private let sampleRate: Double

    public init(sampleRate: Double = 16000.0) {
        self.sampleRate = sampleRate
    }

    /// Start writing to a file at the given URL
    public func startWriting(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        audioFile = try AVAudioFile(forWriting: url, settings: settings)
    }

    /// Write a buffer to the file
    public func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let file = audioFile else { return }

        // Convert float32 buffer to int16 if needed
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            let int16Buffer = try convertToInt16(buffer)
            try file.write(from: int16Buffer)
        } else {
            try file.write(from: buffer)
        }
    }

    /// Stop writing and close the file
    public func stopWriting() {
        audioFile = nil
    }

    // MARK: - Private

    private func convertToInt16(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "AudioFileWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        let frameLength = Int(buffer.frameLength)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: false)!
        guard let int16Buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            throw NSError(domain: "AudioFileWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create int16 buffer"])
        }
        int16Buffer.frameLength = AVAudioFrameCount(frameLength)

        let floatData = channelData[0]
        let int16Data = int16Buffer.int16ChannelData![0]

        for i in 0..<frameLength {
            let sample = max(-1.0, min(1.0, floatData[i]))
            int16Data[i] = Int16(sample * Float(Int16.max))
        }

        return int16Buffer
    }
}
