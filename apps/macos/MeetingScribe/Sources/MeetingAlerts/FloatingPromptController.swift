import AppKit
import SwiftUI
import Combine

/// Owns the always-on-top NSPanel that shows the active meeting prompt.
@MainActor
final class FloatingPromptController {
    private let monitor: MeetingMonitor
    private weak var appState: AppState?
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    init(monitor: MeetingMonitor, appState: AppState) {
        self.monitor = monitor
        self.appState = appState
        cancellable = monitor.$activePrompt
            .receive(on: RunLoop.main)
            .sink { [weak self] prompt in self?.render(prompt) }
    }

    private func render(_ prompt: MeetingPrompt?) {
        guard let prompt else { close(); return }

        let view = MeetingPromptView(
            prompt: prompt,
            onStartRecording: { [weak self] in
                self?.appState?.beginRecording(from: prompt)
            },
            onJoin: {
                if let url = prompt.joinURL { NSWorkspace.shared.open(url) }
                // Joining isn't dismissing — leave the prompt so they can still
                // Start Recording. It clears when handled or the meeting passes.
            },
            onDismiss: { [weak self] in self?.monitor.dismissActive() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        positionTopRight(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let inset: CGFloat = 20
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - inset,
            y: visible.maxY - size.height - inset
        ))
    }
}
