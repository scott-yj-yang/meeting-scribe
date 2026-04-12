import SwiftUI

/// Bottom-anchored bar wrapping RecordingPill with a Notion-style meeting title area.
/// Shown above the main dashboard content when no recording is in progress, or as a status bar when recording.
struct DashboardRecordingBar: View {
    @EnvironmentObject var appState: AppState

    private let meetingTypes = ["1:1", "Subgroup", "Lab Meeting", "Casual", "Standup"]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if appState.isRecording {
                recordingLayout
            } else {
                preRecordingLayout
            }
        }
    }

    // MARK: - Pre-recording layout

    @ViewBuilder
    private var preRecordingLayout: some View {
        HStack(spacing: 16) {
            // Left: meeting type pills, title field, date subtitle
            VStack(alignment: .leading, spacing: 6) {
                // Meeting type pill row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(meetingTypes, id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if appState.selectedMeetingType == type {
                                        appState.selectedMeetingType = nil
                                    } else {
                                        appState.selectedMeetingType = type
                                    }
                                }
                            } label: {
                                Text(type)
                                    .font(.system(size: 9, weight: .medium))
                                    .fixedSize()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        appState.selectedMeetingType == type
                                            ? Color.blue
                                            : Color.gray.opacity(0.12)
                                    )
                                    .foregroundStyle(
                                        appState.selectedMeetingType == type
                                            ? .white
                                            : .secondary
                                    )
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Title field — Notion-style
                TextField("Untitled meeting", text: $appState.meetingTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)

                // Date subtitle + linked calendar event
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(Date().formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let event = appState.selectedCalendarEvent {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text(event.title)
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Right: recording pill
            RecordingPill()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Recording layout

    @ViewBuilder
    private var recordingLayout: some View {
        HStack(spacing: 12) {
            // Left: compact title + calendar event
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.meetingTitle.isEmpty ? "Untitled meeting" : appState.meetingTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let event = appState.selectedCalendarEvent {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text(event.title)
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Right: recording pill
            RecordingPill()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
