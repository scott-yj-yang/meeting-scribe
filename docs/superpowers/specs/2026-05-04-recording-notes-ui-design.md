# Recording-time Note-Taking UI — Design Spec

**Date:** 2026-05-04
**Status:** Approved
**Scope:** Redesign the in-meeting recording UI in the macOS app to make note-taking feel natural, with live markdown rendering, an optional live-transcript companion pane, click-to-anchor transcript timestamps, and slash-command structure tagging.

---

## Goal

Replace the current cramped, distracting note-taking surface in `RecordingModeView`'s recording phase with a layout that puts notes at the center of attention, supports live markdown rendering, and lets the user optionally see a live transcript alongside their notes.

## Problem

The current recording phase (`apps/macos/MeetingScribe/Sources/Views/Dashboard/RecordingModeView.swift:76-168`) renders, top-to-bottom in a centered 500px column:

1. Loud `● Recording 0:42` status row
2. Large editable title field (28pt bold rounded)
3. Calendar event badge
4. Waveform bars
5. Notes editor — plain `TextEditor`, max 500×200, `.body` font, no markdown support
6. Large red "Stop Recording" button immediately below the notes editor

This produces five concrete pain points (validated by the user):

| # | Pain | Cause |
|---|---|---|
| 1 | Cramped notes | Notes box capped at 200pt height; squeezed further when AI chat panel (380pt) is open |
| 2 | No quick structure | Plain text only; no bullets, headers, checkboxes, or callouts |
| 3 | UI competes for attention | Loud title, waveform, calendar badge, prominent stop button all stack vertically |
| 4 | Risky stop placement | Stop button sits right below the editor — easy to misclick while typing fast |
| 5 | Notes are an island | No connection to live transcript or AI chat context |

The user also explicitly requested **live markdown rendering** (Bear/Obsidian Live Preview style — syntax characters remain visible, but formatting renders as you type).

## Approach: split workspace with transcript toggle

A single layout with two states, controlled by one toggle:

- **Transcript ON** — split workspace: notes on the left, live transcript on the right.
- **Transcript OFF** — focus mode: notes fill the full width.

The toggle binds to the existing `appState.liveTranscriptEnabled` `@AppStorage` setting. One toggle = one decision: it both starts/stops the speech recognizer (CPU savings) and shows/hides the right pane.

**Default: transcript OFF** (matches the existing `@AppStorage` default in `AppState.swift:36`, motivated by ~1 CPU core cost and inconsistent on-device speech quality). First-launch users see focus mode; users who flip the toggle get split mode and their preference persists.

### Why not Approach A (focus only) or Approach C (three-zone)?

- **A** doesn't address pain #5 (notes are an island); the user explicitly flagged this.
- **C** (slash commands, ticker, AI sidebar, transcript) is 2-3 weeks of additional scope. Better staged as a follow-up; pieces of it are listed as Phase 2 below.

---

## Architecture

### File map

**New files** (`apps/macos/MeetingScribe/Sources/Views/Recording/`):

- `RecordingWorkspace.swift` — top-level container for the recording phase. Composes top bar + notes editor + optional transcript pane. Replaces the inline `recordingPhase` body in `RecordingModeView`.
- `RecordingTopBar.swift` — thin status strip (red dot, timer, inline-editable title, transcript toggle, audio-level dots, de-emphasized stop button).
- `MarkdownNotesEditor.swift` — `NSViewRepresentable` wrapping `NSTextView`. Two-way binding to `appState.meetingNotes`. Hosts the slash-command menu.
- `MarkdownStyler.swift` — pure-Swift module that, given a string, returns the attribute ranges to apply. Separated from `MarkdownNotesEditor` to be unit-testable.
- `SlashCommandMenu.swift` — small `NSWindow`-anchored popup shown when the user types `/` at a line start in the notes editor. Lists action / decision / question / note. Insertion is delegated back to the editor.
- `LiveTranscriptPane.swift` — auto-scrolling, **clickable** list view of transcript chunks. Shows empty/error/streaming states.
- `LiveTranscriptChunk.swift` — small value type `(id: UUID, text: String, startTime: TimeInterval, endTime: TimeInterval)`. Promotes the existing private `(text, time)` tuple in `TranscriptionManager.savedChunks` into a typed model.

**Modified files:**

