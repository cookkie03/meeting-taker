import SwiftUI

@main
struct MeetingTakerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
