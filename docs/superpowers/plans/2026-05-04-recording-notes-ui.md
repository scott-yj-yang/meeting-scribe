# Recording-time Note-Taking UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the cramped recording-phase notes editor in the macOS MeetingScribe app with a split workspace (notes + optional live transcript) featuring live-rendered markdown, a slash-command menu for structured callouts, and clickable transcript chunks that anchor `[m:ss]` timestamps into notes.

**Architecture:** A new `RecordingWorkspace` SwiftUI view composes a thin `RecordingTopBar`, an `NSViewRepresentable`-backed `MarkdownNotesEditor` (which applies attributes via a pure `MarkdownStyler` module on every text change and hosts a `SlashCommandMenu` popup), and a clickable `LiveTranscriptPane`. The transcript pane visibility is driven by the existing `appState.liveTranscriptEnabled` `@AppStorage` flag (default OFF). The current private `TranscriptionManager.savedChunks` tuple array is promoted to a `@Published [LiveTranscriptChunk]` so the pane can render chunks reactively.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSTextView`, `NSWindow` for the slash menu), Swift Testing (`import Testing`), `swift-markdown-ui` (already a dependency, used elsewhere in the app — not needed for this work).

**Reference spec:** `docs/superpowers/specs/2026-05-04-recording-notes-ui-design.md`

**Working directory for all `swift` commands:** `apps/macos/MeetingScribe/` (relative to repo root). Build the app with `./build-app.sh debug` from that directory.

---

## File map

**New files**
- `Sources/Transcription/LiveTranscriptChunk.swift` — value type, lives next to `TranscriptionManager`
- `Sources/Views/Recording/TimestampFormatter.swift` — pure helper, `TimeInterval → "m:ss"` / `"h:mm:ss"`
- `Sources/Views/Recording/MarkdownStyler.swift` — pure attribute applier
- `Sources/Views/Recording/MarkdownNotesEditor.swift` — `NSViewRepresentable` over `NSTextView`
- `Sources/Views/Recording/SlashCommand.swift` — enum with cases + insertion helpers
- `Sources/Views/Recording/SlashCommandMenu.swift` — popup UI
- `Sources/Views/Recording/LiveTranscriptPane.swift` — clickable transcript list
- `Sources/Views/Recording/RecordingTopBar.swift` — thin status strip
- `Sources/Views/Recording/RecordingWorkspace.swift` — composition view

**Modified files**
- `Sources/Transcription/TranscriptionManager.swift` — promote chunks to `@Published [LiveTranscriptChunk]`
- `Sources/Models/AppState.swift` — add `toggleLiveTranscript()` method
- `Sources/Views/Dashboard/RecordingModeView.swift` — replace inline `recordingPhase` body with `RecordingWorkspace`; delete the inline `notesEditor` helper

**Deleted files**
- `Sources/Views/Recording/LiveNotesPanel.swift` — currently unused; superseded by this design

**Test files (all new, all under `Tests/Recording/`)**
- `Tests/Recording/TimestampFormatterTests.swift`
- `Tests/Recording/MarkdownStylerTests.swift`
- `Tests/Recording/SlashCommandTests.swift`

---

### Task 1: TimestampFormatter — pure helper for `[m:ss]` and `[h:mm:ss]`

**Files:**
- Create: `Sources/Views/Recording/TimestampFormatter.swift`
- Test: `Tests/Recording/TimestampFormatterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/Recording/TimestampFormatterTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingScribe

@Suite("TimestampFormatter")
struct TimestampFormatterTests {

    @Test("formats sub-minute durations as 0:ss")
    func formatsSubMinute() {
        #expect(TimestampFormatter.format(0) == "0:00")
        #expect(TimestampFormatter.format(7) == "0:07")
        #expect(TimestampFormatter.format(42) == "0:42")
    }

    @Test("formats sub-hour durations as m:ss")
    func formatsSubHour() {
        #expect(TimestampFormatter.format(60) == "1:00")
        #expect(TimestampFormatter.format(75) == "1:15")
        #expect(TimestampFormatter.format(599) == "9:59")
        #expect(TimestampFormatter.format(600) == "10:00")
    }

    @Test("formats hour+ durations as h:mm:ss")
    func formatsHours() {
        #expect(TimestampFormatter.format(3600) == "1:00:00")
        #expect(TimestampFormatter.format(3725) == "1:02:05")
        #expect(TimestampFormatter.format(3725.7) == "1:02:05") // truncates
    }

