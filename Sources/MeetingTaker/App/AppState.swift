import SwiftUI
import Combine

/// Global app state
@MainActor
public class AppState: ObservableObject {
    @Published public var isRecording = false
    @Published public var isTranscribing = false
    @Published public var currentTranscription: TranscriptionResult?
    @Published public var transcriptionHistory: [TranscriptionResult] = []
    @Published public var selectedModel: String = TranscriptionEngine.defaultModel
    @Published public var selectedLanguage: String = "auto"
    @Published public var enableDiarization = true
    @Published public var maxSpeakers: Int = 0 // 0 = auto
    @Published public var serverPort: Int = 50060
    @Published public var isServerRunning = false
    @Published public var errorMessage: String?
    @Published public var showError = false

    public init() {}

    public func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
