import Foundation

/// Organizes meeting files into a date-based hierarchy:
///   ~/MeetingScribe/
///     2026/
///       03-March/
///         25-sprint-planning/
///           transcript.md
///           audio.wav
///           CLAUDE.md
///           .claude/commands/summarize.md
struct LocalStorage {

    /// Save transcript markdown into an already-resolved meeting folder and
    /// return the file URL.
    ///
    /// Takes the folder rather than a title so it cannot disagree with the
    /// folder the audio was written to.
    static func save(markdown: String, to meetingDir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let fileURL = meetingDir.appendingPathComponent("transcript.md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        try? writeClaudeWorkspace(at: meetingDir)

        return fileURL
    }

    /// Drop a CLAUDE.md guide and a `/summarize` slash command into the meeting
    /// folder so the user can `cd` there, run `claude`, and produce a summary
    /// without having to know our prompt format. The app's summary panel watches
    /// the folder and reloads `summary.md` as soon as Claude writes it.
    ///
    /// Re-runs idempotently on each save: overwrites existing files so prompt
    /// edits in `prompts/summarize.md` propagate to existing meeting folders
    /// the next time the meeting is saved. Failures are swallowed by the
    /// caller — the workspace files are nice-to-have, not load-bearing.
    private static func writeClaudeWorkspace(at meetingDir: URL) throws {
        let commandsDir = meetingDir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)

        try claudeMdContent.write(
            to: meetingDir.appendingPathComponent("CLAUDE.md"),
            atomically: true,
            encoding: .utf8
        )
        try summarizeCommand.write(
            to: commandsDir.appendingPathComponent("summarize.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static let claudeMdContent: String = """
    # Meeting Workspace

    You are inside a recorded-meeting folder produced by MeetingScribe. The
    transcript is `transcript.md` (frontmatter + timestamped speaker segments).
    The MeetingScribe app reads `summary.md` from this folder and live-reloads
    it whenever it changes.

    ## When the user asks for a summary

    Run `/summarize` (defined in `.claude/commands/summarize.md`). It has the
    canonical prompt and output format. Always write the result to `summary.md`
    in this folder — the app picks it up automatically.

    ## Output rules

    - Write to `summary.md` (overwrite if it exists).
    - Use `- [ ]` checkboxes for action items (Notion-compatible).
    - Cite timestamps inline as `[HH:MM:SS]` from the transcript segments.
    - 300–500 words excluding action items.
    - Don't fabricate. If portions are `[inaudible]`, note that context may be
      missing.

    ## Templates

    If the user asks for a specific style (one-on-one, standup, retro, planning,
    lab meeting, seminar, interview, brainstorm), adapt accordingly: tighter
    structure, less narrative, more actionable bullets. Default style is the
    full structure shown in `/summarize`.
    """

    private static let summarizeCommand: String = """
    ---
    description: Summarize this meeting's transcript and write the result to summary.md
    ---

    Read `transcript.md` in the current directory and produce a structured,
    actionable meeting summary. Write the result to `summary.md` (overwrite if
    it exists).

    ## Output Format

    # Meeting Summary: [title from frontmatter]
    **Date**: [date from frontmatter]
    **Duration**: [duration from frontmatter]
    **Participants**: [participants from frontmatter]

    ## Executive Summary
    A 2-3 sentence overview of the meeting's purpose and most important outcome.

    ## Key Discussion Topics
    For each major topic discussed:
    - **[Topic Name]** — [Summary of what was discussed, who raised it, and the conclusion reached] **[HH:MM:SS]**

    ## Decisions Made
    - **[Decision]** — Proposed by [person]. [Any conditions or context]. **[HH:MM:SS]**

    ## Action Items
    Use checkbox format for Notion compatibility:
    - [ ] **[Specific task]** — Owner: **[person]** — Deadline: [date if mentioned, otherwise "TBD"]

    If ownership is unclear, mark as "Unassigned". Be specific about
    deliverables — "fix the login bug in auth service" not "fix the bug".

    ## Open Questions
    - [ ] [Unresolved question or topic deferred to future discussion]

    ## Next Steps
    Brief description of what happens after this meeting — follow-up meetings,
    deadlines, or milestones mentioned.

    ## Guidelines
    - 300–500 words excluding action items
    - Preserve speaker attributions — who said what matters
    - Use **bold** for names, deadlines, and critical information
    - Don't fabricate information not in the transcript
    - If portions are marked [inaudible], note that context may be missing
    - All action items MUST use `- [ ]` checkbox format
    - Quote 1-2 notable verbatim statements if they capture key sentiments
    - Include `[HH:MM:SS]` citations from the transcript segments — at least
      one per Key Discussion Topic and per Decision Made

    After writing `summary.md`, confirm to the user that the file was saved.
    The MeetingScribe app will reload it automatically.
    """

    /// Like `meetingDirectory`, but guarantees the returned URL does not already
    /// exist on disk — appending `-2`, `-3`, … when a meeting with the same
    /// title was already recorded on the same day.
    ///
    /// Call this once, when a recording *starts*. Without it, two meetings that
    /// share a title and a date resolve to the identical folder and the second
    /// silently overwrites the first's audio, transcript, and metadata.
    static func uniqueMeetingDirectory(title: String, date: Date, baseDirectory: String) -> URL {
        let candidate = meetingDirectory(title: title, date: date, baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let parent = candidate.deletingLastPathComponent()
        let stem = candidate.lastPathComponent
        var suffix = 2
        while true {
            let next = parent.appendingPathComponent("\(stem)-\(suffix)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            suffix += 1
        }
    }

    /// Move a recording's folder so its name reflects `title`, and return the
    /// folder to use from here on.
    ///
    /// A recording's folder is claimed when it *starts*, but the title can be
    /// edited while it runs (that is what the recording top bar is for). Without
    /// this reconciliation the audio stays behind in the start-time folder while
    /// the transcript and metadata are written to a folder named after the final
    /// title — leaving the audio orphaned in a directory the app cannot see.
    ///
    /// No-ops when the name is already correct, and never overwrites another
    /// meeting: a rename onto a taken name gets a `-2` suffix. Returns the
    /// original directory unchanged if the move fails, so callers always get a
    /// usable folder.
    static func reconcileMeetingDirectory(
        _ directory: URL,
        toTitle title: String,
        date: Date,
        baseDirectory: String
    ) -> URL {
        let desiredName = meetingDirectory(
            title: title, date: date, baseDirectory: baseDirectory
        ).lastPathComponent
        let currentName = directory.lastPathComponent

        if currentName == desiredName { return directory }

        // Already a `-2`/`-3` variant of this same title — keep the suffix
        // rather than fighting another meeting for the unsuffixed name.
        if currentName.hasPrefix(desiredName + "-"),
           Int(currentName.dropFirst(desiredName.count + 1)) != nil {
            return directory
        }

        let target = uniqueMeetingDirectory(
            title: title, date: date, baseDirectory: baseDirectory
        )
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: directory, to: target)
            return target
        } catch {
            return directory
        }
    }

    /// Get the organized directory for a meeting's files.
    ///
    /// Date components are computed with an explicit Gregorian calendar and a
    /// POSIX locale so folder names never shift with the user's region
    /// settings. (`Calendar.current` under a Japanese calendar would otherwise
    /// yield year `8`, and `MMMM` under `fr_FR` would yield `mars`.)
    static func meetingDirectory(title: String, date: Date, baseDirectory: String) -> URL {
        let expandedDir = NSString(string: baseDirectory).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expandedDir)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let year = calendar.component(.year, from: date)
        let day = calendar.component(.day, from: date)

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "MM-MMMM"
        let monthStr = monthFormatter.string(from: date)

        let dayStr = String(format: "%02d", day)

        // ~/MeetingScribe/2026/03-March/25-sprint-planning/
        return baseURL
            .appendingPathComponent("\(year)")
            .appendingPathComponent(monthStr)
            .appendingPathComponent("\(dayStr)-\(slug(title))")
    }

    /// Longest allowed byte length for a single path component on APFS/HFS+.
    private static let maxComponentBytes = 255

    /// Turn an arbitrary meeting title into a safe single path component.
    ///
    /// Collapses every run of non-alphanumeric characters into one hyphen, so
    /// separators, punctuation, newlines, and path traversal characters all
    /// become harmless. Unicode letters are preserved, so a Japanese or Greek
    /// title still produces a readable folder rather than `untitled`.
    static func slug(_ title: String) -> String {
        var out = ""
        var pendingHyphen = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen && !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }

        if out.isEmpty { return "untitled" }

        // Reserve room for the `DD-` prefix the caller prepends.
        let limit = maxComponentBytes - 3
        while out.utf8.count > limit { out.removeLast() }
        while out.hasSuffix("-") { out.removeLast() }

        return out.isEmpty ? "untitled" : out
    }
}
