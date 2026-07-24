# Proactive Meeting Alerts — Design

**Date:** 2026-07-24
**Status:** Approved, ready for planning
**Component:** macOS app (`apps/macos/MeetingScribe`)

## Overview

Surface a floating prompt that nudges the user to record at the right moment,
in two situations:

1. **Calendar countdown** — a calendar event with a video-call link is about to
   start (default: within 2 minutes). The prompt shows the title, a live
   countdown, a **Join** button (opens the call link), and **Start Recording**
   (starts the scribe pre-filled from the event).
2. **Zoom meeting detected** — the user is actually in a Zoom call (a Zoom
   *meeting* window is on screen). The prompt offers **Start Recording**.

Both render in the same always-on-top floating panel, driven by one monitor.

## Goals

- Prompt proactively without the user opening the app.
- One click to join, one click to start recording with the event's title and
  the calendar event linked.
- No new system permissions beyond what the app already uses (Calendar, Screen
  Recording).

## Non-goals (YAGNI)

- Google Meet / Teams *detection* (their links are still extracted and shown as
  Join targets for the calendar prompt; only Zoom gets running-meeting
  detection).
- Auto-starting a recording without the user clicking. Always ask.
- Notifications, Focus/DND integration, or snoozing beyond a simple Dismiss.
- Detecting meeting end to auto-stop recording.

## Architecture

```
CalendarManager ──events──▶ MeetingMonitor ──activePrompt──▶ FloatingPromptController
ZoomDetector    ──state───▶     (timer)                         (NSPanel + SwiftUI)
                                    │                                  │
                                    └── de-dup / lead-time logic       └─ MeetingPromptView
                                                                              │ Join / Start / Dismiss
                                                                              ▼
                                                                          AppState (start recording)
```

- **`MeetingMonitor`** is the brain: a `@MainActor ObservableObject` with a
  single repeating timer (~15 s) that evaluates both detectors and publishes at
  most one `activePrompt`.
- **`FloatingPromptController`** is the presentation layer: an `NSObject` that
  observes `MeetingMonitor.$activePrompt` and shows/hides an `NSPanel`.
- Detection *decisions* live in pure functions so they can be tested without a
  clock, EventKit, or the window server.

## Data models

```swift
enum ConferenceProvider: String { case zoom, meet, teams, webex, generic }

struct ConferenceLink: Equatable {
    let url: URL
    let provider: ConferenceProvider
}

struct MeetingPrompt: Identifiable, Equatable {
    enum Kind: Equatable { case upcomingEvent, zoomMeeting }
    let id: String              // event id, or "zoom-meeting"
    let kind: Kind
    let title: String
    let startDate: Date?        // present for upcomingEvent (drives countdown)
    let joinURL: URL?           // present when a link was found
    let calendarEventID: String?
}
```

`CalendarManager.CalendarEvent` gains one field: `conferenceLink: ConferenceLink?`,
populated at fetch time.

## Detection logic

### Conference link extraction (`ConferenceLinkExtractor`)

Pure function:

```swift
static func extract(url: URL?, location: String?, notes: String?) -> ConferenceLink?
```

Scans, in order, the EKEvent's `url`, `location`, then `notes` for the first
recognized pattern:

- Zoom: `https://*.zoom.us/j/<id>` (and `/w/`, `/my/`)
- Meet: `https://meet.google.com/<abc-defg-hij>`
- Teams: `https://teams.microsoft.com/l/meetup-join/...`
- Webex: `https://*.webex.com/...`
- Otherwise the first `https://` URL in those fields → `.generic`.

Returns the URL plus provider, or `nil`.

### Calendar countdown (`MeetingAlertLogic.upcomingPrompt`)

Pure function:

```swift
static func upcomingPrompt(
    events: [CalendarManager.CalendarEvent],
    now: Date,
    leadTime: TimeInterval,
    handledEventIDs: Set<String>
) -> CalendarManager.CalendarEvent?
```

Returns the soonest event where **all** hold: has a `conferenceLink`; hasn't
already ended; `startDate` is within `now ... now + leadTime` **or** already
started but ≤ 5 min ago (so a just-started meeting still prompts); id not in
`handledEventIDs`. `nil` otherwise.

### Zoom meeting detection (`ZoomDetector`)

Pure function over an injected window snapshot:

```swift
struct WindowInfo { let ownerName: String; let title: String }
static func isInMeeting(windows: [WindowInfo]) -> Bool
```

`true` when any window's owner is Zoom (`zoom.us` / `us.zoom.xos`) **and** its
title indicates a call (contains "Zoom Meeting", or "Meeting" without being the
main "Zoom"/"Zoom Workplace" window).