- `RecordingModeView.swift` — `recordingPhase` becomes a thin shell that places `RecordingWorkspace(...)` and keeps the existing `liveChatPanelView` overlay + floating "Ask AI" button untouched.
- `TranscriptionManager.swift` — promote `savedChunks` from a private `[(text, time)]` tuple array to a `@Published [LiveTranscriptChunk]` (renamed `liveChunks`). Each chunk gets a `startTime` derived from the previous chunk's end (currently `lastEnd`). The cumulative `liveText` derivation (`fullTranscriptPreview()`) stays unchanged for backward compatibility with the chat panel system message.

**Deleted file:**

- `Sources/Views/Recording/LiveNotesPanel.swift` — currently unused; this design supersedes it.

### Component responsibilities

#### `RecordingWorkspace`

Top-level layout for the recording phase. Owns the split between notes pane and transcript pane (when visible).

- Reads from `EnvironmentObject AppState`.
- Renders `RecordingTopBar` at the top.
- Below: `HStack` of `MarkdownNotesEditor` (always visible) and `LiveTranscriptPane` (when `appState.liveTranscriptEnabled`).
- When `appState.showLiveChatPanel` is true, the transcript pane is hidden in this view (the chat panel already takes the right side via the overlay in `RecordingModeView`).
- Animates pane appearance/disappearance with `.easeInOut(duration: 0.2)`.

#### `RecordingTopBar`

Thin status strip. Background: subtle elevation (`Color(.windowBackgroundColor)` with rounded corners, light shadow).

Left to right:
- Red recording dot (8×8) + duration `HH:MM:SS` in monospaced font
- Vertical separator
- Inline-editable title (`TextField` with `.plain` style, `.callout` weight medium, no border) — *muted* compared to current 28pt bold
- Calendar event badge (existing rendering, scaled down to caption size)
- `Spacer()`
- Transcript toggle button (icon `text.alignleft` + label "Transcript ON/OFF", filled tint when ON)
- Audio-level dots (compact horizontal indicator derived from `appState.audioLevel`, replaces the standalone `WaveformBars`)
- Stop button — outline style with red tint (`Color.red`), `.borderless` button, label `Stop`. Smaller than current `.controlSize(.large)` prominent button. Placement: top-right corner, far from the notes editor.

#### `MarkdownNotesEditor`

`NSViewRepresentable` wrapping a configured `NSTextView` inside an `NSScrollView`.

