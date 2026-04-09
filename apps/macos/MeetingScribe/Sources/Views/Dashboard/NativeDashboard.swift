import SwiftUI

struct NativeDashboard: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMeeting: LocalMeeting?

    var body: some View {
        NavigationSplitView {
            MeetingListSidebar(
                meetings: appState.meetingStore.meetings,
                selection: $selectedMeeting
            )
            .navigationTitle("Meetings")
            .frame(minWidth: 250)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting, meetingStore: appState.meetingStore)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select a meeting")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Or start a new recording from the menu bar")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            appState.meetingStore.loadAll()
        }
    }
}
