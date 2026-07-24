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