- Bindings: `@Binding var text: String`.
- `NSTextView` configuration:
  - `isRichText = false` (we manage attributes ourselves; user-pasted styles are stripped)
  - `usesFindBar = true`, `usesFontPanel = false`
  - Text container insets: `(top: 16, left: 20, bottom: 16, right: 20)` for breathing room
  - Default font: `NSFont.systemFont(ofSize: 14)` (or honor user's system text size)
  - Background: clear; let parent set color
- `Coordinator` implements `NSTextViewDelegate`:
  - On `textDidChange`: write back to the binding **on the main run loop** to coalesce rapid keystrokes (e.g. via `DispatchQueue.main.async`)
  - After binding update, call `MarkdownStyler.applyAttributes(to: textStorage)` which re-applies attributes to the entire storage (the document is small enough — meeting notes — that full-rescan is fine)
  - Place caret correctly across attribute updates (NSTextView preserves selection across `setAttributes`)
  - Detects `/` typed at a line start (caret is at the beginning of a line and the inserted character is `/`): show `SlashCommandMenu` anchored under the caret. Esc dismisses; arrow keys navigate; Return/Enter inserts.
- `updateNSView`: when the binding changes from outside (e.g. notes loaded from a meeting), set `string` and re-style.

#### `SlashCommandMenu`

Lightweight popup (an `NSWindow` of style `.utilityWindow` or an overlay `NSViewController` — implementer's choice; both are simple) shown by `MarkdownNotesEditor` when `/` is typed at a line start.

- Items: **Action**, **Decision**, **Question**, **Note**.
- Selecting an item:
  - Removes the typed `/` from the text storage.
  - Inserts a callout-style line at the caret: e.g. `> [!action] ` for Action, `> [!decision] ` for Decision, etc. (Markdown blockquote with a Notion-style callout marker.)
  - Caret ends positioned after the marker, ready for content.
- The blockquote-callout shape means raw markdown remains valid and the saved `notes.md` stays human-readable. `MarkdownStyler` recognizes the `[!action]` etc. tags and renders them as colored chips at the start of the line.

Inline-style markdown means: the syntax characters (`**`, `#`, `-`) **remain visible** but the affected text gets the matching style. Easier to implement, simpler caret behavior, and gives the user a visible "what markdown am I writing" cue. (Hide-syntax editors like Notion are deferred — they add caret-positioning complexity that's not worth Phase 1.)

#### `MarkdownStyler`

Pure-Swift module, no AppKit imports. Operates on `NSMutableAttributedString` (the `NSTextStorage`).

```swift
enum MarkdownStyler {
    static func applyAttributes(to storage: NSMutableAttributedString)
}
```

Patterns supported in Phase 1:

| Pattern | Style |
|---|---|
| `# heading` (line start) | font 22pt bold |
| `## heading` | font 18pt bold |
| `### heading` | font 15pt bold |
| `**bold**` (inline) | bold |
| `*italic*` or `_italic_` | italic |
| `- item` / `* item` (line start) | bullet renders as • via attribute, or just leave the dash + indent |
| `[ ]` (line start) | render as ☐ glyph |
| `[x]` (line start) | render as ☑ glyph |
| `> quote` (line start) | left border indent + secondary color |
| `` `code` `` | monospaced font, subtle background highlight |
| `> [!action] text` (line start) | "ACTION" red chip + indented body |
| `> [!decision] text` | "DECISION" green chip + indented body |
| `> [!question] text` | "QUESTION" blue chip + indented body |
| `> [!note] text` | "NOTE" gray chip + indented body |

Implementation: enumerate lines; for each line, apply line-level attributes; then run inline regex passes over the line range. Reset attributes at the start of each apply pass to avoid stale styles on edited text.

#### `LiveTranscriptPane`

Auto-scrolling list of `[LiveTranscriptChunk]` from `transcriptionManager.liveChunks`, with the in-flight current-session text appended as a "tentative" trailing chunk. Each chunk is **clickable**.

Layout:
- Header: `LIVE TRANSCRIPT` small-caps label + pulsing red dot.
- Body: a `ScrollViewReader`-anchored `LazyVStack` of chunk rows. Auto-scroll to the bottom whenever a new chunk lands.
- Each chunk row: timestamp pill (e.g. `0:42`) + chunk text. Older chunks fade to ~70% opacity. The trailing in-flight chunk has a subtle pulsing highlight.
- Empty state (`liveChunks.isEmpty && currentSessionText.isEmpty`): "Listening… speak to see the live transcript here."
- Error state (`appState.liveTranscriptError != nil`): "Live transcript unavailable: <message>. Recording continues; full transcript will appear after stop."

Click behavior:
- Clicking a chunk inserts `[m:ss] ` at the current caret position in `MarkdownNotesEditor`. The format uses the chunk's `startTime` rounded to seconds (e.g. `[0:42] `).
- Implementation: the pane exposes an `onChunkClick: (LiveTranscriptChunk) -> Void` closure, which `RecordingWorkspace` wires to a method on the notes editor's coordinator that inserts text at caret and re-styles.
- The notes editor focus follows the click — caret moves into the notes pane after the timestamp is inserted, so the user can immediately type their note.

The pane reads chunks directly from `transcriptionManager.liveChunks` (`@Published`) and `transcriptionManager.currentSessionText` (already `@Published` via the existing `liveText` derivation; we'll either expose it directly or keep it private and re-derive). It does not own any state.

### Data flow

| State | Source | Direction | Consumer |
|---|---|---|---|
| `meetingNotes` | `appState.meetingNotes` (@Published) | RW | `MarkdownNotesEditor` |
| `liveChunks` | `transcriptionManager.liveChunks` (@Published) | R | `LiveTranscriptPane` |
| `currentSessionText` | `transcriptionManager` (@Published) | R | `LiveTranscriptPane` (in-flight chunk) |
| `liveText` | `transcriptionManager.liveText` (@Published, derived) | R | `MeetingChatPanel` (system message) — unchanged |
| `liveTranscriptEnabled` | `appState.liveTranscriptEnabled` (@AppStorage) | RW | toggle button + pane visibility |
| `liveTranscriptActive` | `appState` (@Published) | R | toggle button visual state |
| `liveTranscriptError` | `appState.liveTranscriptError` | R | `LiveTranscriptPane` error state |
| `recordingDuration` | `appState.recordingDuration` | R | `RecordingTopBar` timer |
| `audioLevel` | `appState.audioLevel` | R | `RecordingTopBar` level dots |
| `meetingTitle` | `appState.meetingTitle` | RW | `RecordingTopBar` title field |
| `selectedCalendarEvent` | `appState.selectedCalendarEvent` | R | `RecordingTopBar` badge |

### Toggle behavior mid-recording

The toggle action in `RecordingTopBar` calls a new method `appState.toggleLiveTranscript()` (added to `AppState`):

```swift
@MainActor
func toggleLiveTranscript() {
    liveTranscriptEnabled.toggle()
    guard isRecording else { return }
    if liveTranscriptEnabled {
        // Mirror the path in openLiveChatPanel(): start the recognizer mid-recording
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.transcriptionManager.setup()
                self.liveTranscriptActive = true
                self.liveTranscriptError = nil
            } catch {
                self.liveTranscriptActive = false
                self.liveTranscriptError = error.localizedDescription
            }
        }
    } else {
        transcriptionManager.reset()
        liveTranscriptActive = false
        liveTranscriptError = nil
    }
}
```

The existing `enableLiveTranscriptTemporarily()` / `disableLiveTranscript()` (used for the pre-recording audio check, `AppState.swift:88-115`) are unrelated and remain unchanged.

---

## Error handling

| Scenario | Behavior |
|---|---|
| Speech permission denied or recognizer unavailable on toggle ON | `liveTranscriptError` set; pane shows error state with one-line explanation. Recording is unaffected. |
| Recognizer mid-restart (300ms gap, existing behavior) | `liveText` preview keeps prior chunks; pane continues to show last-known text. No special UI needed. |
| User toggles transcript OFF mid-recording | Recognizer is reset (CPU released). `liveText` cleared. Pane animates out. Whisper post-recording transcription still runs on stop (uses recorded audio, not the live recognizer). |
| User toggles transcript ON mid-recording without prior setup | New recognizer session starts; pane appears in "Listening…" state until first partial result. |
| `NSTextView` initialization fails | Not expected; AppKit is reliable. No fallback. |

---

## Visual / UX details

- **Top bar height:** ~36pt. Slim, single-line.
- **Stop button:** outline style, `.borderless`, red tint, no fill. ≥80pt of horizontal distance from the notes editor caret area at all times.
- **Title field:** inline `.plain` `TextField`, `.callout` weight medium. No more 28pt-bold-rounded.
- **Notes pane padding:** generous (16-20pt). The notes editor is the visual hero.
- **Transcript pane:** ≥320pt min width, equal width to notes when both visible. When window narrows, both shrink proportionally; below a min total width (~720pt) the transcript pane auto-hides with a tooltip "Window too narrow for transcript pane."
- **AI chat panel interaction:** when the user opens the AI chat panel (existing button), `RecordingWorkspace` hides the transcript pane temporarily so the chat panel takes the right side. Closing the chat panel restores the transcript pane if `liveTranscriptEnabled` is true.
- **Animations:** pane show/hide uses `.easeInOut(duration: 0.2)`. Title font transitions are not animated.

---

## Scope

### In scope

- All new files listed above.
- Markdown live rendering for the patterns in the table (including the four callout chips).
- Transcript toggle wired to `liveTranscriptEnabled` with mid-recording start/stop.
- Clickable transcript chunks → insert `[m:ss] ` timestamp anchor at the notes caret.
- Slash-command menu (`/`) → insert `> [!action]` / `> [!decision]` / `> [!question]` / `> [!note]` callouts.
- Empty / listening / error states for the transcript pane.
- Promote `TranscriptionManager.savedChunks` to `@Published [LiveTranscriptChunk]`.
- Removal of `LiveNotesPanel.swift` and the inline `notesEditor` body in `RecordingModeView`.
- Unit tests for `MarkdownStyler` and the slash-command insertion / timestamp-insertion logic.
- Manual test plan documented (below).

### Out of scope (intentional)

- **Hide-syntax markdown editor** (Notion-style) — alternative design choice, not an additional feature.
- **Extending SFSpeechRecognizer past native session limits** — already handled by the rolling `savedChunks` buffer; not user-visible.
- **AI chat awareness of notes** — already done; `MeetingContextBuilder` passes `appState.meetingNotes` into the chat system message (`RecordingModeView.swift:224`).
- **Custom waveform in the top bar** — cosmetic; the 5-dot level indicator is sufficient.

### Pre-recording phase

Out of scope. The pre-recording phase (`preRecordingPhase` in `RecordingModeView`) keeps its current layout — calendar picker, meeting type pills, large title, notes preview, big start button. Only the **recording phase** is redesigned here. (Intentional: the loud title and big start button serve their purpose pre-recording; they're only problematic *during* a meeting.)

---

## Testing

### Unit tests

`Tests/Recording/MarkdownStylerTests.swift`:

- Heading patterns at line start produce expected font-size attribute on the heading text range.
- Inline `**bold**` in middle of a paragraph applies bold attribute only to the bracketed range (not to the `**` markers, though they remain visible).
- `*italic*` does not match `**bold**` (precedence handled).
- Bulleted list line gets list-paragraph attributes; nested levels (two spaces of indent) increment indent.
- Checkbox glyphs render: `[ ]` → ☐, `[x]` → ☑.
- Callout markers `> [!action] body` apply chip background + body indent; the four callout types map to the right colors.
- Editing a previously-styled line (e.g. removing a `#`) clears the heading attribute on that line.
- Empty string, single newline, very long lines all return without crashing.

`Tests/Recording/SlashCommandInsertionTests.swift`:

- Selecting "Action" from the menu replaces the typed `/` with `> [!action] ` and positions the caret after the marker.
- Esc dismisses the menu without modifying the text.
- Typing `/` mid-line (not at line start) does not open the menu.

`Tests/Recording/TimestampInsertionTests.swift`:

- A click on a chunk with `startTime = 42.3` inserts the literal `[0:42] ` at the notes caret.
- A click on a chunk with `startTime = 3725.0` inserts `[1:02:05] ` (HH:MM:SS format for >1h meetings).
- Multiple clicks each insert at the current caret position; existing notes content is preserved.

### Manual test plan

1. Launch app. Recording phase shows focus mode (notes full width, transcript OFF). Pass: top bar present, stop button top-right.
2. Type `# Meeting agenda` — heading renders 22pt bold immediately.
3. Type `**bold text**` — bold renders.
4. Type `- item one\n- item two` — bullet rendering applied.
5. Type `[ ] task` — checkbox glyph appears.
6. Type `/` at line start — slash menu appears. Pick "Action" — line becomes `> [!action] ` with red ACTION chip.
7. Toggle transcript ON. Right pane animates in. Speak briefly. Live text appears as clickable chunks with timestamps.
8. Click a transcript chunk — `[m:ss] ` is inserted at the notes caret; focus returns to the notes editor.
9. Toggle transcript OFF. Pane animates out, notes fills width. Recognizer stops (verify in Activity Monitor: CPU drop on the app).
10. Open AI chat panel. Transcript pane (if visible) hides; chat panel takes right side. Notes column does not jump width unexpectedly.
11. Close AI chat panel. Transcript pane returns if it was on.
12. Stop recording. Verify `notes.md` saved with the markdown content (raw text including any `> [!action]` callouts and `[0:42]` timestamps, not attributed). Verify whisper transcription runs and saves `transcript.md`.
13. Re-open the meeting from the dashboard. `meetingNotes` reload correctly into the styled editor (markdown rendering applied on load, callouts re-render as chips).

### Existing tests must still pass

The Swift Package's existing tests under `Tests/` (LLM, Storage, Permissions, Notion, Chat) are not directly affected by this work. Run `swift test` from `apps/macos/MeetingScribe/` and confirm green.

---

## Non-goals

- Rich-text formatting beyond markdown (no font picker, no color, no images).
- Collaborative editing.
- Replacing `whisper.cpp` post-processing — the live transcript is a *preview*, not a substitute for the canonical post-recording transcript.
- Changing the post-recording phase or the dashboard meeting list.

## Resolved decisions

- **Default = OFF** for `liveTranscriptEnabled`. First-launch shows focus mode; users opt into split mode. Persists via `@AppStorage`.
- **Title remains editable mid-recording**, but visually de-emphasized (smaller, lighter font in the top bar).
- **5-dot audio-level indicator** in the top bar, not a waveform.

---

*This is the design spec. The implementation plan (file-level steps, ordering, dependencies) will be produced by the writing-plans skill in the next step.*
