import EventKit
import Foundation

/// Queries the user's calendar for current/upcoming meetings
/// to auto-suggest what the recording is about.
@MainActor
class CalendarManager: ObservableObject {
    @Published var currentEvent: CalendarEvent?
    @Published var upcomingEvents: [CalendarEvent] = []

    private let store = EKEventStore()
    private var hasAccess = false

    struct CalendarEvent: Identifiable {
        let id: String
        let title: String
        let organizer: String?
        let attendees: [String]
        let startDate: Date
        let endDate: Date

        var isHappeningNow: Bool {
            let now = Date()
            return startDate <= now && endDate >= now
        }
    }

    func requestAccess() async {
        do {
            hasAccess = try await store.requestFullAccessToEvents()
        } catch {
            print("[Calendar] Access denied: \(error.localizedDescription)")
            hasAccess = false
        }
    }

    /// Find events happening now or starting in the next 15 minutes
    func fetchCurrentAndUpcoming() async {
        if !hasAccess {
            await requestAccess()
        }
        guard hasAccess else { return }

        let now = Date()
        let soon = now.addingTimeInterval(15 * 60) // 15 minutes from now
        let endWindow = now.addingTimeInterval(2 * 60 * 60) // 2 hours from now

        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60 * 60), // Started up to 1 hour ago
            end: endWindow,
            calendars: nil
        )

        let ekEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay } // Skip all-day events
            .sorted { $0.startDate < $1.startDate }

        let events = ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                organizer: event.organizer?.name,
                attendees: event.attendees?.compactMap { $0.name } ?? [],
                startDate: event.startDate,
                endDate: event.endDate
            )
        }

        // Currently happening event
        currentEvent = events.first { $0.isHappeningNow }

        // Upcoming events (starting within 15 min)
        upcomingEvents = events.filter {
            !$0.isHappeningNow && $0.startDate <= soon
        }
    }

    /// Get the best suggestion for what meeting is happening
    var suggestedEvent: CalendarEvent? {
        currentEvent ?? upcomingEvents.first
    }
}
