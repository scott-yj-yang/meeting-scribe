import SwiftUI

struct NativeDashboard: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMeeting: LocalMeeting?
    @State private var searchText = ""
    @State private var selectedType: String?
    @State private var showRecordingMode = false

    var isRecordingMode: Bool {
        showRecordingMode || appState.isRecording || appState.showPostRecording
    }

    var body: some View {
        ZStack {
            if !isRecordingMode {
                viewingMode
                    .transition(.opacity)
            } else {
                recordingMode
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isRecordingMode)
        .onAppear {
            appState.meetingStore.loadAll()
            Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
        }
        .onChange(of: appState.lastCompletedMeeting) { _, newMeeting in
            if let meeting = newMeeting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedMeeting = meeting
                        showRecordingMode = false
                        appState.lastCompletedMeeting = nil
                        appState.showPostRecording = false
                    }
                }
            }
        }
    }

    // MARK: - Viewing Mode

    private var viewingMode: some View {
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showRecordingMode = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Meetings")
            .frame(minWidth: 250)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting, meetingStore: appState.meetingStore)
            } else {
                ContentUnavailableView {
                    Label("No Meeting Selected", systemImage: "waveform.badge.mic")
                } description: {
                    Text("Select a meeting from the sidebar or start a new one.")
                } actions: {
                    Button {
                        showRecordingMode = true
                    } label: {
                        Label("New Meeting", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Recording Mode

    private var recordingMode: some View {
        VStack(spacing: 0) {
            if !appState.isRecording && !appState.showPostRecording {
                HStack {
                    Button {
                        showRecordingMode = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Meetings")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Spacer()
                }
            }

            RecordingModeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
