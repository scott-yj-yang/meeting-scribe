import EventKit
import Foundation
import AppKit

@MainActor
class CalendarManager: ObservableObject {
    @Published var currentEvent: CalendarEvent?
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var accessDenied = false

    private nonisolated(unsafe) let store = EKEventStore()
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
            accessDenied = !hasAccess
        } catch {
            print("[Calendar] Access denied: \(error.localizedDescription)")
            hasAccess = false
            accessDenied = true
        }
    }

    func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

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

        var seen = Set<String>()
        let ekEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            // Drop events that have already ended — the picker should only
            // surface events that are happening now or still in the future.
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
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

        currentEvent = events.first { $0.isHappeningNow }
        upcomingEvents = events.filter { !$0.isHappeningNow }
    }

    var suggestedEvent: CalendarEvent? {
        currentEvent ?? upcomingEvents.first
    }
}
