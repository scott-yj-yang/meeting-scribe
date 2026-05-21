import SwiftUI

/// Top-level layout for the recording phase. Composes the top bar and notes
/// editor. Replaces the inline `recordingPhase` body that previously lived in
/// `RecordingModeView`.
struct RecordingWorkspace: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                RecordingTopBar()
                MarkdownNotesEditor(text: $appState.meetingNotes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            StopRecordingButton()
                .padding(.bottom, 28)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}