    @Test("clamps negative values to 0:00")
    func clampsNegative() {
        #expect(TimestampFormatter.format(-3) == "0:00")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd apps/macos/MeetingScribe
swift test --filter TimestampFormatterTests
```

Expected: build error — `TimestampFormatter` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Views/Recording/TimestampFormatter.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/macos/MeetingScribe
swift test --filter TimestampFormatterTests
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/TimestampFormatter.swift apps/macos/MeetingScribe/Tests/Recording/TimestampFormatterTests.swift
git commit -m "feat(recording): TimestampFormatter for [m:ss] / [h:mm:ss] formatting"
```

---

### Task 2: LiveTranscriptChunk model

**Files:**
- Create: `Sources/Transcription/LiveTranscriptChunk.swift`

No tests — this is a pure value type. It will be exercised by `TranscriptionManager` changes in Task 3.

- [ ] **Step 1: Write the model**

Create `Sources/Transcription/LiveTranscriptChunk.swift`:

```swift
import Foundation

/// One finalized chunk from the live `SFSpeechRecognizer` session.
/// `TranscriptionManager` produces a stream of these as recognition sessions
/// finalize (~once per minute due to SFSpeechRecognizer's native session limit).
///
/// The in-flight (not-yet-finalized) text is exposed separately by
/// `TranscriptionManager.currentSessionText`; consumers that want the full
/// running text can read `liveText` (which already concatenates chunks +
/// in-flight text and is unchanged by this work).
struct LiveTranscriptChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Seconds since recording start when this chunk's session began.
    let startTime: TimeInterval
    /// Seconds since recording start when this chunk's session finalized.
    let endTime: TimeInterval

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd apps/macos/MeetingScribe
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriptChunk.swift
git commit -m "feat(transcription): add LiveTranscriptChunk model"
```

---

### Task 3: Promote `TranscriptionManager.savedChunks` to `@Published [LiveTranscriptChunk]`

**Files:**
- Modify: `Sources/Transcription/TranscriptionManager.swift`

Goal: expose the running list of finalized chunks as a published property so `LiveTranscriptPane` can render them reactively. Preserve all existing behavior (the chat panel system message reads `liveText`, which must remain unchanged).

- [ ] **Step 1: Read the current file**

Read `Sources/Transcription/TranscriptionManager.swift` end-to-end so you understand:
- `savedChunks: [(text: String, time: TimeInterval)]` is private, line ~16
- `saveCurrentSession()` (line ~140) is the only place chunks are appended
- `finalize()` (line ~92) iterates `savedChunks` to build segments using a running `lastEnd`
- `liveText` is `@Published` and is recomputed inside `saveCurrentSession()` and the recognizer callback

- [ ] **Step 2: Replace the private chunk storage**

Find and replace this declaration in `TranscriptionManager.swift`:

```swift
    // All saved text chunks (one per recognition session, ~1 min each)
    private var savedChunks: [(text: String, time: TimeInterval)] = []
```

with:

```swift
    /// All finalized chunks from past recognition sessions. Published so
    /// `LiveTranscriptPane` can render them reactively. Each chunk's
    /// `startTime` is the previous chunk's `endTime` (or 0 for the first).
    @Published private(set) var liveChunks: [LiveTranscriptChunk] = []
```

- [ ] **Step 3: Update `saveCurrentSession()` to append a `LiveTranscriptChunk`**

Find:

```swift
    private func saveCurrentSession() {
        let text = currentSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(recordingStartTime)
        savedChunks.append((text: text, time: elapsed))
        print("[Transcription] Saved chunk #\(savedChunks.count): \"\(text.prefix(100))\"")
        currentSessionText = ""
        // Recompute preview so it still reflects all saved chunks — do NOT wipe to "".
        // Wiping would leave mid-meeting chat with no transcript during the 300ms
        // restart window (and until the next partial result arrives).
        liveText = fullTranscriptPreview()
    }
```

Replace with:

```swift
    private func saveCurrentSession() {
        let text = currentSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(recordingStartTime)
        let startTime = liveChunks.last?.endTime ?? 0
        liveChunks.append(LiveTranscriptChunk(text: text, startTime: startTime, endTime: elapsed))
        print("[Transcription] Saved chunk #\(liveChunks.count): \"\(text.prefix(100))\"")
        currentSessionText = ""
        // Recompute preview so it still reflects all saved chunks — do NOT wipe to "".
        // Wiping would leave mid-meeting chat with no transcript during the 300ms
        // restart window (and until the next partial result arrives).
        liveText = fullTranscriptPreview()
    }
```

- [ ] **Step 4: Update `finalize()` to iterate `liveChunks`**

Find the loop in `finalize()`:

```swift
        var lastEnd: TimeInterval = 0
        for chunk in savedChunks {
            let segment = TranscriptSegment(
                speaker: "Speaker",
                text: chunk.text,
                startTime: lastEnd,
                endTime: chunk.time
            )
            segments.append(segment)
            lastEnd = chunk.time
        }

        print("[Transcription] Finalized \(segments.count) segments from \(savedChunks.count) chunks")
```

Replace with:

```swift
        for chunk in liveChunks {
            let segment = TranscriptSegment(
                speaker: "Speaker",
                text: chunk.text,
                startTime: chunk.startTime,
                endTime: chunk.endTime
            )
            segments.append(segment)
        }

        print("[Transcription] Finalized \(segments.count) segments from \(liveChunks.count) chunks")
```

- [ ] **Step 5: Update `setup()` and `reset()` to clear `liveChunks` instead of `savedChunks`**

In `setup()`, find and replace:

```swift
        savedChunks.removeAll()
```

with:

```swift
        liveChunks.removeAll()
```

In `reset()`, do the same replacement.

- [ ] **Step 6: Update `fullTranscriptPreview()` to read from `liveChunks`**

Find:

```swift
    private func fullTranscriptPreview() -> String {
        let saved = savedChunks.map(\.text).joined(separator: " ")
```

Replace with:

```swift
    private func fullTranscriptPreview() -> String {
        let saved = liveChunks.map(\.text).joined(separator: " ")
```

- [ ] **Step 7: Expose `currentSessionText` as published for the in-flight chunk**

The `LiveTranscriptPane` will render the in-flight (not-yet-finalized) text as a tentative trailing chunk. Find the declaration:

```swift
    private var currentSessionText: String = ""
```

Replace with:

```swift
    /// The current (not-yet-finalized) recognition session's cumulative text.
    /// Published so `LiveTranscriptPane` can render it as a tentative trailing
    /// chunk that updates live with partial results.
    @Published private(set) var currentSessionText: String = ""
```

- [ ] **Step 8: Verify the file builds and existing tests still pass**

```bash
cd apps/macos/MeetingScribe
swift build
swift test
```

Expected: build succeeds, all existing tests still pass (chat panel tests, etc.).

- [ ] **Step 9: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Transcription/TranscriptionManager.swift
git commit -m "refactor(transcription): publish liveChunks and currentSessionText"
```

---

### Task 4: MarkdownStyler — module skeleton + headings

**Files:**
- Create: `Sources/Views/Recording/MarkdownStyler.swift`
- Test: `Tests/Recording/MarkdownStylerTests.swift`

- [ ] **Step 1: Write the failing tests for headings**

Create `Tests/Recording/MarkdownStylerTests.swift`:

```swift
import Testing
import AppKit
@testable import MeetingScribe

@Suite("MarkdownStyler — headings")
struct MarkdownStylerHeadingTests {

    @Test("# heading produces 22pt bold attribute on the line")
    func h1HeadingStyled() {
        let storage = NSMutableAttributedString(string: "# Sprint plan")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == 22)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("## heading produces 18pt bold")
    func h2HeadingStyled() {
        let storage = NSMutableAttributedString(string: "## Subhead")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize == 18)
    }

    @Test("### heading produces 15pt bold")
    func h3HeadingStyled() {
        let storage = NSMutableAttributedString(string: "### Tertiary")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize == 15)
    }

