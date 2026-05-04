import SwiftUI

/// Thin status strip shown above the notes editor during recording.
/// Replaces the loud "● Recording 0:42" + giant title + waveform stack of
/// the previous design with a slim single-line bar.
struct RecordingTopBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(formatDuration(appState.recordingDuration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            divider

            // Inline-editable title (de-emphasized)
            TextField("Untitled meeting", text: $appState.meetingTitle)
                .textFieldStyle(.plain)
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: 280, alignment: .leading)

            // Optional calendar event badge
            if let event = appState.selectedCalendarEvent {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text(event.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.blue.opacity(0.75))
            }

            Spacer()

            // Transcript toggle
            Button {
                appState.toggleLiveTranscript()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.liveTranscriptEnabled ? "text.alignleft" : "text.alignleft.slash")
                    Text("Transcript")
                        .font(.caption.weight(.medium))
                    Text(appState.liveTranscriptEnabled ? "ON" : "OFF")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appState.liveTranscriptEnabled ? .blue : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(appState.liveTranscriptEnabled ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help(appState.liveTranscriptEnabled ? "Hide live transcript" : "Show live transcript")

            // Ask AI — opens the live chat panel (only when not already open)
            if !appState.showLiveChatPanel {
                Button {
                    appState.openLiveChatPanel()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask AI")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                .help("Ask the AI about this meeting")
            }

            // Audio level dots
            audioLevelDots

            // Stop button — outline style, far from notes
            Button {
                appState.toggleRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.red)
                .overlay(
                    Capsule().stroke(Color.red, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 36)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 14)
    }

    private var audioLevelDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        let threshold = Float(index + 1) * 0.2
        return appState.audioLevel >= threshold ? .red : Color.secondary.opacity(0.25)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        TimestampFormatter.format(seconds)
    }
}
