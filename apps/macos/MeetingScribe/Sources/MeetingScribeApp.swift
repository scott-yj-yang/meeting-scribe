import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isRecording ? "record.circle.fill" : "mic.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
