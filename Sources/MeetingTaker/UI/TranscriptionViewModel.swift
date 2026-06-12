import SwiftUI
import AVFoundation
import WhisperKit
import SpeakerKit

/// ViewModel managing the transcription workflow
@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var currentResult: TranscriptionResult?
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioSource: AudioSource = .microphone
    @Published var audioLevel: Float = 0.0

    private var appState: AppState?
    private var transcriptionEngine: TranscriptionEngine?
    private var diarizationEngine: DiarizationEngine?
    private var audioCaptureManager: AudioCaptureManager?
    private var audioFileWriter: AudioFileWriter?
    private var recordingURL: URL?
    private var recordingTimer: Timer?

    func setup(appState: AppState) {
        self.appState = appState
        self.transcriptionEngine = TranscriptionEngine(model: appState.selectedModel)
        self.diarizationEngine = DiarizationEngine()
        self.audioCaptureManager = AudioCaptureManager.shared
        self.audioFileWriter = AudioFileWriter()
    }

    // MARK: - Recording

    func startRecording() {
        guard let appState else { return }

        Task {
            do {
                // Initialize engine if needed
                if !(transcriptionEngine?.isInitialized ?? true) {
                    try await transcriptionEngine?.initialize(model: appState.selectedModel)
                }

                // Create temp file for recording
                let tempDir = FileManager.default.temporaryDirectory
                recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

                if let url = recordingURL {
                    try await audioFileWriter?.startWriting(to: url)
                }

                // Start capture from selected source
                try await audioCaptureManager?.startCapture(source: audioSource) { [weak self] buffer in
                    Task { @MainActor in
                        try? await self?.audioFileWriter?.write(buffer)
                        // Update audio level for UI
                        self?.updateAudioLevel(buffer)
                    }
                }

                isRecording = true
                appState.isRecording = true
                recordingTime = 0

                // Start timer
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.recordingTime += 1
                }

            } catch {
                appState.showError(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        guard let appState else { return }

        Task {
            await audioCaptureManager?.stopCapture()
            await audioFileWriter?.stopWriting()

            recordingTimer?.invalidate()
            recordingTimer = nil
            isRecording = false
            appState.isRecording = false
            audioLevel = 0

            // Transcribe the recorded file
            if let url = recordingURL {
                await transcribeFile(at: url.path)
            }
        }
    }

    // MARK: - File Transcription

    func openFile() {
        guard let appState else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .init(filenameExtension: "m4a")!, .init(filenameExtension: "flac")!]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await transcribeFile(at: url.path)
            }
        }
    }

    private func transcribeFile(at path: String) async {
        guard let appState else { return }

        isTranscribing = true
        appState.isTranscribing = true

        do {
            // Initialize engine
            if !(transcriptionEngine?.isInitialized ?? true) {
                try await transcriptionEngine?.initialize(model: appState.selectedModel)
            }

            // Transcribe
            let result = try await transcriptionEngine?.transcribeFile(
                at: path,
                language: appState.selectedLanguage == "auto" ? nil : appState.selectedLanguage
            )

            guard var result else {
                throw TranscriptionError.transcriptionFailed("No result returned")
            }

            // Diarize if enabled
            if appState.enableDiarization {
                let diarizationSegments = try await diarizationEngine?.diarize(
                    audioPath: path,
                    maxSpeakers: appState.maxSpeakers == 0 ? nil : appState.maxSpeakers
                )

                if let diarization = diarizationSegments {
                    result = mergeDiarization(result, diarization: diarization)
                }
            }

            currentResult = result
            appState.transcriptionHistory.insert(result, at: 0)

        } catch {
            appState.showError(error.localizedDescription)
        }

        isTranscribing = false
        appState.isTranscribing = false
    }

    // MARK: - Audio Level

    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        let avg = sum / Float(frameLength)
        audioLevel = min(1.0, avg * 10) // Normalize to 0-1
    }

    // MARK: - Diarization Merge

    private func mergeDiarization(_ result: TranscriptionResult, diarization: [DiarizationSegment]) -> TranscriptionResult {
        let updatedSegments = result.segments.map { segment -> TranscriptionSegment in
            let matchingSpeaker = diarization.first { diarSegment in
                segment.startTime < diarSegment.endTime && segment.endTime > diarSegment.startTime
            }

            if let speaker = matchingSpeaker {
                return TranscriptionSegment(
                    id: segment.id,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: segment.text,
                    language: segment.language,
                    speaker: speaker.speaker,
                    confidence: segment.confidence
                )
            }
            return segment
        }

        return TranscriptionResult(
            id: result.id,
            date: result.date,
            segments: updatedSegments,
            fullText: result.fullText,
            duration: result.duration,
            language: result.language,
            modelName: result.modelName,
            fileName: result.fileName
        )
    }
}
