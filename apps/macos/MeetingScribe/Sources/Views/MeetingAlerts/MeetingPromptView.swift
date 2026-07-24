import SwiftUI

struct MeetingPromptView: View {
    let prompt: MeetingPrompt
    let onStartRecording: () -> Void
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: prompt.kind == .zoomMeeting ? "video.fill" : "calendar")
                    .foregroundStyle(.blue)
                Text(prompt.kind == .zoomMeeting ? "Meeting in progress" : "Meeting starting soon")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(prompt.title)
                .font(.system(.body, weight: .medium))
                .lineLimit(2)

            if let start = prompt.startDate {
                CountdownBar(target: start)
            }

            HStack(spacing: 8) {
                if prompt.joinURL != nil {
                    Button(action: onJoin) {
                        Label("Join", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: onStartRecording) {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}

/// A bar that shrinks toward `target`, with a "Starts in m:ss" label.
private struct CountdownBar: View {
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, target.timeIntervalSince(context.date))
            let window: TimeInterval = 120 // full bar at 2 min out
            let fraction = min(1, remaining / window)
            VStack(alignment: .leading, spacing: 4) {
                Text(remaining > 0 ? "Starts in \(Self.mmss(remaining))" : "Starting now")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.blue)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
