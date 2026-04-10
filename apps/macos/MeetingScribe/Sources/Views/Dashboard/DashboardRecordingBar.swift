import SwiftUI

/// Bottom-anchored bar wrapping RecordingPill with a meeting-title field.
/// Shown above the main dashboard content when no recording is in progress, or as a status bar when recording.
struct DashboardRecordingBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ZStack {
                // Title field — leading-aligned overlay, only visible when not recording
                if !appState.isRecording {
                    HStack {
                        TextField("Meeting title (optional)", text: $appState.meetingTitle)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded))
                            .frame(maxWidth: 280)
                        Spacer()
                    }
                }

                // Pill — always truly centered
                RecordingPill()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}
