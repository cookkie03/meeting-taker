import SwiftUI
import AVFoundation

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
        HStack(spacing: 12) {
            // Audio source picker
            Picker("Source", selection: $viewModel.audioSource) {
                ForEach(AudioSource.allCases) { source in
                    Label(source.displayName, systemImage: source.icon)
                        .tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Divider().frame(height: 20)

            // Model picker
            Picker("Model", selection: $appState.selectedModel) {
                ForEach(TranscriptionEngine.modelTiers, id: \.name) { tier in
                    Text("\(tier.name) (\(tier.size))").tag(tier.name)
                }
            }
            .frame(width: 220)

            // Language
            Picker("Language", selection: $appState.selectedLanguage) {
                Text("Auto").tag("auto")
                Text("🇬🇧 EN").tag("en")
                Text("🇮🇹 IT").tag("it")
                Text("🇪🇸 ES").tag("es")
                Text("🇫🇷 FR").tag("fr")
                Text("🇩🇪 DE").tag("de")
                Text("🇵🇹 PT").tag("pt")
                Text("🇯🇵 JP").tag("ja")
                Text("🇨🇳 ZH").tag("zh")
                Text("🇰🇷 KO").tag("ko")
                Text("🇷🇺 RU").tag("ru")
                Text("🇸🇦 AR").tag("ar")
                Text("🇮🇳 HI").tag("hi")
            }
            .frame(width: 120)

            Toggle("Speaker ID", isOn: $appState.enableDiarization)
                .toggleStyle(.checkbox)

            Spacer()

            // Audio level indicator
            if viewModel.isRecording {
                AudioLevelView(level: viewModel.audioLevel)
                    .frame(width: 60, height: 24)
            }

            // Record / Stop
            Button(action: {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
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

            Button("Open File...") {
                viewModel.openFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("Ready to Transcribe")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose your audio source, then click Record.\nOr open an audio file to transcribe.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Text("Audio Sources")
                    .font(.headline)
                HStack(spacing: 20) {
                    ForEach(AudioSource.allCases) { source in
                        VStack(spacing: 4) {
                            Image(systemName: source.icon)
                                .font(.title)
                            Text(source.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(viewModel.audioSource == source ? .accent : .secondary)
                    }
                }
            }
            .padding()
            .background(.quaternary.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if appState.isTranscribing {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(1.2)
                    Text("Transcribing...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: 500)
    }
}

// MARK: - Audio Level View

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    let threshold = Float(i + 1) / 10.0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level >= threshold ? .green : .quaternary.opacity(0.4))
                        .frame(height: geo.size.height * CGFloat(threshold))
                }
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

// MARK: - Transcription Result View

struct TranscriptionResultView: View {
    let result: TranscriptionResult
    @State private var showExport = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.fileName ?? "Live Recording")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label(result.language?.uppercased() ?? "Auto", systemImage: "globe")
                        Label("\(result.speakerCount) speakers", systemImage: "person.2")
                        Label(formatDuration(result.duration), systemImage: "clock")
                        Label(result.modelName, systemImage: "cpu")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(format.displayName) { exportAs(format) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.quaternary.opacity(0.3))

            Divider()

            // Segments
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.segments) { segment in
                        SegmentRow(segment: segment)
                        Divider()
                    }
                }
            }
        }
    }

    private func exportAs(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "transcription.\(format.fileExtension)"
        panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .plainText]

        if panel.runModal() == .OK, let url = panel.url {
            let exporter = ExportEngine()
            try? exporter.export(result, to: format, at: url)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Segment Row

struct SegmentRow: View {
    let segment: TranscriptionSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(segment.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("→ \(formatTime(segment.endTime))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.quaternary)
            }
            .frame(width: 80, alignment: .trailing)

            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(speakerColor(speaker).opacity(0.15))
                    .foregroundStyle(speakerColor(speaker))
                    .clipShape(Capsule())
            }

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func speakerColor(_ speaker: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]
        return colors[abs(speaker.hashValue) % colors.count]
    }
}
