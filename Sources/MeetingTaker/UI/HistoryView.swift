import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedResult: TranscriptionResult?

    var filteredResults: [TranscriptionResult] {
        if searchText.isEmpty {
            return appState.transcriptionHistory
        }
        return appState.transcriptionHistory.filter {
            $0.fullText.localizedCaseInsensitiveContains(searchText) ||
            ($0.fileName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedResult) {
                ForEach(filteredResults) { result in
                    HistoryRow(result: result)
                        .tag(result)
                }
                .onDelete(perform: deleteItems)
            }
            .searchable(text: $searchText, prompt: "Search transcriptions...")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: clearAll) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(appState.transcriptionHistory.isEmpty)
                }
            }
        } detail: {
            if let result = selectedResult {
                TranscriptionResultView(result: result)
            } else {
                ContentUnavailableView(
                    "Select a Transcription",
                    systemImage: "doc.text",
                    description: Text("Choose a transcription from the sidebar to view details.")
                )
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let result = filteredResults[index]
            if let idx = appState.transcriptionHistory.firstIndex(where: { $0.id == result.id }) {
                appState.transcriptionHistory.remove(at: idx)
            }
        }
    }

    private func clearAll() {
        appState.transcriptionHistory.removeAll()
        selectedResult = nil
    }
}

struct HistoryRow: View {
    let result: TranscriptionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.fileName ?? "Recording")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(result.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.fullText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(result.language?.uppercased() ?? "Auto", systemImage: "globe")
                Label("\(result.speakerCount) spk", systemImage: "person.2")
                Label(formatDuration(result.duration), systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
