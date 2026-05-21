import SwiftUI

/// Top-level layout for the recording phase. Composes the top bar and notes
/// editor. Replaces the inline `recordingPhase` body that previously lived in
/// `RecordingModeView`.
struct RecordingWorkspace: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            RecordingTopBar()
            MarkdownNotesEditor(text: $appState.meetingNotes)
                .frame(maxWidth: .infinity)
        }
    }
}
