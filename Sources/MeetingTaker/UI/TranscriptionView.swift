import SwiftUI

struct TranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if let result = viewModel.currentResult {
                TranscriptionResultView(result: result)
            } else {
                emptyState
            }
        }
        .onAppear { viewModel.setup(appState: appState) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            // Top row: source, model, language, diarize
            HStack(spacing: 12) {
                // Audio source
                Picker("Source", selection: $viewModel.audioSource) {
                    ForEach(AudioSource.allCases) { source in
                        Label(source.displayName, systemImage: source.icon)
                            .tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Divider().frame(height: 20)

                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(TranscriptionEngine.modelTiers, id: \.name) { tier in
                        Text("\(tier.name) (\(tier.size))").tag(tier.name)
                    }
                }
                .frame(width: 220)

                Picker("Language", selection: $appState.selectedLanguage) {
                    Text("Auto").tag("auto")
                    Text("🇬🇧 EN").tag("en")
                    Text("🇮🇹 IT").tag("it")
                    Text("🇪🇸 ES").tag("es")
                    Text("🇫🇷 FR").tag("fr")
                    Text("🇩🇪 DE").tag("de")
                    Text("🇵🇹 PT").tag("pt")
                    Text("🇯🇵 JA").tag("ja")
                    Text("🇨🇳 ZH").tag("zh")
                    Text("🇰🇷 KO").tag("ko")
                    Text("🇷🇺 RU").tag("ru")
                    Text("🇸🇦 AR").tag("ar")
                    Text("🇮🇳 HI").tag("hi")
                }
                .frame(width: 120)

                Toggle("Speaker ID", isOn: $appState.enableDiarization)
                    .toggleStyle(.checkbox)

                // Auto-record toggle
                Toggle("Auto-Record", isOn: $viewModel.autoRecord)
                    .toggleStyle(.checkbox)
                    .help("Automatically start recording when a call is detected")

                Spacer()

                // Audio level
                if viewModel.isRecording {
                    AudioLevelView(level: viewModel.audioLevel)
                        .frame(width: 60, height: 24)
                }

                Button(action: {
                    if viewModel.isRecording { viewModel.stopRecording() }
                    else { viewModel.startRecording() }
                }) {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.title2)
                        Text(viewModel.isRecording ? "Stop" : "Record")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(viewModel.isRecording ? .red : .accent)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Open File...") { viewModel.openFile() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            // Call detection status bar
            if viewModel.isWatchingForCalls {
                CallDetectionBar(
                    state: viewModel.callDetectionState,
                    detectedCall: viewModel.detectedCall
                )
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("Ready to Transcribe")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose audio source, then click Record.\nEnable Auto-Record to detect calls automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Audio sources overview
            VStack(spacing: 8) {
                Text("Audio Sources")
                    .font(.headline)
                HStack(spacing: 20) {
                    ForEach(AudioSource.allCases) { source in
                        VStack(spacing: 4) {
                            Image(systemName: source.icon).font(.title)
                            Text(source.displayName).font(.caption)
                        }
                        .foregroundStyle(viewModel.audioSource == source ? .accent : .secondary)
                    }
                }
            }
            .padding()
            .background(.quaternary.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Call detection info
            if viewModel.isWatchingForCalls {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(.green)
                    Text("Watching for calls: Zoom, Meet, Teams, FaceTime, Slack Huddle, Webex, Discord…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.isTranscribing {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(1.2)
                    Text("Transcribing...").font(.callout).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: 600)
    }
}

// MARK: - Call Detection Bar

struct CallDetectionBar: View {
    let state: CallDetectionState
    let detectedCall: DetectedCall?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            switch state {
            case .idle:
                Text("Listening for calls...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .warming:
                if let call = detectedCall {
                    Text("Detected: \(call.appName) — starting in \(Int(warmupRemaining))s...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

            case .recording:
                if let call = detectedCall {
                    Text("🔴 Recording: \(call.appName)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

            case .cooling:
                Text("Call ended — stopping in \(Int(coolingRemaining))s...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(iconColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var iconName: String {
        switch state {
        case .idle:      return "magnifyingglass"
        case .warming:   return "ear"
        case .recording: return "record.circle.fill"
        case .cooling:   return "stop.circle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:      return .secondary
        case .warming:   return .orange
        case .recording: return .red
        case .cooling:   return .orange
        }
    }

    private var warmupRemaining: TimeInterval { 5.0 }
    private var coolingRemaining: TimeInterval { 5.0 }
}
