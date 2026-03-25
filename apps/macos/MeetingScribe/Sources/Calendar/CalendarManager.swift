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

    /// Find today's events: current, recent, and upcoming
    func fetchCurrentAndUpcoming() async {
        if !hasAccess {
            await requestAccess()
        }
        guard hasAccess else { return }

        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )

        // Deduplicate events that appear in multiple calendars (by title + start time)
        var seen = Set<String>()
        let ekEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate > $1.startDate } // Most recent first
            .filter { event in
                let key = "\(event.title ?? "")_\(event.startDate.timeIntervalSince1970)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }

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

        // All other events today (recent + upcoming, most recent first)
        upcomingEvents = events.filter { !$0.isHappeningNow }
    }

    /// Get the best suggestion for what meeting is happening
    var suggestedEvent: CalendarEvent? {
        currentEvent ?? upcomingEvents.first
    }
}
