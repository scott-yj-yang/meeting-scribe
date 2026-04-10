import SwiftUI

/// Floating pill that combines: record/stop button, duration, waveform.
/// Reads recording state from `AppState`. Reusable — drop into menu bar or dashboard.
struct RecordingPill: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { appState.toggleRecording() }) {
                Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(appState.isRecording ? .red : .blue)
                    .symbolEffect(.pulse, isActive: appState.isRecording)
            }
            .buttonStyle(.plain)

            if appState.isRecording {
                WaveformBars(level: appState.audioLevel, tint: .red)
                Text(formatDuration(appState.recordingDuration))
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(minWidth: 56, alignment: .leading)
            } else {
                Text("Start recording")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
