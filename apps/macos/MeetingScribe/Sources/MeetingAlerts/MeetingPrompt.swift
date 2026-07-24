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
