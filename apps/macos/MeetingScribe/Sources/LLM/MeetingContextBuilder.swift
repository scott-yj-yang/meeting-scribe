import Foundation

/// A snapshot of a meeting's state used to build an LLM system prompt.
struct MeetingContext: Sendable {
    enum Mode: Sendable {
        case live          // recording in progress; transcript is partial
        case postMeeting   // recording finished; transcript is final
    }

    let title: String
    let date: Date
    let durationSeconds: TimeInterval
    let calendarEventTitle: String?
    let notes: String?
    let transcript: String
    let summary: String?
    let mode: Mode

    init(
        title: String,
        date: Date,
        durationSeconds: TimeInterval,
        calendarEventTitle: String?,
        notes: String?,
        transcript: String,
        summary: String?,
        mode: Mode
    ) {
        self.title = title
        self.date = date
        self.durationSeconds = durationSeconds
        self.calendarEventTitle = calendarEventTitle
        self.notes = notes
        self.transcript = transcript
        self.summary = summary
        self.mode = mode
    }
}

enum MeetingContextBuilder {
    /// Build the system `ChatMessage` that should be prepended to every chat turn.
    static func buildSystemMessage(context: MeetingContext) -> ChatMessage {
        var parts: [String] = []

        // Preamble + instructions
        parts.append(preamble(mode: context.mode))

        // Meeting metadata
        parts.append(metadataBlock(context: context))

        // Notes
        if let notes = context.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append("# User notes\n\(notes)")
        }

        // Summary
        if let summary = context.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append("# Summary\n\(summary)")
        }

        // Transcript
        let transcriptHeader = context.mode == .live
            ? "# Live transcript (in progress)"
            : "# Transcript"
        parts.append("\(transcriptHeader)\n\(context.transcript)")

        return ChatMessage(role: .system, text: parts.joined(separator: "\n\n"))
    }

    private static func preamble(mode: MeetingContext.Mode) -> String {
        let modeLine: String
        switch mode {
        case .live:
            modeLine = "The meeting is currently happening. The transcript below is partial and may contain recognition errors from real-time transcription."
        case .postMeeting:
            modeLine = "The meeting has concluded. The transcript below is the final whisper-generated transcript."
        }
        return """
        You are an assistant helping the user with a meeting. Answer questions based only on the information in the meeting transcript, summary, and notes provided below. If the answer isn't in the provided context, say so honestly instead of guessing.

        \(modeLine)

        When citing specific moments from the transcript, use the format [[mm:ss]] after the claim, where mm:ss is the timestamp of the relevant line. Do not invent timestamps. You may omit citations when they are not needed.
        """
    }

    private static func metadataBlock(context: MeetingContext) -> String {
        let isoDate = context.date.formatted(date: .abbreviated, time: .shortened)
        let duration = Self.formatDuration(context.durationSeconds)
        var lines = ["# Meeting", "Title: \(context.title)", "Date: \(isoDate)", "Duration: \(duration)"]
        if let cal = context.calendarEventTitle, !cal.isEmpty {
            lines.append("Calendar event: \(cal)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let remainderSeconds = total % 60
        if total == 0 { return "in progress" }
        if minutes == 0 { return "\(remainderSeconds)s" }
        return "\(minutes)m \(remainderSeconds)s"
    }
}
