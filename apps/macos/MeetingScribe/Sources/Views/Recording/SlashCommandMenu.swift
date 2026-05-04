import SwiftUI
import AppKit

/// Small popup window shown when the user types `/` at the start of a line
/// in `MarkdownNotesEditor`. Lists the four `SlashCommand` cases. Selection
/// dismisses the menu and inserts the callout prefix at the trigger location.
@MainActor
final class SlashCommandMenuController {
    private var window: NSWindow?

    func show(anchoredTo screenPoint: NSPoint, onSelect: @escaping (SlashCommand) -> Void, onCancel: @escaping () -> Void) {
        dismiss()

        let content = SlashCommandMenuView(
            onSelect: { [weak self] command in
                self?.dismiss()
                onSelect(command)
            },
            onCancel: { [weak self] in
                self?.dismiss()
                onCancel()
            }
        )
        let host = NSHostingController(rootView: content)
        host.view.frame = NSRect(x: 0, y: 0, width: 220, height: 160)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.setFrameTopLeftPoint(screenPoint)
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct SlashCommandMenuView: View {
    let onSelect: (SlashCommand) -> Void
    let onCancel: () -> Void
    @State private var hoveredCommand: SlashCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSERT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(SlashCommand.allCases) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color(for: command)).frame(width: 8, height: 8)
                        Text(command.label).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(hoveredCommand == command ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredCommand = isHovered ? command : nil
                }
            }
        }
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .onExitCommand { onCancel() }
    }

    private func color(for command: SlashCommand) -> Color {
        switch command {
        case .action: return .red
        case .decision: return .green
        case .question: return .blue
        case .note: return .gray
        }
    }
}
