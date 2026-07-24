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
