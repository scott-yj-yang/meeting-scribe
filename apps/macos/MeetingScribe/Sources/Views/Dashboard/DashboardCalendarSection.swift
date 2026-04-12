import SwiftUI

struct DashboardCalendarSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Section {
            if let suggested = appState.calendarManager.suggestedEvent {
                suggestedEventRow(suggested)
            }

            if !appState.calendarManager.upcomingEvents.isEmpty {
                DisclosureGroup("Today's meetings (\(appState.calendarManager.upcomingEvents.count))") {
                    ForEach(appState.calendarManager.upcomingEvents) { event in
                        eventRow(event)
                    }
                }
            }

            if appState.calendarManager.accessDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Calendar access required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Grant") {
                        appState.calendarManager.openCalendarSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
        } header: {
            Label("Calendar", systemImage: "calendar")
        }
    }

    private func suggestedEventRow(_ event: CalendarManager.CalendarEvent) -> some View {
        Button {
            toggleSelection(event)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.isHappeningNow ? Color.red : Color.blue)
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.isHappeningNow ? "Happening now" : "Starting soon")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(event.isHappeningNow ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundStyle(event.isHappeningNow ? .red : .blue)
                        .cornerRadius(3)

                    Text(event.title)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formatTimeRange(event))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !event.attendees.isEmpty {
                            Text("\(event.attendees.count) attendee\(event.attendees.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: isSelected(event) ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(isSelected(event) ? .blue : .secondary)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ event: CalendarManager.CalendarEvent) -> some View {
        Button {
            toggleSelection(event)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(formatTimeRange(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected(event) ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(isSelected(event) ? .blue : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ event: CalendarManager.CalendarEvent) -> Bool {
        appState.selectedCalendarEvent?.id == event.id
    }

    private func toggleSelection(_ event: CalendarManager.CalendarEvent) {
        if isSelected(event) {
            appState.selectedCalendarEvent = nil
            appState.meetingTitle = ""
        } else {
            appState.selectedCalendarEvent = event
            appState.meetingTitle = event.title
        }
    }

    private func formatTimeRange(_ event: CalendarManager.CalendarEvent) -> String {
        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start) - \(end)"
    }
}
