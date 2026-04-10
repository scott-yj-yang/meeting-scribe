import SwiftUI

/// Bottom-anchored bar wrapping RecordingPill with a meeting-title field.
/// Shown above the main dashboard content when no recording is in progress, or as a status bar when recording.
struct DashboardRecordingBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if !appState.isRecording {
                    TextField("Meeting title (optional)", text: $appState.meetingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: 280)
                    Spacer()
                } else {
                    Spacer()
                }

                RecordingPill()

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}
