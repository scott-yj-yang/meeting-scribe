import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            appState.checkServerStatus()
            Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
        }
    }

    // MARK: - Main Panel

    @ViewBuilder
    private var mainPanel: some View {
        if appState.isRecording {
            RecordingIndicator(duration: appState.recordingDuration)

            if appState.enableLiveTranscript && !appState.transcriptionManager.liveText.isEmpty {
                ScrollView {
                    Text(appState.transcriptionManager.liveText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }

            Button("Stop Recording") {
                appState.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            // Meeting title
            TextField("Meeting title (optional)", text: $appState.meetingTitle)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            // Calendar suggestion
            if let event = appState.calendarManager.suggestedEvent {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.caption)
                            .fontWeight(.medium)
                        if !event.attendees.isEmpty {
                            Text(event.attendees.prefix(3).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Use") {
                        appState.meetingTitle = event.title
                        appState.selectedCalendarEvent = event
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
                .padding(6)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            }

            // Today's events
            if !appState.calendarManager.upcomingEvents.isEmpty {
                Text("Today's meetings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(appState.calendarManager.upcomingEvents.prefix(5)) { event in
                    HStack(spacing: 6) {
                        Text(event.startDate, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .leading)
                        Text(event.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Use") {
                            appState.meetingTitle = event.title
                            appState.selectedCalendarEvent = event
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button("Start Recording") {
                appState.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
        }

        // Status message
        if let message = appState.statusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(message.lowercased().contains("fail") ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        // Server status
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        Text("Recent")
            .font(.caption)
            .foregroundStyle(.secondary)
        RecentRecordingsList(recordings: appState.recentRecordings)

        Divider()

        Button("Settings...") { showSettings = true }
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    // MARK: - Settings Panel

    @ViewBuilder
    private var settingsPanel: some View {
        HStack {
            Text("Settings")
                .font(.headline)
            Spacer()
            Button("Done") { showSettings = false }
                .buttonStyle(.borderless)
        }

        Divider()

        Text("Server URL").font(.caption).foregroundStyle(.secondary)
        TextField("http://localhost:3000", text: $appState.serverURL)
            .textFieldStyle(.roundedBorder).font(.caption)

        Text("Output Directory").font(.caption).foregroundStyle(.secondary)
        TextField("~/MeetingScribe", text: $appState.outputDirectory)
            .textFieldStyle(.roundedBorder).font(.caption)

        Divider()

        Toggle("Live transcript (uses more CPU)", isOn: $appState.enableLiveTranscript)
            .font(.caption)
        Toggle("Save raw audio files", isOn: $appState.saveAudio)
            .font(.caption)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.serverStatus {
        case .connected: return .green
        case .disconnected: return .red
        case .unknown: return .yellow
        }
    }

    private var statusText: String {
        switch appState.serverStatus {
        case .connected: return "Server connected"
        case .disconnected: return "Server offline"
        case .unknown: return "Checking server..."
        }
    }
}
