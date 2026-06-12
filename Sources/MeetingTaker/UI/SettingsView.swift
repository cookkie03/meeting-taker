import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Transcription settings
            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            // Server settings
            serverSettings
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }

            // About
            aboutSection
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
        .padding()
    }

    // MARK: - Transcription Settings

    private var transcriptionSettings: some View {
        Form {
            Section {
                Picker("Default Model", selection: $appState.selectedModel) {
                    ForEach(TranscriptionEngine.modelTiers, id: \.name) { tier in
                        VStack(alignment: .leading) {
                            Text(tier.name)
                            Text(tier.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(tier.name)
                    }
                }

                Picker("Default Language", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("en")
                    Text("Italian").tag("it")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Portuguese").tag("pt")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                    Text("Korean").tag("ko")
                    Text("Russian").tag("ru")
                    Text("Arabic").tag("ar")
                    Text("Hindi").tag("hi")
                }
            } header: {
                Text("Model Configuration")
            } footer: {
                Text("Larger models provide better accuracy but require more disk space and time.")
            }

            Section {
                Toggle("Enable Speaker Diarization", isOn: $appState.enableDiarization)

                if appState.enableDiarization {
                    Stepper(
                        "Max Speakers: \(appState.maxSpeakers == 0 ? "Auto" : "\(appState.maxSpeakers)")",
                        value: $appState.maxSpeakers,
                        in: 0...10
                    )
                }
            } header: {
                Text("Speaker Detection")
            } footer: {
                Text("Speaker diarization identifies who spoke when. Set max speakers to 0 for auto-detection.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Server Settings

    private var serverSettings: some View {
        Form {
            Section {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $appState.serverPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Status")
                    Spacer()
                    Text(appState.isServerRunning ? "Running" : "Stopped")
                        .foregroundStyle(appState.isServerRunning ? .green : .secondary)
                }

                Button(appState.isServerRunning ? "Stop Server" : "Start Server") {
                    // Toggle server
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Local Server")
            } footer: {
                Text("The local server provides an OpenAI-compatible API for transcription. Access at http://localhost:\(appState.serverPort)/v1")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Endpoint")
                        .font(.headline)
                    Text("POST http://localhost:\(appState.serverPort)/v1/audio/transcriptions")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Example (curl):")
                        .font(.headline)
                        .padding(.top, 4)
                    Text("curl -X POST http://localhost:\(appState.serverPort)/v1/audio/transcriptions \\\n  -F file=@audio.wav \\\n  -F model=\(appState.selectedModel)")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } header: {
                Text("API Usage")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.accent)

            VStack(spacing: 4) {
                Text("MeetingTaker")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Version 1.0.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Professional-grade, on-device transcription for macOS. Powered by WhisperKit and SpeakerKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Divider()

            VStack(spacing: 8) {
                Text("Stack")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("• WhisperKit — Speech-to-text (OpenAI Whisper)")
                    Text("• SpeakerKit — Speaker diarization (Pyannote)")
                    Text("• SwiftUI — Native macOS interface")
                    Text("• Vapor — Local API server")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("100% local. Zero external dependencies. Your data never leaves your machine.")
                .font(.caption)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
