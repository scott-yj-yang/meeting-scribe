import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow
    @State private var promptController: FloatingPromptController?

    var body: some Scene {
        // Main dashboard window
        Window("MeetingScribe Dashboard", id: "dashboard") {
            DashboardRoot()
                .environmentObject(appState)
                .onAppear { Self.setAppIcon() }
        }
        .defaultSize(width: 1200, height: 800)

        // Menu bar recording controls (always visible)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .task {
                    // The MenuBarExtra scene is always alive, so it's the right
                    // place to keep the floating-prompt controller and to react
                    // to a prompt-initiated recording by surfacing the window.
                    if promptController == nil {
                        promptController = FloatingPromptController(
                            monitor: appState.meetingMonitor, appState: appState
                        )
                    }
                }
                .onChange(of: appState.recordingSurfaceRequest) { _, _ in
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
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
                SetupView()
                    .tabItem { Label("Setup", systemImage: "arrow.down.circle") }
                LLMSettingsView()
                    .tabItem { Label("Summarization", systemImage: "brain.head.profile") }
                NotionSettingsView()
                    .tabItem { Label("Notion", systemImage: "square.and.arrow.up.on.square") }
            }
            .frame(width: 560, height: 420)
        }
    }

    private static func setAppIcon() {
        let bundleName = "MeetingScribe_MeetingScribe"
        if let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let icon = resourceBundle.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
    }
}

private struct DashboardRoot: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some View {
        NativeDashboard()
            .frame(minWidth: 900, minHeight: 600)
            .sheet(isPresented: Binding(
                get: { !hasCompletedWelcome },
                set: { newValue in
                    if !newValue { hasCompletedWelcome = true }
                }
            )) {
                WelcomeView()
                    .interactiveDismissDisabled()
            }
    }
}
