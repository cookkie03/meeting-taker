import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
                .frame(minWidth: 200)
        } detail: {
            switch selectedTab {
            case 0:
                TranscriptionView()
            case 1:
                HistoryView()
            default:
                TranscriptionView()
            }
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") { appState.showError = false }
        } message: {
            Text(appState.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: Int

    var body: some View {
        List {
            Section {
                Button(action: { selectedTab = 0 }) {
                    Label("Transcribe", systemImage: "mic.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == 0 ? .accent : .primary)

                Button(action: { selectedTab = 1 }) {
                    Label("History", systemImage: "clock.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == 1 ? .accent : .primary)
            }

            if !AppState().transcriptionHistory.isEmpty {
                Section("Recent") {
                    ForEach(AppState().transcriptionHistory.prefix(5)) { result in
                        Button(action: { selectedTab = 1 }) {
                            VStack(alignment: .leading) {
                                Text(result.fileName ?? "Recording")
                                    .font(.headline)
                                Text(result.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("MeetingTaker")
        .toolbar {
            ToolbarItem {
                SettingsLink {
                    Image(systemName: "gear")
                }
            }
        }
    }
}
