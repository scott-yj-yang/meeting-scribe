import SwiftUI

/// Top-level layout for the recording phase. Composes the top bar, notes
/// editor, and (when enabled) the live transcript pane. Replaces the inline
/// `recordingPhase` body that previously lived in `RecordingModeView`.
struct RecordingWorkspace: View {
    @EnvironmentObject var appState: AppState

    /// State holder used to pass the editor's coordinator out of the
    /// representable so external views (e.g. transcript pane click) can call
    /// `insertAtCaret(_:)` on it.
    @State private var notesEditorCoordinator: MarkdownNotesEditor.Coordinator?

    var body: some View {
        VStack(spacing: 0) {
            RecordingTopBar()
            HStack(spacing: 0) {
                MarkdownNotesEditor(text: $appState.meetingNotes, coordinatorRef: $notesEditorCoordinator)
                    .frame(maxWidth: .infinity)

                if appState.liveTranscriptEnabled && !appState.showLiveChatPanel {
                    Divider()
                    LiveTranscriptPane(
                        transcriptionManager: appState.transcriptionManager,
                        liveTranscriptError: appState.liveTranscriptError,
                        onChunkClick: { chunk in
                            let stamp = "[\(TimestampFormatter.format(chunk.startTime))] "
                            notesEditorCoordinator?.insertAtCaret(stamp)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.liveTranscriptEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.showLiveChatPanel)
        }
    }
}
