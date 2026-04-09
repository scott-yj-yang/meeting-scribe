import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Main dashboard window
        WindowGroup("MeetingScribe") {
            DashboardWindow()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(appState)
        }
        .defaultSize(width: 1200, height: 800)

        // Menu bar recording controls (always visible)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "doc.text.magnifyingglass")
                if appState.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
