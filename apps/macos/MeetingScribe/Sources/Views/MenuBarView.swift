import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSettings {
                settingsPanel
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
        VStack(alignment: .leading, spacing: 10) {
            // Title input
            TextField("Meeting title (optional)", text: $appState.meetingTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .rounded))

            // Calendar event suggestion
            if let event = appState.calendarManager.suggestedEvent {
                calendarSuggestion(event: event, isCurrent: event.isHappeningNow)
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
            }

            // Record button
            Button {
                appState.toggleRecording()
            } label: {
                HStack {
                    Image(systemName: "record.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Start Recording")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Recording

    @ViewBuilder
    private var recordingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recording indicator
            HStack {
                RecordingIndicator(duration: appState.recordingDuration)
                Spacer()
                // Linked calendar event badge
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

            // Live transcript
            if appState.enableLiveTranscript && !appState.transcriptionManager.liveText.isEmpty {
                ScrollView {
                    Text(appState.transcriptionManager.liveText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(6)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(recording.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(timeAgo(from: recording.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
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

            Toggle("Live transcript (uses more CPU)", isOn: $appState.enableLiveTranscript)
                .font(.caption)
            Toggle("Save raw audio files", isOn: $appState.saveAudio)
                .font(.caption)
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
