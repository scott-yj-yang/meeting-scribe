# Proactive Meeting Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A floating panel that prompts the user to record when a calendar meeting is about to start or when they're in a Zoom call.

**Architecture:** A `MeetingMonitor` (one repeating timer) evaluates two pure detectors — calendar lead-time and Zoom window presence — and publishes a single `activePrompt`. A `FloatingPromptController` (NSPanel) shows a SwiftUI `MeetingPromptView` whose buttons join the call or start the scribe pre-filled from the event.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`), EventKit, ScreenCaptureKit-adjacent `CGWindowList`, swift-testing.

## Global Constraints

- Platform: macOS 14+; Swift 6 toolchain.
- No new system permissions beyond Calendar and Screen Recording (both already requested).
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`). Run the whole suite with `./scripts/test.sh` from the repo root (it selects the Xcode toolchain via `DEVELOPER_DIR`; the Command Line Tools cannot run tests).
- App builds from `apps/macos/MeetingScribe` with `swift build`.
- Pure logic (extraction, timing, window heuristics) is unit-tested; AppKit/EventKit/timer wiring is verified by build + manual.
- All new source under `Sources/MeetingAlerts/` and `Sources/Views/MeetingAlerts/`; tests under `Tests/MeetingAlerts/`.

---

### Task 1: ConferenceLink model + extractor

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/ConferenceLink.swift`
- Test: `apps/macos/MeetingScribe/Tests/MeetingAlerts/ConferenceLinkExtractorTests.swift`

**Interfaces:**
- Produces:
  - `enum ConferenceProvider: String, Equatable { case zoom, meet, teams, webex, generic }`
  - `struct ConferenceLink: Equatable { let url: URL; let provider: ConferenceProvider }`
  - `enum ConferenceLinkExtractor { static func extract(url: URL?, location: String?, notes: String?) -> ConferenceLink? }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAlerts/ConferenceLinkExtractorTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingScribe

@Suite("ConferenceLinkExtractor")
struct ConferenceLinkExtractorTests {

    @Test("extracts a Zoom link from the url field")
    func zoomFromURL() {
        let link = ConferenceLinkExtractor.extract(
            url: URL(string: "https://us02web.zoom.us/j/8412345678?pwd=abc"),
            location: nil, notes: nil
        )
        #expect(link?.provider == .zoom)
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/8412345678?pwd=abc")
    }

