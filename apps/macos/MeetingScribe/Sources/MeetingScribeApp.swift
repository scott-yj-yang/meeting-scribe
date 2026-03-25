import SwiftUI

@main
struct MeetingScribeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: appState.isRecording
                    ? "waveform.circle.fill"
                    : "doc.text.magnifyingglass")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                if appState.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