Live layer `ZoomDetector.currentWindows()` builds `[WindowInfo]` from
`CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`. Window
**titles** are readable because the app holds Screen Recording permission
(already required for system audio). If titles come back empty (permission not
granted), fall back to: Zoom is running (via `NSWorkspace.runningApplications`,
bundle id `us.zoom.xos`) **and** has any on-screen window → treated as a weaker
"in meeting" signal.

### De-duplication (in `MeetingMonitor`)

- `handledEventIDs: Set<String>` — an event id is added when the user acts on or
  dismisses its prompt, so it never re-fires. Cleared daily (ids are per-day).
- `zoomPromptActive: Bool` — Zoom prompts once on the transition into a meeting;
  reset when `isInMeeting` returns to false, so leaving and rejoining prompts
  again.
- Never prompt while `appState.isRecording` is true, or while a prompt of any
  kind is already showing.
- Calendar prompts take priority over Zoom when both fire in the same tick.

## Floating panel

`FloatingPromptController`:
- Creates a borderless `NSPanel`: `.nonactivatingPanel`, level `.floating`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, ignores
  activation so it never steals focus from the call.
- Positions it top-right of the active screen with an inset.
- Hosts `MeetingPromptView` via `NSHostingView`.
- Subscribes to `monitor.$activePrompt`: non-nil → order front (fade in); nil →
  close.

`MeetingPromptView` (SwiftUI, fixed width ~320):
- **upcomingEvent:** provider icon + title; "Starts in m:ss" with a bar that
  shrinks toward `startDate` (driven by `TimelineView(.periodic)`); **Join**
  (if `joinURL`), **Start Recording**, and a small **Dismiss** (✕).
- **zoomMeeting:** "You're in a Zoom meeting" + **Start Recording** + Dismiss.
- Theme-aware, uses `.regularMaterial` background, matches existing app styling.

## Start-recording integration

`MeetingPrompt` → recording:

- Add `AppState.beginRecording(from prompt: MeetingPrompt)`:
  - Sets `meetingTitle` from the prompt title (unless already recording).
  - For `upcomingEvent`, sets `selectedCalendarEvent` to the matching event so
    the recording is linked to it.
  - Brings the dashboard window forward and enters recording mode (via a new
    `@Published var recordingSurfaceRequest` signal that the dashboard scene
    observes to `openWindow("dashboard")` + set `showRecordingMode = true`), then
    calls `toggleRecording()`.
  - Marks the prompt handled so it won't reappear.
- **Join** opens `joinURL` with `NSWorkspace.shared.open`.
- **Dismiss** marks the prompt handled and clears `activePrompt`.

The window-surfacing observer lives in the always-alive `MenuBarExtra` scene so
it works even when the dashboard window is closed.

## Settings & permissions

New **Meeting Alerts** section (in the existing Settings `SetupView` or a small
dedicated pane):
- Master toggle `meetingAlertsEnabled` (default on).
- Lead-time stepper `meetingAlertLeadMinutes` (1–10, default 2).
- Zoom-detection toggle `zoomDetectionEnabled` (default on).

Stored via `@AppStorage`. `MeetingMonitor` reads them each tick.

Permissions: Calendar and Screen Recording only — both already requested
elsewhere. No Accessibility grant. If Screen Recording isn't granted, Zoom
detection degrades (see above) but calendar alerts still work.

## Testing

Unit-tested pure logic (no clock/EventKit/window server):
- `ConferenceLinkExtractor.extract` — Zoom/Meet/Teams/Webex/generic across
  url/location/notes fields; ordering; no-match → nil.
- `MeetingAlertLogic.upcomingPrompt` — within/outside lead time; just-started
  window; no-link excluded; handled-id excluded; picks soonest.
- `ZoomDetector.isInMeeting` — meeting window vs idle Zoom window vs no Zoom.

Integration (build + manual): the `NSPanel` presentation, the live
`CGWindowList` scan, and the start-recording hand-off.

## File layout

```
Sources/
  MeetingAlerts/
    ConferenceLink.swift            // model + extractor
    MeetingPrompt.swift             // model
    MeetingAlertLogic.swift         // upcomingPrompt
    ZoomDetector.swift              // WindowInfo + isInMeeting + live scan
    MeetingMonitor.swift            // timer, de-dup, publishes activePrompt
    FloatingPromptController.swift  // NSPanel management
  Views/MeetingAlerts/
    MeetingPromptView.swift         // SwiftUI panel content
Tests/
  MeetingAlerts/
    ConferenceLinkExtractorTests.swift
    MeetingAlertLogicTests.swift
    ZoomDetectorTests.swift
```

`CalendarManager.CalendarEvent` gains `conferenceLink`; `AppState` gains
`beginRecording(from:)`, `recordingSurfaceRequest`, and owns the
`MeetingMonitor`; `MeetingScribeApp` wires the `FloatingPromptController` and the
window-surfacing observer.
