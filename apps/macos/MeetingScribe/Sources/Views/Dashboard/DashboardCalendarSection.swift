import SwiftUI

struct DashboardCalendarBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if appState.calendarManager.accessDenied {
                accessDeniedBanner
            } else if let suggested = appState.calendarManager.suggestedEvent {
                suggestedEventBanner(suggested)

                if isExpanded {
                    expandedEventsList
                }
            }

            Divider()
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Suggested Event Banner

    private func suggestedEventBanner(_ event: CalendarManager.CalendarEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(event.isHappeningNow ? Color.red : Color.blue)
                .frame(width: 8, height: 8)

            Text(event.isHappeningNow ? "Now" : "Next")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(event.isHappeningNow ? .red : .blue)

            Text(event.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Text(formatTimeRange(event))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                toggleSelection(event)
            } label: {
                Image(systemName: isSelected(event) ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected(event) ? .blue : .secondary)
                    .iconHitTarget(.compact)
            }
            .buttonStyle(.plain)
            .clickableHover()

            if !appState.calendarManager.upcomingEvents.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .iconHitTarget(.compact)
                }
                .buttonStyle(.plain)
                .clickableHover()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Expanded Events List

    private var expandedEventsList: some View {
        VStack(spacing: 0) {
            ForEach(appState.calendarManager.upcomingEvents) { event in
                Button {
                    toggleSelection(event)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(event.isHappeningNow ? Color.red : Color.blue)
                            .frame(width: 6, height: 6)

                        Text(event.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        Text(formatTimeRange(event))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Image(systemName: isSelected(event) ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected(event) ? .blue : .secondary)
                            .iconHitTarget(.compact)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickableHover()
            }
        }
    }

    // MARK: - Access Denied Banner

    private var accessDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

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
