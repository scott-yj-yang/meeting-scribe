import AppKit

/// Pure-Swift module that applies markdown rendering attributes to an
/// `NSMutableAttributedString` (typically the `textStorage` of an
/// `NSTextView`). Inline-style: syntax characters (`**`, `#`, `-`) remain
/// visible; only the appearance of the affected text changes.
///
/// `MarkdownNotesEditor` calls `applyAttributes(to:)` on every text change.
/// The function clears all attributes first, then re-applies them, so editing
/// a previously-styled line back to plain text correctly removes the style.
enum MarkdownStyler {

    static let bodyPointSize: CGFloat = 14

    static func applyAttributes(to storage: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        // Reset to body style across the full range.
        let bodyFont = NSFont.systemFont(ofSize: bodyPointSize)
        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        // Walk lines and apply line-level attributes.
        let nsString = storage.string as NSString
        var lineStart = 0
        while lineStart < nsString.length {
            var lineEnd = 0
            var contentsEnd = 0
            nsString.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            applyLineLevel(in: lineRange, storage: storage, nsString: nsString)
            lineStart = lineEnd
        }
    }

    // MARK: - Line-level patterns

    private static func applyLineLevel(in lineRange: NSRange, storage: NSMutableAttributedString, nsString: NSString) {
        guard lineRange.length > 0 else { return }
        let lineText = nsString.substring(with: lineRange)
        if let level = headingLevel(of: lineText) {
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 15)
            let font = NSFont.boldSystemFont(ofSize: size)
            storage.addAttribute(.font, value: font, range: lineRange)
        }
    }

    /// Returns 1, 2, or 3 if the line begins with `# `, `## `, or `### ` respectively. Otherwise nil.
    private static func headingLevel(of line: String) -> Int? {
        if line.hasPrefix("### ") { return 3 }
        if line.hasPrefix("## ") { return 2 }
        if line.hasPrefix("# ") { return 1 }
        return nil
    }
}
