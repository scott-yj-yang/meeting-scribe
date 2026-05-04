import SwiftUI
import AppKit

/// Markdown-aware notes editor used in the recording phase. Wraps an
/// `NSTextView` inside an `NSScrollView`. Bound to a `String` via the
/// standard SwiftUI `@Binding` mechanism.
///
/// Styling (via `MarkdownStyler`) and the slash-command menu are added in
/// follow-up tasks.
struct MarkdownNotesEditor: NSViewRepresentable {
    @Binding var text: String
    /// Optional outbound binding so parents can hold a reference to the
    /// coordinator and call `insertAtCaret(_:)` from external views (e.g.
    /// the transcript pane click handler).
    var coordinatorRef: Binding<Coordinator?>? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.font = NSFont.systemFont(ofSize: MarkdownStyler.bodyPointSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.delegate = context.coordinator

        scroll.documentView = textView
        context.coordinator.textView = textView

        // Initial text load
        textView.string = text
        if let storage = textView.textStorage {
            MarkdownStyler.applyAttributes(to: storage)
        }

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        if let ref = coordinatorRef {
            DispatchQueue.main.async { [weak coord] in
                ref.wrappedValue = coord
            }
        }
        return coord
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNotesEditor
        weak var textView: NSTextView?
        private let slashMenu = SlashCommandMenuController()
        private var pendingSlashLocation: Int?

        init(_ parent: MarkdownNotesEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            detectSlashTrigger(in: tv)
            parent.text = tv.string
        }

        /// Detects when the user just typed `/` at the start of a line and shows the slash menu.
        private func detectSlashTrigger(in tv: NSTextView) {
            let selected = tv.selectedRange()
            guard selected.length == 0, selected.location > 0 else { return }
            let nsString = tv.string as NSString
            let charBefore = nsString.substring(with: NSRange(location: selected.location - 1, length: 1))
            guard charBefore == "/" else { return }
            // At line start? Either offset 0 or preceding char is newline.
            let triggerLocation = selected.location - 1
            let isLineStart: Bool = {
                if triggerLocation == 0 { return true }
                let prior = nsString.substring(with: NSRange(location: triggerLocation - 1, length: 1))
                return prior == "\n"
            }()
            guard isLineStart else { return }
            showSlashMenu(in: tv, triggerLocation: triggerLocation)
        }

        private func showSlashMenu(in tv: NSTextView, triggerLocation: Int) {
            pendingSlashLocation = triggerLocation
            // Convert text position to a screen point under the caret.
            guard let layoutManager = tv.layoutManager,
                  let textContainer = tv.textContainer else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: triggerLocation, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let inView = NSRect(
                x: rect.origin.x + tv.textContainerOrigin.x,
                y: rect.origin.y + tv.textContainerOrigin.y + rect.height + 2,
                width: rect.width, height: rect.height
            )
            let inWindow = tv.convert(inView, to: nil)
            guard let window = tv.window else { return }
            let onScreen = window.convertToScreen(inWindow)
            let topLeft = NSPoint(x: onScreen.origin.x, y: onScreen.origin.y)

            slashMenu.show(
                anchoredTo: topLeft,
                onSelect: { [weak self] command in
                    self?.applySlashCommand(command, in: tv)
                },
                onCancel: { [weak self] in
                    self?.pendingSlashLocation = nil
                }
            )
        }

        private func applySlashCommand(_ command: SlashCommand, in tv: NSTextView) {
            guard let location = pendingSlashLocation else { return }
            pendingSlashLocation = nil
            let result = command.applyInsertion(into: tv.string, triggerSlashLocation: location)
            tv.string = result.text
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            tv.setSelectedRange(NSRange(location: result.caretLocation, length: 0))
            parent.text = tv.string
        }

        /// Public API for external views (e.g. `LiveTranscriptPane`) to insert
        /// text at the current caret position. Re-styles after the insert.
        func insertAtCaret(_ string: String) {
            guard let tv = textView else { return }
            let selected = tv.selectedRange()
            let nsString = tv.string as NSString
            let mutable = NSMutableString(string: nsString)
            mutable.replaceCharacters(in: selected, with: string)
            tv.string = mutable as String
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            let caret = selected.location + (string as NSString).length
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            tv.window?.makeFirstResponder(tv)
            parent.text = tv.string
        }
    }
}
