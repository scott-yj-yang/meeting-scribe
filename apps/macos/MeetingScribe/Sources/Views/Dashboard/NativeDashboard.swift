import SwiftUI

struct NativeDashboard: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMeeting: LocalMeeting?
    @State private var searchText = ""
    @State private var selectedType: String?
    @State private var showRecordingMode = false

    var isRecordingMode: Bool {
        // Note: we intentionally do NOT include `appState.isRecording` here.
        // A recording can run in the background while the user browses past
        // meetings. `showRecordingMode` is the sole switch the user controls
        // (via "New Meeting", "Minimize", or the recording pill in the
        // dashboard toolbar). `showPostRecording` still forces the recording
        // view so the user sees transcription progress automatically when a
        // recording finishes — but they can minimize that too.
        showRecordingMode || appState.showPostRecording
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
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
                // Persistent recording pill — appears while a recording is
                // in progress AND the user has minimized the recording view.
                // Clicking it returns to the recording view.
                if appState.isRecording {
                    ToolbarItem(placement: .principal) {
                        Button {
                            showRecordingMode = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "record.circle")
                                    .symbolEffect(.pulse, options: .repeating)
                                    .foregroundStyle(.red)
                                Text("Recording")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                Text(formatDuration(appState.recordingDuration))
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .clickableHover(cornerRadius: 20)
                        .help("Return to recording")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("All") { selectedType = nil }
                        Divider()
                        ForEach(["1:1", "Subgroup", "Lab Meeting", "Seminar", "Standup", "Casual"], id: \.self) { type in
                            Button(type) { selectedType = type.lowercased() }
                        }
                    } label: {
                        Image(systemName: selectedType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .medium))
                            .iconHitTarget(.compact)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Filter meetings by type")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showRecordingMode = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .iconHitTarget(.compact)
                    }
                    .buttonStyle(.plain)
                    .help(appState.isRecording ? "Return to recording" : "Start a new meeting")
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
            // Top bar is always visible so the user can always get back to
            // the dashboard. The label and trailing indicator change based
            // on phase: pre-recording shows "Meetings"; active recording and
            // transcription show "Minimize" with a live recording pill.
            HStack {
                Button {
                    showRecordingMode = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(appState.isRecording || appState.showPostRecording ? "Minimize" : "Meetings")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Spacer()

                if appState.isRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .symbolEffect(.pulse, options: .repeating)
                            .foregroundStyle(.red)
                        Text(formatDuration(appState.recordingDuration))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                }
            }

            RecordingModeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