    @Test("extracts a Google Meet link from notes")
    func meetFromNotes() {
        let link = ConferenceLinkExtractor.extract(
            url: nil, location: nil,
            notes: "Join here: https://meet.google.com/abc-defg-hij thanks"
        )
        #expect(link?.provider == .meet)
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("extracts a Teams link from location")
    func teamsFromLocation() {
        let link = ConferenceLinkExtractor.extract(
            url: nil,
            location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x",
            notes: nil
        )
        #expect(link?.provider == .teams)
    }

    @Test("a known provider anywhere beats a generic link in an earlier field")
    func knownBeatsGeneric() {
        let link = ConferenceLinkExtractor.extract(
            url: URL(string: "https://example.com/agenda"),
            location: nil,
            notes: "call: https://us02web.zoom.us/j/999"
        )
        #expect(link?.provider == .zoom)
    }

    @Test("falls back to the first generic https link")
    func genericFallback() {
        let link = ConferenceLinkExtractor.extract(
            url: nil, location: "Room 4",
            notes: "dial in at https://meet.example.org/room/42"
        )
        #expect(link?.provider == .generic)
        #expect(link?.url.absoluteString == "https://meet.example.org/room/42")
    }

    @Test("returns nil when no link is present")
    func noLink() {
        #expect(ConferenceLinkExtractor.extract(url: nil, location: "Room 4", notes: "bring laptop") == nil)
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `./scripts/test.sh`
Expected: build fails / tests fail — `ConferenceLinkExtractor` is undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/MeetingAlerts/ConferenceLink.swift`:

```swift
import Foundation

enum ConferenceProvider: String, Equatable {
    case zoom, meet, teams, webex, generic
}

struct ConferenceLink: Equatable {
    let url: URL
    let provider: ConferenceProvider
}

/// Pulls a video-call join link out of an event's url / location / notes.
enum ConferenceLinkExtractor {

    private static let known: [(ConferenceProvider, String)] = [
        (.zoom,  #"https?://[A-Za-z0-9.-]*zoom\.us/[^\s<>"']+"#),
        (.meet,  #"https?://meet\.google\.com/[^\s<>"']+"#),
        (.teams, #"https?://teams\.(?:microsoft|live)\.com/[^\s<>"']+"#),
        (.webex, #"https?://[A-Za-z0-9.-]*webex\.com/[^\s<>"']+"#),
    ]
    private static let generic = #"https?://[^\s<>"']+"#

    static func extract(url: URL?, location: String?, notes: String?) -> ConferenceLink? {
        let fields = [url?.absoluteString, location, notes].compactMap { $0 }

        // Known providers win over a bare link, regardless of which field holds them.
        for field in fields {
            for (provider, pattern) in known {
                if let u = firstURL(pattern, in: field) {
                    return ConferenceLink(url: u, provider: provider)
                }
            }
        }
        for field in fields {
            if let u = firstURL(generic, in: field) {
                return ConferenceLink(url: u, provider: .generic)
            }
        }
        return nil
    }

    private static func firstURL(_ pattern: String, in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        // Trailing punctuation often clings to a URL pasted mid-sentence.
        let raw = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
        return URL(string: raw)
    }
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `./scripts/test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/ConferenceLink.swift apps/macos/MeetingScribe/Tests/MeetingAlerts/ConferenceLinkExtractorTests.swift
git commit -m "feat(alerts): extract conference join links from calendar events"
```

---

### Task 2: Attach conferenceLink to CalendarEvent

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/Calendar/CalendarManager.swift`

**Interfaces:**
- Consumes: `ConferenceLinkExtractor.extract` (Task 1).
- Produces: `CalendarManager.CalendarEvent.conferenceLink: ConferenceLink?`.

- [ ] **Step 1: Add the field to the struct**

In `CalendarManager.CalendarEvent`, add after `endDate`:

```swift
        let conferenceLink: ConferenceLink?
```

- [ ] **Step 2: Populate it at fetch time**

In `fetchCurrentAndUpcoming()`, change the `CalendarEvent(...)` construction to:

```swift
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                organizer: event.organizer?.name,
                attendees: event.attendees?.compactMap { $0.name } ?? [],
                startDate: event.startDate,
                endDate: event.endDate,
                conferenceLink: ConferenceLinkExtractor.extract(
                    url: event.url, location: event.location, notes: event.notes
                )
            )
```

- [ ] **Step 3: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete. (Any other `CalendarEvent(...)` initializer call sites must add `conferenceLink:`; search with `grep -rn "CalendarEvent(" Sources` and pass `conferenceLink: nil` where a test/preview constructs one.)

- [ ] **Step 4: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Calendar/CalendarManager.swift
git commit -m "feat(alerts): surface a conference link on each calendar event"
```

---

### Task 3: MeetingPrompt model

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingPrompt.swift`

**Interfaces:**
- Produces:
  - `struct MeetingPrompt: Identifiable, Equatable` with `id: String`, `kind: Kind` (`.upcomingEvent` | `.zoomMeeting`), `title: String`, `startDate: Date?`, `joinURL: URL?`, `calendarEventID: String?`.

- [ ] **Step 1: Write the file**

Create `Sources/MeetingAlerts/MeetingPrompt.swift`:

```swift
import Foundation

/// A single thing the floating panel is currently asking the user to do.
struct MeetingPrompt: Identifiable, Equatable {
    enum Kind: Equatable { case upcomingEvent, zoomMeeting }

    let id: String            // event id, or "zoom-meeting"
    let kind: Kind
    let title: String
    let startDate: Date?      // upcomingEvent only — drives the countdown
    let joinURL: URL?
    let calendarEventID: String?

    static func upcoming(_ event: CalendarManager.CalendarEvent) -> MeetingPrompt {
        MeetingPrompt(
            id: event.id, kind: .upcomingEvent, title: event.title,
            startDate: event.startDate, joinURL: event.conferenceLink?.url,
            calendarEventID: event.id
        )
    }

    static let zoom = MeetingPrompt(
        id: "zoom-meeting", kind: .zoomMeeting, title: "You're in a Zoom meeting",
        startDate: nil, joinURL: nil, calendarEventID: nil
    )
}
```

- [ ] **Step 2: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingPrompt.swift
git commit -m "feat(alerts): add MeetingPrompt model"
```

---

### Task 4: Calendar lead-time logic

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingAlertLogic.swift`
- Test: `apps/macos/MeetingScribe/Tests/MeetingAlerts/MeetingAlertLogicTests.swift`

**Interfaces:**
- Consumes: `CalendarManager.CalendarEvent` (Task 2).
- Produces: `enum MeetingAlertLogic { static func upcomingPrompt(events:now:leadTime:handledEventIDs:) -> CalendarManager.CalendarEvent? }`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAlerts/MeetingAlertLogicTests.swift`:

```swift
import Testing
import Foundation
@testable import MeetingScribe

@Suite("MeetingAlertLogic")
struct MeetingAlertLogicTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        id: String, startOffset: TimeInterval, durationMin: Double = 30, hasLink: Bool = true
    ) -> CalendarManager.CalendarEvent {
        CalendarManager.CalendarEvent(
            id: id, title: "Event \(id)", organizer: nil, attendees: [],
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(startOffset + durationMin * 60),
            conferenceLink: hasLink
                ? ConferenceLink(url: URL(string: "https://zoom.us/j/1")!, provider: .zoom)
                : nil
        )
    }

    @Test("prompts for an event starting within the lead time")
    func withinLead() {
        let e = event(id: "a", startOffset: 90) // 1.5 min out
        let picked = MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: [])
        #expect(picked?.id == "a")
    }

    @Test("does not prompt for an event beyond the lead time")
    func beyondLead() {
        let e = event(id: "a", startOffset: 600) // 10 min out
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: []) == nil)
    }

    @Test("still prompts for a meeting that just started")
    func justStarted() {
        let e = event(id: "a", startOffset: -120) // started 2 min ago
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: [])?.id == "a")
    }

    @Test("ignores events with no conference link")
    func noLinkIgnored() {
        let e = event(id: "a", startOffset: 60, hasLink: false)
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: []) == nil)
    }

    @Test("ignores already-handled events")
    func handledIgnored() {
        let e = event(id: "a", startOffset: 60)
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: ["a"]) == nil)
    }

    @Test("picks the soonest eligible event")
    func picksSoonest() {
        let a = event(id: "a", startOffset: 100)
        let b = event(id: "b", startOffset: 40)
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [a, b], now: now, leadTime: 120, handledEventIDs: [])?.id == "b")
    }

    @Test("ignores an event that has already ended")
    func endedIgnored() {
        let e = event(id: "a", startOffset: -3600, durationMin: 30) // ended 30 min ago
        #expect(MeetingAlertLogic.upcomingPrompt(
            events: [e], now: now, leadTime: 120, handledEventIDs: []) == nil)
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `./scripts/test.sh`
Expected: fails — `MeetingAlertLogic` undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/MeetingAlerts/MeetingAlertLogic.swift`:

```swift
import Foundation

enum MeetingAlertLogic {

    /// Grace window after start during which a just-begun meeting still prompts.
    private static let startedGrace: TimeInterval = 5 * 60

    static func upcomingPrompt(
        events: [CalendarManager.CalendarEvent],
        now: Date,
        leadTime: TimeInterval,
        handledEventIDs: Set<String>
    ) -> CalendarManager.CalendarEvent? {
        events
            .filter { $0.conferenceLink != nil }
            .filter { !handledEventIDs.contains($0.id) }
            .filter { $0.endDate > now }
            .filter { $0.startDate <= now.addingTimeInterval(leadTime) }
            .filter { $0.startDate >= now.addingTimeInterval(-startedGrace) }
            .min { $0.startDate < $1.startDate }
    }
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `./scripts/test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingAlertLogic.swift apps/macos/MeetingScribe/Tests/MeetingAlerts/MeetingAlertLogicTests.swift
git commit -m "feat(alerts): calendar lead-time prompt selection"
```

---

### Task 5: Zoom meeting detector

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/ZoomDetector.swift`
- Test: `apps/macos/MeetingScribe/Tests/MeetingAlerts/ZoomDetectorTests.swift`

**Interfaces:**
- Produces:
  - `struct WindowInfo: Equatable { let ownerName: String; let title: String }`
  - `enum ZoomDetector { static func isInMeeting(windows: [WindowInfo]) -> Bool; static func currentWindows() -> [WindowInfo]; static func zoomRunning() -> Bool; static func liveIsInMeeting() -> Bool }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MeetingAlerts/ZoomDetectorTests.swift`:

```swift
import Testing
@testable import MeetingScribe

@Suite("ZoomDetector")
struct ZoomDetectorTests {

    @Test("a Zoom meeting window counts as in-meeting")
    func meetingWindow() {
        #expect(ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom Meeting")
        ]))
    }

    @Test("the idle Zoom main window does not count")
    func idleWindow() {
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom Workplace")
        ]))
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "zoom.us", title: "Zoom")
        ]))
    }

    @Test("a browser tab named like a meeting does not count")
    func browserTab() {
        #expect(!ZoomDetector.isInMeeting(windows: [
            WindowInfo(ownerName: "Safari", title: "Zoom Meeting - Join")
        ]))
    }

    @Test("no windows means not in a meeting")
    func noWindows() {
        #expect(!ZoomDetector.isInMeeting(windows: []))
    }
}
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `./scripts/test.sh`
Expected: fails — `ZoomDetector` / `WindowInfo` undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/MeetingAlerts/ZoomDetector.swift`:

```swift
import AppKit
import CoreGraphics

struct WindowInfo: Equatable {
    let ownerName: String
    let title: String
}

/// Detects whether the user is in a Zoom *call* (not just running Zoom).
enum ZoomDetector {

    static func isInMeeting(windows: [WindowInfo]) -> Bool {
        windows.contains { w in
            w.ownerName.lowercased().contains("zoom")
                && w.title.lowercased().contains("meeting")
        }
    }

    /// On-screen windows via CGWindowList. Titles need Screen Recording
    /// permission (already held for system audio); without it, titles are empty
    /// and `isInMeeting` degrades to `false` — callers fall back to `zoomRunning`.
    static func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.map { dict in
            WindowInfo(
                ownerName: dict[kCGWindowOwnerName as String] as? String ?? "",
                title: dict[kCGWindowName as String] as? String ?? ""
            )
        }
    }

    static func zoomRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "us.zoom.xos" }
    }

    /// Live decision: prefer the precise window-title check; if titles are
    /// unavailable (no Screen Recording permission) fall back to "Zoom is
    /// running with an on-screen window".
    static func liveIsInMeeting() -> Bool {
        let windows = currentWindows()
        if isInMeeting(windows: windows) { return true }
        let titlesReadable = windows.contains { !$0.title.isEmpty }
        if titlesReadable { return false }
        return zoomRunning() && windows.contains { $0.ownerName.lowercased().contains("zoom") }
    }
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `./scripts/test.sh`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/ZoomDetector.swift apps/macos/MeetingScribe/Tests/MeetingAlerts/ZoomDetectorTests.swift
git commit -m "feat(alerts): detect an active Zoom meeting window"
```

---

### Task 6: MeetingMonitor

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingMonitor.swift`

**Interfaces:**
- Consumes: `CalendarManager`, `MeetingAlertLogic`, `ZoomDetector`, `MeetingPrompt`.
- Produces: `@MainActor final class MeetingMonitor: ObservableObject` with `@Published private(set) var activePrompt: MeetingPrompt?`, `weak var appState: AppState?`, `func start()`, `func stop()`, `func markHandled(_ prompt: MeetingPrompt)`, `func dismissActive()`.

- [ ] **Step 1: Write the file**

Create `Sources/MeetingAlerts/MeetingMonitor.swift`:

```swift
import Foundation
import SwiftUI

/// Watches the calendar and Zoom, and publishes at most one prompt at a time.
@MainActor
final class MeetingMonitor: ObservableObject {
    @Published private(set) var activePrompt: MeetingPrompt?

    weak var appState: AppState?

    @AppStorage("meetingAlertsEnabled") private var alertsEnabled = true
    @AppStorage("zoomDetectionEnabled") private var zoomEnabled = true
    @AppStorage("meetingAlertLeadMinutes") private var leadMinutes = 2

    private var timer: Timer?
    private var handledEventIDs = Set<String>()
    private var handledDay = Calendar.current.startOfDay(for: Date())
    private var zoomPromptActive = false

    private let calendar: CalendarManager

    init(calendar: CalendarManager) {
        self.calendar = calendar
    }

    func start() {
        stop()
        // Evaluate promptly, then on a cadence. 15s is frequent enough for a
        // 2-minute lead time and cheap (one EventKit query + one window scan).
        evaluateTick()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateTick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markHandled(_ prompt: MeetingPrompt) {
        if let id = prompt.calendarEventID { handledEventIDs.insert(id) }
        if prompt.kind == .zoomMeeting { zoomPromptActive = true }
        if activePrompt?.id == prompt.id { activePrompt = nil }
    }

    func dismissActive() {
        if let prompt = activePrompt { markHandled(prompt) }
        activePrompt = nil
    }

    private func evaluateTick() {
        rolloverDayIfNeeded()
        guard alertsEnabled else { activePrompt = nil; return }

        // Never interrupt an in-progress recording, and don't stack prompts.
        if appState?.isRecording == true { activePrompt = nil; return }
        if activePrompt != nil { return }

        Task { @MainActor in
            await calendar.fetchCurrentAndUpcoming()

            // Calendar prompts take priority over Zoom.
            let events = [calendar.currentEvent].compactMap { $0 } + calendar.upcomingEvents
            if let event = MeetingAlertLogic.upcomingPrompt(
                events: events, now: Date(),
                leadTime: TimeInterval(leadMinutes * 60),
                handledEventIDs: handledEventIDs
            ) {
                activePrompt = .upcoming(event)
                return
            }

            guard zoomEnabled else { return }
            let inMeeting = ZoomDetector.liveIsInMeeting()
            if !inMeeting { zoomPromptActive = false }
            if inMeeting && !zoomPromptActive {
                activePrompt = .zoom
            }
        }
    }

    private func rolloverDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != handledDay {
            handledDay = today
            handledEventIDs.removeAll()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete. (`AppState` reference resolves in Task 7; the file compiles now because `weak var appState: AppState?` only needs the type to exist, which it does.)

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/MeetingMonitor.swift
git commit -m "feat(alerts): MeetingMonitor drives calendar + Zoom prompts"
```

---

### Task 7: AppState integration

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/Models/AppState.swift`

**Interfaces:**
- Consumes: `MeetingMonitor`, `MeetingPrompt`.
- Produces: `AppState.meetingMonitor: MeetingMonitor`, `AppState.recordingSurfaceRequest: Int` (`@Published`), `func beginRecording(from prompt: MeetingPrompt)`.

- [ ] **Step 1: Add stored properties**

In `AppState`, near `let calendarManager = CalendarManager()`:

```swift
    let meetingMonitor: MeetingMonitor

    /// Bumped to ask the dashboard to come forward and enter recording mode
    /// (used when a recording is started from the floating meeting prompt).
    @Published var recordingSurfaceRequest = 0
```

In `init()`, after `meetingStore = ...`:

```swift
        meetingMonitor = MeetingMonitor(calendar: calendarManager)
        meetingMonitor.appState = self
        meetingMonitor.start()
```

(Move the `meetingMonitor` assignment so it follows `calendarManager`, which is a `let` initialized inline — it's available in `init`.)

- [ ] **Step 2: Add beginRecording(from:)**

Add near `toggleRecording()`:

```swift
    /// Start a recording from a floating meeting prompt: pre-fill the title,
    /// link the calendar event when there is one, bring the dashboard forward,
    /// and begin. No-op if a recording is already running.
    func beginRecording(from prompt: MeetingPrompt) {
        meetingMonitor.markHandled(prompt)
        guard !isRecording, !isStopping, !isFinalizingPreviousRecording else { return }

        meetingTitle = prompt.title == "You're in a Zoom meeting" ? "" : prompt.title
        if let id = prompt.calendarEventID {
            let events = [calendarManager.currentEvent].compactMap { $0 } + calendarManager.upcomingEvents
            selectedCalendarEvent = events.first { $0.id == id }
        }
        recordingSurfaceRequest &+= 1   // ask the dashboard to show recording mode
        toggleRecording()
    }
```

- [ ] **Step 3: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Models/AppState.swift
git commit -m "feat(alerts): AppState owns the monitor and starts recordings from prompts"
```

---

### Task 8: MeetingPromptView

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/Views/MeetingAlerts/MeetingPromptView.swift`

**Interfaces:**
- Consumes: `MeetingPrompt`.
- Produces: `struct MeetingPromptView: View` with `init(prompt:onStartRecording:onJoin:onDismiss:)`.

- [ ] **Step 1: Write the view**

Create `Sources/Views/MeetingAlerts/MeetingPromptView.swift`:

```swift
import SwiftUI

struct MeetingPromptView: View {
    let prompt: MeetingPrompt
    let onStartRecording: () -> Void
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: prompt.kind == .zoomMeeting ? "video.fill" : "calendar")
                    .foregroundStyle(.blue)
                Text(prompt.kind == .zoomMeeting ? "Meeting in progress" : "Meeting starting soon")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(prompt.title)
                .font(.system(.body, weight: .medium))
                .lineLimit(2)

            if let start = prompt.startDate {
                CountdownBar(target: start)
            }

            HStack(spacing: 8) {
                if prompt.joinURL != nil {
                    Button(action: onJoin) {
                        Label("Join", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: onStartRecording) {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}

/// A bar that shrinks toward `target`, with a "Starts in m:ss" label.
private struct CountdownBar: View {
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, target.timeIntervalSince(context.date))
            let window: TimeInterval = 120 // full bar at 2 min out
            let fraction = min(1, remaining / window)
            VStack(alignment: .leading, spacing: 4) {
                Text(remaining > 0 ? "Starts in \(Self.mmss(remaining))" : "Starting now")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.blue)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/Views/MeetingAlerts/MeetingPromptView.swift
git commit -m "feat(alerts): floating prompt view with countdown"
```

---

### Task 9: FloatingPromptController

**Files:**
- Create: `apps/macos/MeetingScribe/Sources/MeetingAlerts/FloatingPromptController.swift`

**Interfaces:**
- Consumes: `MeetingMonitor`, `MeetingPromptView`, `AppState`.
- Produces: `@MainActor final class FloatingPromptController` with `init(monitor:appState:)` and internal panel management.

- [ ] **Step 1: Write the controller**

Create `Sources/MeetingAlerts/FloatingPromptController.swift`:

```swift
import AppKit
import SwiftUI
import Combine

/// Owns the always-on-top NSPanel that shows the active meeting prompt.
@MainActor
final class FloatingPromptController {
    private let monitor: MeetingMonitor
    private weak var appState: AppState?
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    init(monitor: MeetingMonitor, appState: AppState) {
        self.monitor = monitor
        self.appState = appState
        cancellable = monitor.$activePrompt
            .receive(on: RunLoop.main)
            .sink { [weak self] prompt in self?.render(prompt) }
    }

    private func render(_ prompt: MeetingPrompt?) {
        guard let prompt else { close(); return }

        let view = MeetingPromptView(
            prompt: prompt,
            onStartRecording: { [weak self] in
                self?.appState?.beginRecording(from: prompt)
            },
            onJoin: { [weak self] in
                if let url = prompt.joinURL { NSWorkspace.shared.open(url) }
                // Joining isn't dismissing — leave the prompt so they can still
                // Start Recording. It clears when handled or the meeting passes.
                _ = self
            },
            onDismiss: { [weak self] in self?.monitor.dismissActive() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        positionTopRight(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let inset: CGFloat = 20
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - inset,
            y: visible.maxY - size.height - inset
        ))
    }
}
```

- [ ] **Step 2: Build**

Run: `cd apps/macos/MeetingScribe && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingAlerts/FloatingPromptController.swift
git commit -m "feat(alerts): floating NSPanel controller for meeting prompts"
```

---

### Task 10: App wiring, window surfacing, settings

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/MeetingScribeApp.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/Dashboard/NativeDashboard.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/Settings/SetupView.swift`

**Interfaces:**
- Consumes: `FloatingPromptController`, `AppState.recordingSurfaceRequest`.

- [ ] **Step 1: Create the controller and keep it alive**

In `MeetingScribeApp`, add a stored controller. Because `App` structs can't hold `@State` classes reliably across launches, use an `NSApplicationDelegateAdaptor`, or a `@State` optional set on appear. Simplest reliable option — a `@State` holder created in a `.task`:

Add to `MeetingScribeApp`:

```swift
    @State private var promptController: FloatingPromptController?
```

On the `MenuBarExtra`'s content, attach:

```swift
            MenuBarView()
                .environmentObject(appState)
                .task {
                    if promptController == nil {
                        promptController = FloatingPromptController(
                            monitor: appState.meetingMonitor, appState: appState
                        )
                    }
                }
```

- [ ] **Step 2: Surface the dashboard when a prompt starts a recording**

Also on the `MenuBarExtra` content (it's always alive), observe the surface request and open + activate the window:

```swift
                .onChange(of: appState.recordingSurfaceRequest) { _, _ in
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
```

Ensure `@Environment(\.openWindow) private var openWindow` exists on `MeetingScribeApp` (it does).

- [ ] **Step 3: Enter recording mode in the dashboard**

In `NativeDashboard`, add below the existing `.onChange(of: appState.meetingToOpen)`:

```swift
        .onChange(of: appState.recordingSurfaceRequest) { _, _ in
            showRecordingMode = true
        }
```

- [ ] **Step 4: Add settings**

In `SetupView`, add a new `Section` (after `Audio`):

```swift
            Section("Meeting Alerts") {
                Toggle("Show a prompt before calendar meetings and during Zoom calls",
                       isOn: $meetingAlertsEnabled)
                Stepper("Remind me \(leadMinutes) min before",
                        value: $leadMinutes, in: 1...10)
                    .disabled(!meetingAlertsEnabled)
                Toggle("Detect active Zoom meetings",
                       isOn: $zoomDetectionEnabled)
                    .disabled(!meetingAlertsEnabled)
            }
```

Add the backing storage at the top of `SetupView`:

```swift
    @AppStorage("meetingAlertsEnabled") private var meetingAlertsEnabled = true
    @AppStorage("zoomDetectionEnabled") private var zoomDetectionEnabled = true
    @AppStorage("meetingAlertLeadMinutes") private var leadMinutes = 2
```

- [ ] **Step 5: Build and run the full suite**

Run: `cd apps/macos/MeetingScribe && swift build` then `cd ../../.. && ./scripts/test.sh`
Expected: Build complete; all tests pass.

- [ ] **Step 6: Manual smoke test**

Run: `cd apps/macos/MeetingScribe && ./build-app.sh debug && open .build/arm64-apple-macosx/debug/MeetingScribe.app`
Verify: with a calendar event holding a Zoom link starting within 2 minutes, the panel appears top-right with a countdown; **Join** opens the link; **Start Recording** brings the dashboard forward and begins; joining a real Zoom call surfaces the Zoom prompt.

- [ ] **Step 7: Commit**

```bash
git add apps/macos/MeetingScribe/Sources/MeetingScribeApp.swift apps/macos/MeetingScribe/Sources/Views/Dashboard/NativeDashboard.swift apps/macos/MeetingScribe/Sources/Views/Settings/SetupView.swift
git commit -m "feat(alerts): wire the monitor, panel, window surfacing, and settings"
```

---

## Self-Review

**Spec coverage:** link extraction (T1), event link field (T2), prompt model (T3), lead-time logic (T4), Zoom detection (T5), monitor + de-dup + priority + suppress-while-recording (T6), start-recording hand-off + window surfacing (T7, T10), floating panel + countdown (T8, T9), settings + permissions reuse (T10). All spec sections map to a task.

**Placeholder scan:** no TBD/TODO; every code step has complete code.

**Type consistency:** `MeetingPrompt` fields, `ConferenceLink`, `WindowInfo`, `MeetingAlertLogic.upcomingPrompt`, `ZoomDetector.liveIsInMeeting`, `MeetingMonitor` API, and `AppState.beginRecording(from:)` / `recordingSurfaceRequest` are used consistently across tasks.