    @Test("a # not at line start is not a heading")
    func midLineHashIsNotHeading() {
        let storage = NSMutableAttributedString(string: "issue #42 filed today")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize ?? 14 == 14) // body size, not heading
    }

    @Test("editing a heading line back to plain clears the heading style")
    func clearsHeadingStyleOnReapply() {
        let storage = NSMutableAttributedString(string: "# heading")
        MarkdownStyler.applyAttributes(to: storage)
        // Now the user removes the `#` — caller mutates the string and re-applies
        storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize ?? 14 == 14)
    }

    @Test("empty string does not crash")
    func emptyStringSafe() {
        let storage = NSMutableAttributedString(string: "")
        MarkdownStyler.applyAttributes(to: storage)
        // No assertion — just must not crash
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd apps/macos/MeetingScribe
swift test --filter MarkdownStylerHeadingTests
```

Expected: build error — `MarkdownStyler` is undefined.

- [ ] **Step 3: Implement the styler**

Create `Sources/Views/Recording/MarkdownStyler.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd apps/macos/MeetingScribe
swift test --filter MarkdownStylerHeadingTests
```

Expected: all heading tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownStyler.swift apps/macos/MeetingScribe/Tests/Recording/MarkdownStylerTests.swift
git commit -m "feat(recording): MarkdownStyler with heading rendering"
```

---

### Task 5: MarkdownStyler — inline patterns (bold, italic, code)

**Files:**
- Modify: `Sources/Views/Recording/MarkdownStyler.swift`
- Modify: `Tests/Recording/MarkdownStylerTests.swift`

- [ ] **Step 1: Add failing tests for inline patterns**

Append to `Tests/Recording/MarkdownStylerTests.swift`:

```swift
@Suite("MarkdownStyler — inline")
struct MarkdownStylerInlineTests {

    @Test("**bold** applies bold to the inner text")
    func boldApplied() {
        let storage = NSMutableAttributedString(string: "this is **bold** text")
        MarkdownStyler.applyAttributes(to: storage)
        // "**bold**" is at offset 8..16. The "bold" content is at 10..14.
        let attrs = storage.attributes(at: 11, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("*italic* applies italic to the inner text")
    func italicApplied() {
        let storage = NSMutableAttributedString(string: "an *italic* word")
        MarkdownStyler.applyAttributes(to: storage)
        // "*italic*" at 3..11; "italic" at 4..10
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("_italic_ also applies italic")
    func underscoreItalicApplied() {
        let storage = NSMutableAttributedString(string: "an _italic_ word")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("**bold** is not matched as italic")
    func boldNotItalic() {
        let storage = NSMutableAttributedString(string: "**bold**")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        // bold should be set; italic should NOT
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }

    @Test("`code` applies monospaced font")
    func codeApplied() {
        let storage = NSMutableAttributedString(string: "use `swift build` here")
        MarkdownStyler.applyAttributes(to: storage)
        // "`swift build`" at 4..17; content at 5..16
        let attrs = storage.attributes(at: 8, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.isFixedPitch == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter MarkdownStylerInlineTests
```

Expected: tests fail (no inline patterns implemented yet).

- [ ] **Step 3: Add inline pattern application to `MarkdownStyler`**

Add a private helper and a call from `applyAttributes`. Modify `Sources/Views/Recording/MarkdownStyler.swift`:

Find the method:

```swift
    private static func applyLineLevel(in lineRange: NSRange, storage: NSMutableAttributedString, nsString: NSString) {
        guard lineRange.length > 0 else { return }
        let lineText = nsString.substring(with: lineRange)
        if let level = headingLevel(of: lineText) {
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 15)
            let font = NSFont.boldSystemFont(ofSize: size)
            storage.addAttribute(.font, value: font, range: lineRange)
        }
    }
```

Replace with:

```swift
    private static func applyLineLevel(in lineRange: NSRange, storage: NSMutableAttributedString, nsString: NSString) {
        guard lineRange.length > 0 else { return }
        let lineText = nsString.substring(with: lineRange)
        if let level = headingLevel(of: lineText) {
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 15)
            let font = NSFont.boldSystemFont(ofSize: size)
            storage.addAttribute(.font, value: font, range: lineRange)
        }
        applyInline(in: lineRange, storage: storage, lineText: lineText)
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

    /// Runs a regex against `lineText` (which corresponds to the substring at `lineRange`)
    /// and calls `apply` with the *inner* (capture group 1) range translated back to the
    /// full storage range.
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter MarkdownStyler
```

Expected: all heading + inline tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownStyler.swift apps/macos/MeetingScribe/Tests/Recording/MarkdownStylerTests.swift
git commit -m "feat(recording): MarkdownStyler inline patterns (bold/italic/code)"
```

---

### Task 6: MarkdownStyler — line-start patterns (bullets, checkboxes, blockquote)

**Files:**
- Modify: `Sources/Views/Recording/MarkdownStyler.swift`
- Modify: `Tests/Recording/MarkdownStylerTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/Recording/MarkdownStylerTests.swift`:

```swift
@Suite("MarkdownStyler — line-start patterns")
struct MarkdownStylerLineStartTests {

    @Test("- bullet line gets head indent")
    func bulletIndent() {
        let storage = NSMutableAttributedString(string: "- item one")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(style != nil)
        #expect((style?.headIndent ?? 0) > 0)
    }

    @Test("[ ] empty checkbox is detected")
    func emptyCheckbox() {
        let storage = NSMutableAttributedString(string: "[ ] task")
        MarkdownStyler.applyAttributes(to: storage)
        // The checkbox marker should get an attachment color or attribute we can verify.
        // Implementation: we set a distinct foreground color (controlAccentColor) on the "[ ]" run.
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? NSColor
        #expect(color == NSColor.controlAccentColor)
    }

    @Test("[x] checked checkbox is detected")
    func checkedCheckbox() {
        let storage = NSMutableAttributedString(string: "[x] done")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? NSColor
        #expect(color == NSColor.systemGreen)
    }

    @Test("> blockquote line gets secondary color")
    func blockquoteColor() {
        let storage = NSMutableAttributedString(string: "> quoted text")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? NSColor
        #expect(color == NSColor.secondaryLabelColor)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter MarkdownStylerLineStartTests
```

Expected: failures on all four tests.

- [ ] **Step 3: Extend `applyLineLevel` with new patterns**

Modify `Sources/Views/Recording/MarkdownStyler.swift`. Find:

```swift
    private static func applyLineLevel(in lineRange: NSRange, storage: NSMutableAttributedString, nsString: NSString) {
        guard lineRange.length > 0 else { return }
        let lineText = nsString.substring(with: lineRange)
        if let level = headingLevel(of: lineText) {
            let size: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : 15)
            let font = NSFont.boldSystemFont(ofSize: size)
            storage.addAttribute(.font, value: font, range: lineRange)
        }
        applyInline(in: lineRange, storage: storage, lineText: lineText)
    }
```

Replace with:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter MarkdownStyler
```

Expected: all heading + inline + line-start tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownStyler.swift apps/macos/MeetingScribe/Tests/Recording/MarkdownStylerTests.swift
git commit -m "feat(recording): MarkdownStyler line-start patterns (bullets, checkboxes, blockquote)"
```

---

### Task 7: MarkdownStyler — callouts (action / decision / question / note)

**Files:**
- Modify: `Sources/Views/Recording/MarkdownStyler.swift`
- Modify: `Tests/Recording/MarkdownStylerTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/Recording/MarkdownStylerTests.swift`:

```swift
@Suite("MarkdownStyler — callouts")
struct MarkdownStylerCalloutTests {

    @Test("> [!action] line gets red chip background on the marker")
    func actionCallout() {
        let storage = NSMutableAttributedString(string: "> [!action] ship onboarding Friday")
        MarkdownStyler.applyAttributes(to: storage)
        // Marker "[!action]" is at indices 2..11
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let bg = attrs[.backgroundColor] as? NSColor
        #expect(bg == NSColor.systemRed.withAlphaComponent(0.15))
    }

    @Test("> [!decision] gets green chip")
    func decisionCallout() {
        let storage = NSMutableAttributedString(string: "> [!decision] approved")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let bg = attrs[.backgroundColor] as? NSColor
        #expect(bg == NSColor.systemGreen.withAlphaComponent(0.15))
    }

    @Test("> [!question] gets blue chip")
    func questionCallout() {
        let storage = NSMutableAttributedString(string: "> [!question] what about Q3?")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let bg = attrs[.backgroundColor] as? NSColor
        #expect(bg == NSColor.systemBlue.withAlphaComponent(0.15))
    }

    @Test("> [!note] gets gray chip")
    func noteCallout() {
        let storage = NSMutableAttributedString(string: "> [!note] reminder")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let bg = attrs[.backgroundColor] as? NSColor
        #expect(bg == NSColor.systemGray.withAlphaComponent(0.15))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter MarkdownStylerCalloutTests
```

Expected: 4 failures.

- [ ] **Step 3: Add callout handling to MarkdownStyler**

Modify `Sources/Views/Recording/MarkdownStyler.swift`. Find the blockquote branch in `applyLineLevel`:

```swift
        } else if lineText.hasPrefix("> ") {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
        }
```

Replace with:

```swift
        } else if lineText.hasPrefix("> ") {
            if let callout = calloutKind(of: lineText) {
                applyCallout(callout, lineRange: lineRange, lineText: lineText, storage: storage)
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            }
        }
```

Add these helpers below the existing line-start helpers:

```swift
    enum CalloutKind: String {
        case action, decision, question, note

        var color: NSColor {
            switch self {
            case .action: return .systemRed
            case .decision: return .systemGreen
            case .question: return .systemBlue
            case .note: return .systemGray
            }
        }
    }

    private static func calloutKind(of line: String) -> CalloutKind? {
        // Expect "> [!<kind>] <body>"
        guard line.hasPrefix("> [!") else { return nil }
        let afterPrefix = line.dropFirst(4) // after "> [!"
        guard let closeIdx = afterPrefix.firstIndex(of: "]") else { return nil }
        let kindString = String(afterPrefix[..<closeIdx])
        return CalloutKind(rawValue: kindString)
    }

    private static func applyCallout(_ kind: CalloutKind, lineRange: NSRange, lineText: String, storage: NSMutableAttributedString) {
        // Marker is "[!<kind>]" — locate within lineText.
        let nsLine = lineText as NSString
        let markerInLine = nsLine.range(of: "[!\(kind.rawValue)]")
        guard markerInLine.location != NSNotFound else { return }
        let markerInStorage = NSRange(location: lineRange.location + markerInLine.location, length: markerInLine.length)
        storage.addAttribute(.backgroundColor, value: kind.color.withAlphaComponent(0.15), range: markerInStorage)
        storage.addAttribute(.foregroundColor, value: kind.color, range: markerInStorage)

        // Body of the line gets a slight indent — apply paragraph style.
        let style = NSMutableParagraphStyle()
        style.headIndent = 12
        storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter MarkdownStyler
```

Expected: all MarkdownStyler tests pass (heading + inline + line-start + callout).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownStyler.swift apps/macos/MeetingScribe/Tests/Recording/MarkdownStylerTests.swift
git commit -m "feat(recording): MarkdownStyler callouts (action/decision/question/note)"
```

---

### Task 8: SlashCommand model + tests

**Files:**
- Create: `Sources/Views/Recording/SlashCommand.swift`
- Create: `Tests/Recording/SlashCommandTests.swift`

This task introduces the model + insertion logic. The popup UI is in Task 10.

- [ ] **Step 1: Write the failing tests**

Create `Tests/Recording/SlashCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingScribe

@Suite("SlashCommand")
struct SlashCommandTests {

    @Test("each command has the expected callout prefix")
    func calloutPrefixes() {
        #expect(SlashCommand.action.calloutPrefix == "> [!action] ")
        #expect(SlashCommand.decision.calloutPrefix == "> [!decision] ")
        #expect(SlashCommand.question.calloutPrefix == "> [!question] ")
        #expect(SlashCommand.note.calloutPrefix == "> [!note] ")
    }

    @Test("each command has a human-readable label")
    func labels() {
        #expect(SlashCommand.action.label == "Action")
        #expect(SlashCommand.decision.label == "Decision")
        #expect(SlashCommand.question.label == "Question")
        #expect(SlashCommand.note.label == "Note")
    }

    @Test("insertion replaces the trigger '/' and inserts the prefix at line start")
    func insertReplacesSlashAtLineStart() {
        // The user typed "/" at offset 0, so the buffer is "/" with caret at offset 1.
        let result = SlashCommand.action.applyInsertion(into: "/", triggerSlashLocation: 0)
        #expect(result.text == "> [!action] ")
        #expect(result.caretLocation == result.text.utf16.count)
    }

    @Test("insertion in the middle of an existing document replaces the / on the current line")
    func insertOnNonEmptyLine() {
        // Buffer: "earlier note\n/" — caret at the end (offset 14). Trigger / is at 13.
        let buffer = "earlier note\n/"
        let result = SlashCommand.decision.applyInsertion(into: buffer, triggerSlashLocation: 13)
        #expect(result.text == "earlier note\n> [!decision] ")
        #expect(result.caretLocation == result.text.utf16.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SlashCommandTests
```

Expected: build error — `SlashCommand` undefined.

- [ ] **Step 3: Implement the model**

Create `Sources/Views/Recording/SlashCommand.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter SlashCommandTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/SlashCommand.swift apps/macos/MeetingScribe/Tests/Recording/SlashCommandTests.swift
git commit -m "feat(recording): SlashCommand model with insertion logic"
```

---

### Task 9: MarkdownNotesEditor — basic NSViewRepresentable + binding (no styling, no slash menu yet)

**Files:**
- Create: `Sources/Views/Recording/MarkdownNotesEditor.swift`

This task wires up an `NSTextView` inside an `NSScrollView` with two-way binding. Styling and slash menu come in subsequent tasks.

No automated tests (NSViewRepresentable behavior requires AppKit instantiation; covered by manual test in the smoke-test task).

- [ ] **Step 1: Write the basic editor**

Create `Sources/Views/Recording/MarkdownNotesEditor.swift`:

```swift
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

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // External change — replace and preserve caret at end.
            textView.string = text
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
            // Write back to the binding asynchronously so we don't trigger
            // a re-entrant updateNSView during the same run loop tick.
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd apps/macos/MeetingScribe
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownNotesEditor.swift
git commit -m "feat(recording): MarkdownNotesEditor scaffold (binding only)"
```

---

### Task 10: Wire MarkdownStyler into MarkdownNotesEditor

**Files:**
- Modify: `Sources/Views/Recording/MarkdownNotesEditor.swift`

- [ ] **Step 1: Apply styling on text change and on initial load**

Modify `Sources/Views/Recording/MarkdownNotesEditor.swift`. Find:

```swift
        // Initial text load
        textView.string = text

        return scroll
```

Replace with:

```swift
        // Initial text load
        textView.string = text
        if let storage = textView.textStorage {
            MarkdownStyler.applyAttributes(to: storage)
        }

        return scroll
```

Find:

```swift
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // External change — replace and preserve caret at end.
            textView.string = text
        }
    }
```

Replace with:

```swift
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            // External change — replace and re-style.
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
        }
    }
```

Find the `textDidChange` method:

```swift
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Write back to the binding asynchronously so we don't trigger
            // a re-entrant updateNSView during the same run loop tick.
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
```

Replace with:

```swift
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Re-style first, *then* write back to the binding asynchronously
            // (so we don't trigger a re-entrant updateNSView during the same
            // run loop tick).
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
```

- [ ] **Step 2: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 3: Manual visual smoke test**

Build and run the app:

```bash
cd apps/macos/MeetingScribe
./build-app.sh debug
open .build/arm64-apple-macosx/debug/MeetingScribe.app
```

(Use `x86_64-apple-macosx` instead on Intel Macs.)

The app's recording UI is not yet wired to use this editor (Task 16 does that), so this step verifies build only — actual rendering is verified in the smoke test task.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownNotesEditor.swift
git commit -m "feat(recording): wire MarkdownStyler into MarkdownNotesEditor"
```

---

### Task 11: SlashCommandMenu UI + integrate trigger detection in editor coordinator

**Files:**
- Create: `Sources/Views/Recording/SlashCommandMenu.swift`
- Modify: `Sources/Views/Recording/MarkdownNotesEditor.swift`

The slash menu is a borderless `NSWindow` containing a small SwiftUI list. The editor coordinator detects `/` typed at a line start and shows the menu anchored to the caret.

- [ ] **Step 1: Create the menu view**

Create `Sources/Views/Recording/SlashCommandMenu.swift`:

```swift
import SwiftUI
import AppKit

/// Small popup window shown when the user types `/` at the start of a line
/// in `MarkdownNotesEditor`. Lists the four `SlashCommand` cases. Selection
/// dismisses the menu and inserts the callout prefix at the trigger location.
final class SlashCommandMenuController {
    private var window: NSWindow?
    private var onSelect: ((SlashCommand) -> Void)?
    private var onCancel: (() -> Void)?

    func show(anchoredTo screenPoint: NSPoint, onSelect: @escaping (SlashCommand) -> Void, onCancel: @escaping () -> Void) {
        dismiss()
        self.onSelect = onSelect
        self.onCancel = onCancel

        let content = SlashCommandMenuView(
            onSelect: { [weak self] command in
                self?.dismiss()
                onSelect(command)
            },
            onCancel: { [weak self] in
                self?.dismiss()
                onCancel()
            }
        )
        let host = NSHostingController(rootView: content)
        host.view.frame = NSRect(x: 0, y: 0, width: 220, height: 160)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.setFrameTopLeftPoint(screenPoint)
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct SlashCommandMenuView: View {
    let onSelect: (SlashCommand) -> Void
    let onCancel: () -> Void
    @State private var hoveredCommand: SlashCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSERT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(SlashCommand.allCases) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color(for: command)).frame(width: 8, height: 8)
                        Text(command.label).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(hoveredCommand == command ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredCommand = isHovered ? command : nil
                }
            }
        }
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .onExitCommand { onCancel() }
    }

    private func color(for command: SlashCommand) -> Color {
        switch command {
        case .action: return .red
        case .decision: return .green
        case .question: return .blue
        case .note: return .gray
        }
    }
}
```

- [ ] **Step 2: Wire the menu into `MarkdownNotesEditor`**

Modify `Sources/Views/Recording/MarkdownNotesEditor.swift`. Find the `Coordinator` class declaration and replace it with:

```swift
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownNotesEditor
        weak var textView: NSTextView?
        private let slashMenu = SlashCommandMenuController()
        private var pendingSlashLocation: Int?

        init(_ parent: MarkdownNotesEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            detectSlashTrigger(in: tv)
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }

        /// Detects when the user just typed `/` at the start of a line and shows the slash menu.
        private func detectSlashTrigger(in tv: NSTextView) {
            let selected = tv.selectedRange()
            guard selected.length == 0, selected.location > 0 else { return }
            let nsString = tv.string as NSString
            let charBefore = nsString.substring(with: NSRange(location: selected.location - 1, length: 1))
            guard charBefore == "/" else { return }
            // At line start? Either offset 0 or preceding char is newline.
            let triggerLocation = selected.location - 1
            let isLineStart: Bool = {
                if triggerLocation == 0 { return true }
                let prior = nsString.substring(with: NSRange(location: triggerLocation - 1, length: 1))
                return prior == "\n"
            }()
            guard isLineStart else { return }
            showSlashMenu(in: tv, triggerLocation: triggerLocation)
        }

        private func showSlashMenu(in tv: NSTextView, triggerLocation: Int) {
            pendingSlashLocation = triggerLocation
            // Convert text position to a screen point under the caret.
            guard let layoutManager = tv.layoutManager,
                  let textContainer = tv.textContainer else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: triggerLocation, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let inView = NSRect(
                x: rect.origin.x + tv.textContainerOrigin.x,
                y: rect.origin.y + tv.textContainerOrigin.y + rect.height + 2,
                width: rect.width, height: rect.height
            )
            let inWindow = tv.convert(inView, to: nil)
            guard let window = tv.window else { return }
            let onScreen = window.convertToScreen(inWindow)
            let topLeft = NSPoint(x: onScreen.origin.x, y: onScreen.origin.y)

            slashMenu.show(
                anchoredTo: topLeft,
                onSelect: { [weak self] command in
                    self?.applySlashCommand(command, in: tv)
                },
                onCancel: { [weak self] in
                    self?.pendingSlashLocation = nil
                }
            )
        }

        private func applySlashCommand(_ command: SlashCommand, in tv: NSTextView) {
            guard let location = pendingSlashLocation else { return }
            pendingSlashLocation = nil
            let result = command.applyInsertion(into: tv.string, triggerSlashLocation: location)
            tv.string = result.text
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            tv.setSelectedRange(NSRange(location: result.caretLocation, length: 0))
            // Push the binding update.
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
    }
```

- [ ] **Step 3: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/SlashCommandMenu.swift apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownNotesEditor.swift
git commit -m "feat(recording): SlashCommandMenu popup wired to notes editor"
```

---

### Task 12: LiveTranscriptPane — render chunks (no click yet)

**Files:**
- Create: `Sources/Views/Recording/LiveTranscriptPane.swift`

- [ ] **Step 1: Write the pane**

Create `Sources/Views/Recording/LiveTranscriptPane.swift`:

```swift
import SwiftUI

/// Read-only pane that renders the live transcript as a scrolling list of
/// chunks plus the in-flight (not-yet-finalized) text as a tentative
/// trailing chunk. Each chunk is **clickable** in Task 13 — for now this
/// renders the streaming view with empty/error states.
struct LiveTranscriptPane: View {
    @ObservedObject var transcriptionManager: TranscriptionManager
    let liveTranscriptError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 320)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = liveTranscriptError {
            errorView(error)
        } else if transcriptionManager.liveChunks.isEmpty && transcriptionManager.currentSessionText.isEmpty {
            listeningView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcriptionManager.liveChunks) { chunk in
                            chunkRow(chunk: chunk, isInFlight: false)
                                .id(chunk.id)
                        }
                        if !transcriptionManager.currentSessionText.isEmpty {
                            chunkRow(
                                text: transcriptionManager.currentSessionText,
                                timestampLabel: "now",
                                isInFlight: true
                            )
                            .id("in-flight")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: transcriptionManager.liveChunks.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("in-flight", anchor: .bottom)
                    }
                }
                .onChange(of: transcriptionManager.currentSessionText) { _, _ in
                    proxy.scrollTo("in-flight", anchor: .bottom)
                }
            }
        }
    }

    private func chunkRow(chunk: LiveTranscriptChunk, isInFlight: Bool) -> some View {
        chunkRow(text: chunk.text, timestampLabel: TimestampFormatter.format(chunk.startTime), isInFlight: isInFlight)
    }

    private func chunkRow(text: String, timestampLabel: String, isInFlight: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timestampLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 36, alignment: .trailing)
            Text(text)
                .font(.system(.body))
                .foregroundStyle(isInFlight ? .primary : .secondary)
                .opacity(isInFlight ? 1.0 : 0.85)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var listeningView: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "ear")
                    .foregroundStyle(.tertiary)
                Text("Listening… speak to see the live transcript here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Live transcript unavailable", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Recording continues; full transcript will appear after stop.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/LiveTranscriptPane.swift
git commit -m "feat(recording): LiveTranscriptPane rendering (no click yet)"
```

---

### Task 13: Click-to-anchor — make transcript chunks insert `[m:ss] ` into notes

**Files:**
- Modify: `Sources/Views/Recording/LiveTranscriptPane.swift`
- Modify: `Sources/Views/Recording/MarkdownNotesEditor.swift`

The pane exposes `onChunkClick: (LiveTranscriptChunk) -> Void`. The editor's coordinator gains an `insertAtCaret(_ string: String)` method that the workspace will wire up in Task 16.

- [ ] **Step 1: Add `onChunkClick` parameter to `LiveTranscriptPane`**

Modify `Sources/Views/Recording/LiveTranscriptPane.swift`. Find:

```swift
struct LiveTranscriptPane: View {
    @ObservedObject var transcriptionManager: TranscriptionManager
    let liveTranscriptError: String?
```

Replace with:

```swift
struct LiveTranscriptPane: View {
    @ObservedObject var transcriptionManager: TranscriptionManager
    let liveTranscriptError: String?
    let onChunkClick: (LiveTranscriptChunk) -> Void
```

Find the `chunkRow(chunk:isInFlight:)` method:

```swift
    private func chunkRow(chunk: LiveTranscriptChunk, isInFlight: Bool) -> some View {
        chunkRow(text: chunk.text, timestampLabel: TimestampFormatter.format(chunk.startTime), isInFlight: isInFlight)
    }
```

Replace with:

```swift
    private func chunkRow(chunk: LiveTranscriptChunk, isInFlight: Bool) -> some View {
        Button {
            onChunkClick(chunk)
        } label: {
            chunkRow(text: chunk.text, timestampLabel: TimestampFormatter.format(chunk.startTime), isInFlight: isInFlight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to insert [\(TimestampFormatter.format(chunk.startTime))] into notes")
    }
```

(The in-flight row stays non-clickable — its content is still streaming.)

- [ ] **Step 2: Add `insertAtCaret` to the notes editor coordinator**

Modify `Sources/Views/Recording/MarkdownNotesEditor.swift`. Find the `Coordinator` class and add this method inside it (anywhere before the closing brace):

```swift
        /// Public API for external views (e.g. `LiveTranscriptPane`) to insert
        /// text at the current caret position. Re-styles after the insert.
        func insertAtCaret(_ string: String) {
            guard let tv = textView else { return }
            let selected = tv.selectedRange()
            let nsString = tv.string as NSString
            let mutable = NSMutableString(string: nsString)
            mutable.replaceCharacters(in: selected, with: string)
            tv.string = mutable as String
            if let storage = tv.textStorage {
                MarkdownStyler.applyAttributes(to: storage)
            }
            let caret = selected.location + (string as NSString).length
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            tv.window?.makeFirstResponder(tv)
            let newText = tv.string
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = newText
            }
        }
```

- [ ] **Step 3: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/LiveTranscriptPane.swift apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownNotesEditor.swift
git commit -m "feat(recording): clickable transcript chunks + insertAtCaret coordinator API"
```

---

### Task 14: AppState — `toggleLiveTranscript()` method

**Files:**
- Modify: `Sources/Models/AppState.swift`

- [ ] **Step 1: Add the method**

Modify `Sources/Models/AppState.swift`. Find the existing `toggleLiveTranscriptCheck()` method (around line 88) and **add a new method below it** (do not modify the existing method):

```swift
    /// Toggles `liveTranscriptEnabled` and starts/stops the recognizer
    /// mid-recording. Called by the transcript-toggle button in
    /// `RecordingTopBar`.
    func toggleLiveTranscript() {
        liveTranscriptEnabled.toggle()
        guard isRecording else { return }
        if liveTranscriptEnabled {
            // Mirror openLiveChatPanel(): start the recognizer mid-recording.
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

- [ ] **Step 2: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Models/AppState.swift
git commit -m "feat(recording): AppState.toggleLiveTranscript()"
```

---

### Task 15: RecordingTopBar

**Files:**
- Create: `Sources/Views/Recording/RecordingTopBar.swift`

- [ ] **Step 1: Write the top bar**

Create `Sources/Views/Recording/RecordingTopBar.swift`:

```swift
import SwiftUI

/// Thin status strip shown above the notes editor during recording.
/// Replaces the loud "● Recording 0:42" + giant title + waveform stack of
/// the previous design with a slim single-line bar.
struct RecordingTopBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(formatDuration(appState.recordingDuration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            divider

            // Inline-editable title (de-emphasized)
            TextField("Untitled meeting", text: $appState.meetingTitle)
                .textFieldStyle(.plain)
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: 280, alignment: .leading)

            // Optional calendar event badge
            if let event = appState.selectedCalendarEvent {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text(event.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.blue.opacity(0.75))
            }

            Spacer()

            // Transcript toggle
            Button {
                appState.toggleLiveTranscript()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.liveTranscriptEnabled ? "text.alignleft" : "text.alignleft")
                    Text(appState.liveTranscriptEnabled ? "Transcript" : "Transcript")
                        .font(.caption.weight(.medium))
                    Text(appState.liveTranscriptEnabled ? "ON" : "OFF")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appState.liveTranscriptEnabled ? .blue : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(appState.liveTranscriptEnabled ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help(appState.liveTranscriptEnabled ? "Hide live transcript" : "Show live transcript")

            // Audio level dots
            audioLevelDots

            // Stop button — outline style, far from notes
            Button {
                appState.toggleRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.red)
                .overlay(
                    Capsule().stroke(Color.red, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 36)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 14)
    }

    private var audioLevelDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        let threshold = Float(index + 1) * 0.2
        return appState.audioLevel >= threshold ? .red : Color.secondary.opacity(0.25)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
swift build
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/RecordingTopBar.swift
git commit -m "feat(recording): RecordingTopBar with transcript toggle and de-emphasized stop"
```

---

### Task 16: RecordingWorkspace composition + integrate into RecordingModeView (delete LiveNotesPanel)

**Files:**
- Create: `Sources/Views/Recording/RecordingWorkspace.swift`
- Modify: `Sources/Views/Dashboard/RecordingModeView.swift`
- Delete: `Sources/Views/Recording/LiveNotesPanel.swift`

- [ ] **Step 1: Write the workspace**

Create `Sources/Views/Recording/RecordingWorkspace.swift`:

```swift
import SwiftUI

/// Top-level layout for the recording phase. Composes the top bar, notes
/// editor, and (when enabled) the live transcript pane. Replaces the inline
/// `recordingPhase` body that previously lived in `RecordingModeView`.
struct RecordingWorkspace: View {
    @EnvironmentObject var appState: AppState

    /// State holder used to pass the editor's coordinator out of the
    /// representable so external views (e.g. transcript pane click) can call
    /// `insertAtCaret(_:)` on it.
    @State private var notesEditorCoordinator: MarkdownNotesEditor.Coordinator?

    var body: some View {
        VStack(spacing: 0) {
            RecordingTopBar()
            HStack(spacing: 0) {
                MarkdownNotesEditor(text: $appState.meetingNotes, coordinatorRef: $notesEditorCoordinator)
                    .frame(maxWidth: .infinity)

                if appState.liveTranscriptEnabled && !appState.showLiveChatPanel {
                    Divider()
                    LiveTranscriptPane(
                        transcriptionManager: appState.transcriptionManager,
                        liveTranscriptError: appState.liveTranscriptError,
                        onChunkClick: { chunk in
                            let stamp = "[\(TimestampFormatter.format(chunk.startTime))] "
                            notesEditorCoordinator?.insertAtCaret(stamp)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.liveTranscriptEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.showLiveChatPanel)
        }
    }
}
```

- [ ] **Step 2: Add `coordinatorRef` to `MarkdownNotesEditor`**

Modify `Sources/Views/Recording/MarkdownNotesEditor.swift`. Find:

```swift
struct MarkdownNotesEditor: NSViewRepresentable {
    @Binding var text: String
```

Replace with:

```swift
struct MarkdownNotesEditor: NSViewRepresentable {
    @Binding var text: String
    /// Optional outbound binding so parents can hold a reference to the
    /// coordinator and call `insertAtCaret(_:)` from external views (e.g.
    /// the transcript pane click handler).
    var coordinatorRef: Binding<Coordinator?>? = nil
```

Find the `makeCoordinator()` method:

```swift
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
```

Replace with:

```swift
    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        DispatchQueue.main.async { [weak coord] in
            coordinatorRef?.wrappedValue = coord
        }
        return coord
    }
```

- [ ] **Step 3: Replace `recordingPhase` body in `RecordingModeView`**

Modify `Sources/Views/Dashboard/RecordingModeView.swift`. Find the `recordingPhase` computed property (~line 76-168) and replace it with:

```swift
    // MARK: - Phase 2: Recording

    private var recordingPhase: some View {
        HStack(spacing: 0) {
            RecordingWorkspace()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.showLiveChatPanel {
                Divider()
                liveChatPanelView
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.showLiveChatPanel)
        .overlay(alignment: .topTrailing) {
            if !appState.showLiveChatPanel {
                Button {
                    appState.openLiveChatPanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask AI")
                    }
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.blue))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .clickableHover(cornerRadius: 22)
                .padding(16)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
```

- [ ] **Step 4: Remove the now-unused `notesEditor` helper from `RecordingModeView`**

In `RecordingModeView.swift`, find the `private var notesEditor: some View` declaration (around line 411-429) and **delete it entirely**. The `preRecordingPhase` still references it — replace its single use site `notesEditor` (around line 55) with an inline copy:

Find in `preRecordingPhase`:

```swift
                // Notes area
                notesEditor
```

Replace with:

```swift
                // Notes area
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $appState.meetingNotes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)

                    if appState.meetingNotes.isEmpty {
                        Text("Add notes...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: 500, minHeight: 100, maxHeight: 200)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
```

(The pre-recording notes editor keeps its current plain `TextEditor` because the pre-recording phase is intentionally out of scope per the spec — only the *during recording* notes editor gets the markdown upgrade.)

- [ ] **Step 5: Delete `LiveNotesPanel.swift`**

```bash
git rm apps/macos/MeetingScribe/Sources/Views/Recording/LiveNotesPanel.swift
```

- [ ] **Step 6: Verify it builds**

```bash
swift build
```

Expected: success. If you get an error about `formatDuration` being unused in `RecordingModeView`, delete that helper from the file (it was used by the old `recordingPhase` only).

- [ ] **Step 7: Run the full test suite**

```bash
swift test
```

Expected: all existing + new tests pass.

- [ ] **Step 8: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/Recording/RecordingWorkspace.swift apps/macos/MeetingScribe/Sources/Views/Recording/MarkdownNotesEditor.swift apps/macos/MeetingScribe/Sources/Views/Dashboard/RecordingModeView.swift
git commit -m "feat(recording): wire RecordingWorkspace into recordingPhase, remove LiveNotesPanel"
```

---

### Task 17: Manual smoke test against the spec's test plan

**Files:** none modified — this is verification only.

- [ ] **Step 1: Build and launch the app**

```bash
cd apps/macos/MeetingScribe
./build-app.sh debug
open .build/arm64-apple-macosx/debug/MeetingScribe.app
```

- [ ] **Step 2: Walk through the 13-step manual test plan from the spec**

Reference: `docs/superpowers/specs/2026-05-04-recording-notes-ui-design.md` § "Manual test plan". Each step:

1. Recording phase shows focus mode (notes full width, transcript OFF). Top bar present, stop button top-right.
2. Type `# Meeting agenda` — heading renders 22pt bold immediately.
3. Type `**bold text**` — bold renders.
4. Type `- item one`, newline, `- item two` — bullet rendering applied.
5. Type `[ ] task` — checkbox marker is colored.
6. Type `/` at line start — slash menu appears. Pick "Action" — line becomes `> [!action] ` with red ACTION chip.
7. Toggle transcript ON. Right pane animates in. Speak briefly. Live text appears as clickable chunks with timestamps.
8. Click a transcript chunk — `[m:ss] ` is inserted at the notes caret; focus returns to the notes editor.
9. Toggle transcript OFF. Pane animates out, notes fills width. Recognizer stops (verify in Activity Monitor: CPU drop on the app).
10. Open AI chat panel. Transcript pane (if visible) hides; chat panel takes right side. Notes column does not jump width unexpectedly.
11. Close AI chat panel. Transcript pane returns if it was on.
12. Stop recording. Verify `~/MeetingScribe/<year>/<month>/<slug>/notes.md` saved with the markdown content (raw text including any `> [!action]` callouts and `[0:42]` timestamps, not attributed). Verify whisper transcription runs and saves `transcript.md`.
13. Re-open the meeting from the dashboard. `meetingNotes` reload correctly into the styled editor (markdown rendering applied on load, callouts re-render as chips).

- [ ] **Step 3: If any step fails**

File the failure as a fix-up task, fix it, then re-run that step. Keep iterating until all 13 pass.

- [ ] **Step 4: Final commit (if any small fixes were needed during smoke test)**

If smoke testing surfaced fixes, commit them with descriptive messages. If everything passed cleanly, no commit is needed for this task.

---

## Self-review checklist

This section is a record of the spec→plan coverage check; the engineer doesn't need to act on it.

| Spec requirement | Implemented in task |
|---|---|
| `RecordingWorkspace.swift` | Task 16 |
| `RecordingTopBar.swift` | Task 15 |
| `MarkdownNotesEditor.swift` | Tasks 9, 10, 11, 13, 16 |
| `MarkdownStyler.swift` | Tasks 4, 5, 6, 7 |
| `SlashCommandMenu.swift` + `SlashCommand.swift` | Tasks 8, 11 |
| `LiveTranscriptPane.swift` | Tasks 12, 13 |
| `LiveTranscriptChunk.swift` | Task 2 |
| `TranscriptionManager` `@Published [LiveTranscriptChunk]` | Task 3 |
| `AppState.toggleLiveTranscript()` | Task 14 |
| `RecordingModeView` integration | Task 16 |
| Delete `LiveNotesPanel.swift` | Task 16 |
| Markdown patterns: headings, bold, italic, code | Tasks 4, 5 |
| Markdown patterns: bullets, checkboxes, blockquote | Task 6 |
| Markdown patterns: callouts | Task 7 |
| Slash menu trigger detection (line start only) | Task 11 |
| Slash menu insertion replaces `/` with prefix | Tasks 8, 11 |
| Click-to-anchor `[m:ss] ` insertion | Task 13 |
| Toggle stops recognizer + hides pane | Tasks 14, 16 |
| Transcript pane empty / listening / error states | Task 12 |
| Default `liveTranscriptEnabled = OFF` | (already in `AppState.swift:36`, no change needed) |
| AI chat panel coexistence | Task 16 |
| 5-dot audio-level indicator | Task 15 |
| De-emphasized stop button (top-right) | Task 15 |
| Inline-editable, less-prominent title | Task 15 |
| Unit tests `MarkdownStylerTests` | Tasks 4, 5, 6, 7 |
| Unit tests `SlashCommandTests` (insertion) | Task 8 |
| Unit tests `TimestampFormatterTests` | Task 1 |
| Manual test plan execution | Task 17 |
