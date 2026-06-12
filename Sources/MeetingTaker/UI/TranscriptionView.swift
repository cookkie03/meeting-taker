import SwiftUI
import AVFoundation

struct TranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            toolbar

            Divider()

            // Main content
            if let result = viewModel.currentResult {
                TranscriptionResultView(result: result)
            } else {
                emptyState
            }
        }
        .onAppear {
            viewModel.setup(appState: appState)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Model picker
            Picker("Model", selection: $appState.selectedModel) {
                ForEach(TranscriptionEngine.modelTiers, id: \.name) { tier in
                    Text("\(tier.name) (\(tier.size))")
                        .tag(tier.name)
                }
            }
            .frame(width: 250)

            // Language picker
            Picker("Language", selection: $appState.selectedLanguage) {
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
            .frame(width: 140)

            Toggle("Speaker ID", isOn: $appState.enableDiarization)
                .toggleStyle(.checkbox)

            Spacer()

            // Record / Stop button
            Button(action: {
                if appState.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            }) {
                HStack {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "record.circle.fill")
                        .font(.title2)
                    Text(appState.isRecording ? "Stop" : "Record")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(appState.isRecording ? .red : .accent)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // Transcribe file button
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
                .font(.system(size: 80))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("Ready to Transcribe")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Click Record to capture from microphone, or Open File to transcribe an audio file.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if appState.isTranscribing {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Transcribing...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: 400)
    }
}

// MARK: - Transcription Result View

struct TranscriptionResultView: View {
    let result: TranscriptionResult
    @State private var selectedFormat: ExportFormat = .txt
    @State private var showExport = false

    var body: some View {
        VStack(spacing: 0) {
            // Result header
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

                // Export button
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(format.displayName) {
                            exportAs(format)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.quaternary.opacity(0.3))

            Divider()

            // Segments list
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
            do {
                try exporter.export(result, to: format, at: url)
            } catch {
                // Handle error
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Segment Row

struct SegmentRow: View {
    let segment: TranscriptionSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(segment.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("→ \(formatTime(segment.endTime))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.quaternary)
            }
            .frame(width: 80, alignment: .trailing)

            // Speaker badge
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

            // Text
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func speakerColor(_ speaker: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]
        let hash = abs(speaker.hashValue)
        return colors[hash % colors.count]
    }
}
