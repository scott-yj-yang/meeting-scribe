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
