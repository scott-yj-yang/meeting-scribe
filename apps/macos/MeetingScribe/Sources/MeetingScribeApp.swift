import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    var body: some Scene {
        // Main dashboard window
        Window("MeetingScribe Dashboard", id: "dashboard") {
            NativeDashboard()
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

        Settings {
            TabView {
                LLMSettingsView()
                    .tabItem { Label("LLM", systemImage: "brain.head.profile") }
                NotionSettingsView()
                    .tabItem { Label("Notion", systemImage: "square.and.arrow.up.on.square") }
            }
            .frame(width: 560, height: 420)
        }
    }
}
