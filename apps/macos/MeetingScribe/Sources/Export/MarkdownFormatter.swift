import Foundation

struct MarkdownFormatter {
    static func format(
        title: String,
        date: Date,
        duration: TimeInterval,
        meetingType: String?,
        audioSources: [String],
        segments: [TranscriptSegment]
    ) -> String {
        let participants = Array(Set(segments.map(\.speaker)))
        let dateISO = ISO8601DateFormatter().string(from: date)
        let dateHuman = date.formatted(.dateTime.year().month(.wide).day().hour().minute())

        var md = """
        ---
        title: "\(title)"
        date: \(dateISO)
        duration: \(Int(duration))
        meeting_type: \(meetingType.map { "\"\($0)\"" } ?? "null")
        audio_sources: \(audioSources)
        participants: \(participants)
        ---

        # Meeting Transcript: \(title)
        **Date**: \(dateHuman)
        **Duration**: \(formatDuration(duration))

        ## Transcript

        """

        for segment in segments {
            let ts = formatTimestamp(segment.startTime)
            md += "\(ts) **\(segment.speaker)**: \(segment.text)\n\n"
        }

        md += "## --- END TRANSCRIPT ---\n"
        return md
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h != 1 ? "s" : "")") }
        if m > 0 { parts.append("\(m) minute\(m != 1 ? "s" : "")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) second\(s != 1 ? "s" : "")") }
        return parts.joined(separator: " ")
    }

    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "[%02d:%02d:%02d]", h, m, s)
    }
}
