import SwiftUI
import AppKit

/// Floating stop-recording button shown at the bottom of the recording
/// workspace. Two-click confirm: first click arms; second click within
/// 3 seconds actually stops. Auto-disarms after 3s of inactivity. Hover
/// scales + glows.
struct StopRecordingButton: View {
    var compact: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var phase: Phase = .idle
    @State private var revertTask: Task<Void, Never>?
    @State private var isHovered = false
    @State private var confirmProgress: CGFloat = 1.0

    private enum Phase {
        case idle
        case confirming
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 10) {
                Image(systemName: phase == .idle ? "stop.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: compact ? 15 : 18, weight: .semibold))
                    .symbolEffect(.pulse, options: phase == .confirming ? .repeating : .nonRepeating, value: phase)
                Text(phase == .idle ? "Stop Recording" : "Tap again to confirm")
                    .font(.system(compact ? .callout : .body, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, compact ? 18 : 28)
            .padding(.vertical, compact ? 10 : 14)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(phase == .confirming ? Color.red : Color.red.opacity(0.92))
                    .shadow(
                        color: Color.red.opacity(isHovered ? 0.45 : 0.25),
                        radius: isHovered ? 14 : 8,
                        x: 0, y: 4
                    )
            )
            .overlay(alignment: .leading) {
                if phase == .confirming {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: max(0, confirmProgress * 200), height: 4)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(AppAnim.snappy, value: isHovered)
            .animation(AppAnim.standard, value: phase)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(phase == .idle
              ? "Click to stop recording — you'll be asked to confirm"
              : "Click again to stop. Auto-cancels in a few seconds.")
    }

    private func handleTap() {
        switch phase {
        case .idle:
            withAnimation(AppAnim.standard) { phase = .confirming }
            confirmProgress = 1.0
            withAnimation(.linear(duration: 3.0)) {
                confirmProgress = 0.0
            }
            revertTask?.cancel()
            revertTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled {
                    withAnimation(AppAnim.standard) { phase = .idle }
                    confirmProgress = 1.0
                }
            }
        case .confirming:
            revertTask?.cancel()
            revertTask = nil
            appState.toggleRecording()
        }
    }
}
