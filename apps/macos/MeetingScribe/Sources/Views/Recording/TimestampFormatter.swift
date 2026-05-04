import Foundation

/// Formats a duration in seconds as `m:ss` or `h:mm:ss`.
/// Used both by `LiveTranscriptPane` (rendering chunk timestamps) and by
/// the click-to-anchor logic that inserts `[m:ss] ` into the notes editor.
enum TimestampFormatter {
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
