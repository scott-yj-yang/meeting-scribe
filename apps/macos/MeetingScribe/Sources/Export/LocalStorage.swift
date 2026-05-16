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

    /// Save transcript markdown and return the file URL
    static func save(markdown: String, title: String, date: Date, directory: String) throws -> URL {
        let meetingDir = meetingDirectory(title: title, date: date, baseDirectory: directory)
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

    /// Get the organized directory for a meeting's files
    static func meetingDirectory(title: String, date: Date, baseDirectory: String) -> URL {
        let expandedDir = NSString(string: baseDirectory).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expandedDir)

        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let day = calendar.component(.day, from: date)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MM-MMMM"
        let monthStr = monthFormatter.string(from: date)

        let safeTitle = title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()

        let dayStr = String(format: "%02d", day)

        // ~/MeetingScribe/2026/03-March/25-sprint-planning/
        return baseURL
            .appendingPathComponent("\(year)")
            .appendingPathComponent(monthStr)
            .appendingPathComponent("\(dayStr)-\(safeTitle)")
    }
}
