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
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNotesEditor
        weak var textView: NSTextView?

        init(_ parent: MarkdownNotesEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
    }
}
