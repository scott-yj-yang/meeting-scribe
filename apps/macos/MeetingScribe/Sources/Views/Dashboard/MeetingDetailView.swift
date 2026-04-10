import SwiftUI

struct MeetingDetailView: View {
    let meeting: LocalMeeting
    let meetingStore: MeetingStore
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Label(meeting.date.formatted(.dateTime.weekday(.wide).month().day().year()),
                          systemImage: "calendar")
                    Label(formatDuration(meeting.duration), systemImage: "clock")
                    if let type = meeting.meetingType {
                        Text(type)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let calTitle = meeting.calendarEventTitle {
                    Label(calTitle, systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Picker("", selection: $selectedTab) {
                Text("Transcript").tag(0)
                Text("Summary").tag(1)
                Text("Notes").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0:
                    let transcript = meetingStore.loadTranscript(meeting)
                    if transcript.isEmpty {
                        ContentUnavailableView("No transcript", systemImage: "doc.text",
                            description: Text("This meeting hasn't been transcribed yet."))
                    } else {
                        NativeTranscriptView(rawMarkdown: transcript)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                case 1:
                    NativeSummaryView(meeting: meeting)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                case 2:
                    NativeNotesEditor(meeting: meeting, meetingStore: meetingStore)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m == 0 { return "\(Int(seconds))s" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }
}
