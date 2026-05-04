import Foundation

/// One of the four slash-command callouts the user can insert from
/// `SlashCommandMenu`. Each maps to a markdown blockquote-callout prefix
/// that `MarkdownStyler` renders as a colored chip on the line.
enum SlashCommand: String, CaseIterable, Identifiable {
    case action, decision, question, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .action: return "Action"
        case .decision: return "Decision"
        case .question: return "Question"
        case .note: return "Note"
        }
    }

    var calloutPrefix: String {
        return "> [!\(rawValue)] "
    }

    /// Applies this command's insertion to a buffer where the user typed `/`
    /// at `triggerSlashLocation` (UTF-16 offset). Removes the `/` and inserts
    /// the callout prefix in its place. Returns the new text and where the
    /// caret should land (just after the prefix).
    struct InsertionResult {
        let text: String
        /// UTF-16 caret position in the new text.
        let caretLocation: Int
    }

    func applyInsertion(into buffer: String, triggerSlashLocation: Int) -> InsertionResult {
        let nsBuffer = buffer as NSString
        let mutable = NSMutableString(string: nsBuffer)
        // Replace the single "/" character with the callout prefix.
        mutable.replaceCharacters(in: NSRange(location: triggerSlashLocation, length: 1), with: calloutPrefix)
        let caret = triggerSlashLocation + (calloutPrefix as NSString).length
        return InsertionResult(text: mutable as String, caretLocation: caret)
    }
}
