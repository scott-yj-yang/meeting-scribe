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
        } else if isBullet(lineText) {
            applyBulletParagraph(in: lineRange, storage: storage)
        } else if let checkbox = checkboxState(of: lineText), lineRange.length >= 3 {
            let markerRange = NSRange(location: lineRange.location, length: 3)
            let color: NSColor = checkbox ? .systemGreen : .controlAccentColor
            storage.addAttribute(.foregroundColor, value: color, range: markerRange)
        } else if lineText.hasPrefix("> ") {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
        }
        applyInline(in: lineRange, storage: storage, lineText: lineText)
    }

    private static func isBullet(_ line: String) -> Bool {
        return line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    /// Returns true if the line begins with `[x]`, false if `[ ]`, nil otherwise.
    private static func checkboxState(of line: String) -> Bool? {
        if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") { return true }
        if line.hasPrefix("[ ] ") { return false }
        return nil
    }

    private static func applyBulletParagraph(in lineRange: NSRange, storage: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.headIndent = 16
        storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
    }

    // MARK: - Inline patterns

    private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicAsteriskRegex = try! NSRegularExpression(pattern: #"(?<![*\w])\*(?!\*)([^*\n]+?)\*(?!\*)"#)
    private static let italicUnderscoreRegex = try! NSRegularExpression(pattern: #"(?<![_\w])_([^_\n]+?)_(?![_\w])"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"`([^`\n]+?)`"#)

    private static func applyInline(in lineRange: NSRange, storage: NSMutableAttributedString, lineText: String) {
        // Apply in this order: code (claims monospaced), bold (** before *), italic.
        applyMatches(codeRegex, in: lineRange, against: lineText) { innerRange in
            let mono = NSFont.monospacedSystemFont(ofSize: bodyPointSize, weight: .regular)
            storage.addAttribute(.font, value: mono, range: innerRange)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: innerRange)
        }
        applyMatches(boldRegex, in: lineRange, against: lineText) { innerRange in
            applyTrait(.bold, in: innerRange, storage: storage)
        }
        applyMatches(italicAsteriskRegex, in: lineRange, against: lineText) { innerRange in
            applyTrait(.italic, in: innerRange, storage: storage)
        }
        applyMatches(italicUnderscoreRegex, in: lineRange, against: lineText) { innerRange in
            applyTrait(.italic, in: innerRange, storage: storage)
        }
    }

    /// Runs a regex against `lineText` and calls `apply` with the *inner*
    /// (capture group 1) range translated back to the full storage range.
    private static func applyMatches(_ regex: NSRegularExpression, in lineRange: NSRange, against lineText: String, apply: (NSRange) -> Void) {
        let lineFullRange = NSRange(location: 0, length: (lineText as NSString).length)
        regex.enumerateMatches(in: lineText, range: lineFullRange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let innerInLine = match.range(at: 1)
            let innerInStorage = NSRange(location: lineRange.location + innerInLine.location, length: innerInLine.length)
            apply(innerInStorage)
        }
    }

    private static func applyTrait(_ trait: NSFontDescriptor.SymbolicTraits, in range: NSRange, storage: NSMutableAttributedString) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let base = (value as? NSFont) ?? NSFont.systemFont(ofSize: bodyPointSize)
            var traits = base.fontDescriptor.symbolicTraits
            traits.insert(trait)
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
            let merged = NSFont(descriptor: descriptor, size: base.pointSize) ?? base
            storage.addAttribute(.font, value: merged, range: subrange)
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
