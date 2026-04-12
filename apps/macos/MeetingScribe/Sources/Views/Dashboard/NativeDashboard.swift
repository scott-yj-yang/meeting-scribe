import SwiftUI

struct NativeDashboard: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMeeting: LocalMeeting?
    @State private var searchText = ""
    @State private var selectedType: String?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                VStack(spacing: 0) {
                    DashboardCalendarBanner()

                    List(selection: $selectedMeeting) {
                        MeetingListContent(
                            meetings: appState.meetingStore.meetings,
                            searchText: searchText,
                            selectedType: selectedType,
                            onDelete: { meeting in
                                appState.meetingStore.delete(meeting)
                                if selectedMeeting?.id == meeting.id {
                                    selectedMeeting = nil
                                }
                            }
                        )
                    }
                    .searchable(text: $searchText, prompt: "Search meetings")
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button("All") { selectedType = nil }
                            Divider()
                            ForEach(["1:1", "Subgroup", "Lab Meeting", "Standup", "Casual"], id: \.self) { type in
                                Button(type) { selectedType = type.lowercased() }
                            }
                        } label: {
                            Image(systemName: selectedType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
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
            .frame(maxHeight: .infinity)

            DashboardRecordingBar()
        }
        .onAppear {
            appState.meetingStore.loadAll()
            Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
        }
    }
}
