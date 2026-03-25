import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSettings {
                settingsPanel
            } else if appState.showPostRecording {
                postRecordingPanel
            } else {
                mainPanel
            }
        }
        .frame(width: 320)
        .onAppear {
            appState.checkServerStatus()
            Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
        }
    }

    // MARK: - Main Panel

    @ViewBuilder
    private var mainPanel: some View {
        // Header
        HStack {
            Text("MeetingScribe")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Spacer()
            // Server status dot
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)

        Divider().padding(.horizontal, 12)

        // Recording section
        if appState.isRecording {
            recordingView
        } else {
            preRecordingView
        }

        // Status message
        if let message = appState.statusMessage {
            Text(message)
                .font(.caption2)
                .foregroundStyle(message.lowercased().contains("fail") ? .red : .green)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }

        Divider().padding(.horizontal, 12)

        // Recent recordings
        recentSection

        Divider().padding(.horizontal, 12)

        // Footer
        HStack {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Pre-recording

    @ViewBuilder
    private var preRecordingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Notion-style title area
            VStack(alignment: .leading, spacing: 6) {
                // Meeting type pill row
                HStack(spacing: 6) {
                    ForEach(meetingTypes, id: \.self) { type in
                        Button {
                            if appState.selectedMeetingType == type {
                                appState.selectedMeetingType = nil
                            } else {
                                appState.selectedMeetingType = type
                            }
                        } label: {
                            Text(type)
                                .font(.system(size: 10, weight: .medium))
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

                // Title — large, clean, Notion-style
                TextField("Untitled meeting", text: $appState.meetingTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)

                // Subtitle: date + linked event
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(Date().formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let event = appState.selectedCalendarEvent {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text(event.title)
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            // Calendar event suggestion
            if let event = appState.calendarManager.suggestedEvent {
                calendarSuggestion(event: event, isCurrent: event.isHappeningNow)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Today's other events
            if !appState.calendarManager.upcomingEvents.isEmpty {
                DisclosureGroup {
                    VStack(spacing: 4) {
                        ForEach(appState.calendarManager.upcomingEvents.prefix(5)) { event in
                            calendarRow(event: event)
                        }
                    }
                } label: {
                    Text("Today's meetings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Record button
            Button {
                appState.toggleRecording()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                        )
                    Text("Start Recording")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var meetingTypes: [String] {
        ["Standup", "1:1", "Team", "Planning", "Interview"]
    }

    // MARK: - Recording

    @ViewBuilder
    private var recordingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recording indicator + calendar badge
            HStack {
                RecordingIndicator(duration: appState.recordingDuration)
                Spacer()
                if let event = appState.selectedCalendarEvent {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text(event.title)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }

            // Live transcript area
            if appState.liveTranscriptActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 5, height: 5)
                            Text("Audio check")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green)
                                .textCase(.uppercase)
                        }
                        Spacer()
                        Button {
                            appState.toggleLiveTranscriptCheck()
                        } label: {
                            Text("Hide")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    if !appState.transcriptionManager.liveText.isEmpty {
                        Text(appState.transcriptionManager.liveText)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(4)
                    } else {
                        Text("Listening...")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.06))
                .cornerRadius(6)
            } else {
                // Show "check audio" button when live transcript is off
                Button {
                    appState.toggleLiveTranscriptCheck()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text("Check audio")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Stop button
            Button {
                appState.toggleRecording()
            } label: {
                HStack {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                    Text("Stop Recording")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Calendar Components

    @ViewBuilder
    private func calendarSuggestion(event: CalendarManager.CalendarEvent, isCurrent: Bool) -> some View {
        let isSelected = appState.selectedCalendarEvent?.id == event.id

        Button {
            appState.meetingTitle = event.title
            appState.selectedCalendarEvent = event
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: isCurrent ? "record.circle.fill" : "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(isCurrent ? .red : .blue)
                        Text(isCurrent ? "Happening now" : "Starting soon")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isCurrent ? .red : .blue)
                            .textCase(.uppercase)
                    }

                    Text(event.title)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(event.startDate.formatted(.dateTime.hour().minute())) – \(event.endDate.formatted(.dateTime.hour().minute()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if !event.attendees.isEmpty {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(event.attendees.count) attendee\(event.attendees.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !event.attendees.isEmpty {
                        Text(event.attendees.prefix(4).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                }
            }
            .padding(8)
            .background(isSelected ? Color.green.opacity(0.08) : Color.blue.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func calendarRow(event: CalendarManager.CalendarEvent) -> some View {
        let isSelected = appState.selectedCalendarEvent?.id == event.id

        Button {
            appState.meetingTitle = event.title
            appState.selectedCalendarEvent = event
        } label: {
            HStack(spacing: 6) {
                Text(event.startDate.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                Text(event.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.green.opacity(0.08) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Section

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if appState.recentRecordings.isEmpty {
                Text("No recent recordings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                ForEach(appState.recentRecordings.prefix(5)) { recording in
                    Button {
                        appState.showRecordingSummary(recording)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(recording.title)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(timeAgo(from: recording.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Settings Panel

    @ViewBuilder
    private var settingsPanel: some View {
        HStack {
            Button {
                showSettings = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Text("Settings")
                .font(.system(.headline, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)

        Divider().padding(.horizontal, 12)

        VStack(alignment: .leading, spacing: 10) {
            Group {
                Text("Server URL").font(.caption2).foregroundStyle(.secondary)
                TextField("http://localhost:3000", text: $appState.serverURL)
                    .textFieldStyle(.roundedBorder).font(.caption)
            }

            Group {
                Text("Output Directory").font(.caption2).foregroundStyle(.secondary)
                TextField("~/MeetingScribe", text: $appState.outputDirectory)
                    .textFieldStyle(.roundedBorder).font(.caption)
            }

            Divider()

            Toggle("Save raw audio files", isOn: $appState.saveAudio)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Post-recording Panel

    @ViewBuilder
    private var postRecordingPanel: some View {
        // Header
        HStack {
            Text("MeetingScribe")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Spacer()
            Button {
                appState.dismissPostRecording()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)

        Divider().padding(.horizontal, 12)

        VStack(alignment: .leading, spacing: 10) {
            // Status
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text("Recording complete")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }

            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // File actions
            Text("Files")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if appState.lastRecordingAudioURL != nil {
                Button {
                    appState.openAudioInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .frame(width: 16)
                        Text("Show audio file in Finder")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.borderless)
            }

            if appState.lastRecordingMarkdownURL != nil {
                Button {
                    appState.openTranscriptInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .frame(width: 16)
                        Text("Show transcript in Finder")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.borderless)
            }

            Button {
                appState.openOutputFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .frame(width: 16)
                    Text("Open output folder")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)

            Divider()

            // Server actions
            Text("Server")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let meetingId = appState.lastUploadedMeetingId {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .frame(width: 16)
                    Text("Uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(meetingId.prefix(8) + "...")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Button {
                        appState.openInBrowser()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                                .font(.system(size: 10))
                            Text("View in browser")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        appState.deleteFromServer()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Remove from server")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    Text("Not uploaded (server offline)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // New recording button
            Button {
                appState.dismissPostRecording()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("New Recording")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    private func timeAgo(from date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours == 1 { return "1 hour ago" }
        if hours < 24 { return "\(hours) hours ago" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}
