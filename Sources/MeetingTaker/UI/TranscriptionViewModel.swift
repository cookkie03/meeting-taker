import SwiftUI
import AVFoundation
import WhisperKit
import SpeakerKit

/// Call detection state for UI
public enum CallDetectionState: Sendable {
    case idle
    case warming
    case recording
    case cooling
}

@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var currentResult: TranscriptionResult?
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioSource: AudioSource = .microphone
    @Published var audioLevel: Float = 0.0
    @Published var autoRecord = false {
        didSet {
            if autoRecord { startWatchingForCalls() }
            else { stopWatchingForCalls() }
        }
    }
    @Published var isWatchingForCalls = false
    @Published var callDetectionState: CallDetectionState = .idle
    @Published var detectedCall: DetectedCall?

    private var appState: AppState?
    private var transcriptionEngine: TranscriptionEngine?
    private var diarizationEngine: DiarizationEngine?
    private var audioCaptureManager: AudioCaptureManager?
    private var audioFileWriter: AudioFileWriter?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var callWatcher: CallWatcher?

    func setup(appState: AppState) {
        self.appState = appState
        self.transcriptionEngine = TranscriptionEngine(model: appState.selectedModel)
        self.diarizationEngine = DiarizationEngine()
        self.audioCaptureManager = AudioCaptureManager.shared
        self.audioFileWriter = AudioFileWriter()
    }

    // MARK: - Call Detection

    private func startWatchingForCalls() {
        guard callWatcher == nil else { return }

        let config = CallWatcher.Configuration(
            pollInterval: 2.0,
            warmupDuration: 5.0,
            graceDuration: 5.0,
            minimumRecordingDuration: 30.0,
            autoStartRecording: true,
            autoStopRecording: true
        )

        let watcher = CallWatcher(config: config)
        callWatcher = watcher
        isWatchingForCalls = true
        callDetectionState = .idle

        Task {
            await watcher.startWatching(
                onCallDetected: { [weak self] call in
                    Task { @MainActor in
                        self?.handleCallDetected(call)
                    }
                },
                onCallEnded: { [weak self] call in
                    Task { @mainActor in
                        self?.handleCallEnded(call)
                    }
                }
            )
        }
    }

    private func stopWatchingForCalls() {
        Task {
            await callWatcher?.stopWatching()
            callWatcher = nil
            isWatchingForCalls = false
            callDetectionState = .idle
            detectedCall = nil
        }
    }

    private func handleCallDetected(_ call: DetectedCall) {
        detectedCall = call
        callDetectionState = .warming

        // Auto-start recording after warmup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.autoRecord, !self.isRecording else { return }
            self.callDetectionState = .recording
            self.startRecording()
        }
    }

    private func handleCallEnded(_ call: DetectedCall) {
        callDetectionState = .cooling

        // Auto-stop recording after grace period
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.autoRecord, self.isRecording else { return }
            self.callDetectionState = .idle
            self.detectedCall = nil
            self.stopRecording()
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard let appState else { return }

        Task {
            do {
                if !(transcriptionEngine?.isInitialized ?? true) {
                    try await transcriptionEngine?.initialize(model: appState.selectedModel)
                }

                let tempDir = FileManager.default.temporaryDirectory
                let meetingName = detectedCall?.appName ?? "Recording"
                recordingURL = tempDir.appendingPathComponent("\(meetingName)_\(Date().timeIntervalSince1970).wav")

                if let url = recordingURL {
                    try await audioFileWriter?.startWriting(to: url)
                }

                try await audioCaptureManager?.startCapture(source: audioSource) { [weak self] buffer in
                    Task { @MainActor in
                        try? await self?.audioFileWriter?.write(buffer)
                        self?.updateAudioLevel(buffer)
                    }
                }

                isRecording = true
                appState.isRecording = true
                recordingTime = 0

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
            Task { await transcribeFile(at: url.path) }
        }
    }

    private func transcribeFile(at path: String) async {
        guard let appState else { return }

        isTranscribing = true
        appState.isTranscribing = true

        do {
            if !(transcriptionEngine?.isInitialized ?? true) {
                try await transcriptionEngine?.initialize(model: appState.selectedModel)
            }

            let result = try await transcriptionEngine?.transcribeFile(
                at: path,
                language: appState.selectedLanguage == "auto" ? nil : appState.selectedLanguage
            )

            guard var result else {
                throw TranscriptionError.transcriptionFailed("No result returned")
            }

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
        for i in 0..<frameLength { sum += abs(channelData[i]) }
        audioLevel = min(1.0, sum / Float(frameLength) * 10)
    }

    // MARK: - Diarization Merge

    private func mergeDiarization(_ result: TranscriptionResult, diarization: [DiarizationSegment]) -> TranscriptionResult {
        let updatedSegments = result.segments.map { segment -> TranscriptionSegment in
            let matchingSpeaker = diarization.first { d in
                segment.startTime < d.endTime && segment.endTime > d.startTime
            }
            if let speaker = matchingSpeaker {
                return TranscriptionSegment(
                    id: segment.id, startTime: segment.startTime, endTime: segment.endTime,
                    text: segment.text, language: segment.language,
                    speaker: speaker.speaker, confidence: segment.confidence
                )
            }
            return segment
        }
        return TranscriptionResult(
            id: result.id, date: result.date, segments: updatedSegments,
            fullText: result.fullText, duration: result.duration,
            language: result.language, modelName: result.modelName, fileName: result.fileName
        )
    }
}
