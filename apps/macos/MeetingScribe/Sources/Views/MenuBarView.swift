import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var showTodaysMeetings = false

    private enum Panel: Equatable {
        case main, settings, postRecording
    }

    private var activePanel: Panel {
        if showSettings { return .settings }
        if appState.showPostRecording { return .postRecording }
        return .main
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch activePanel {
                case .settings:
                    settingsPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .postRecording:
                    postRecordingPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .main:
                    mainPanel
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activePanel)
        }
        .frame(width: 320)
        .onAppear {
            appState.checkServerStatus()
            appState.audioCaptureManager.refreshMicList()
            Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
        }
    }

    // MARK: - Main Panel

    @ViewBuilder
    private var mainPanel: some View {
        // Header
        HStack(spacing: 8) {
            Text("MeetingScribe")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Spacer()
            // Quick link to web dashboard
            Button {
                if let url = URL(string: appState.serverURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(appState.serverStatus == .connected ? .blue : .gray.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .help("Open web dashboard")
            .disabled(appState.serverStatus != .connected)
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
        Group {
            if appState.isRecording {
                recordingView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                preRecordingView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isRecording)

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
                withAnimation(.easeInOut(duration: 0.2)) { showSettings = true }
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
                // Meeting type pill row — scrollable to prevent truncation
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
                                    .padding(.horizontal, 7)
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
                // Notes field
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    TextEditor(text: $appState.meetingNotes)
                        .font(.system(size: 11))
                        .frame(minHeight: 36, maxHeight: 60)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.gray.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(
                            Group {
                                if appState.meetingNotes.isEmpty {
                                    Text("Jot down quick notes...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 8)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
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
                VStack(spacing: 4) {
                    // Header — entire row is tappable
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTodaysMeetings.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Today's meetings")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("(\(appState.calendarManager.upcomingEvents.count))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showTodaysMeetings ? 90 : 0))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showTodaysMeetings {
                        ForEach(appState.calendarManager.upcomingEvents.prefix(5)) { event in
                            calendarRow(event: event)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Calendar access prompt
            if appState.calendarManager.accessDenied {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar access needed")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Link recordings to your meetings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Grant") {
                        appState.calendarManager.openCalendarSettings()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                }
                .padding(10)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Start button
            Button {
                appState.toggleRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 15))
                        .symbolEffect(.pulse, options: .speed(0.5))
                    Text("Start Session")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var meetingTypes: [String] {
        ["1:1", "Subgroup", "Lab Meeting", "Casual", "Standup"]
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
                        // Audio level meter — shows mic is working even without speech-to-text
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                ForEach(0..<12, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Float(i) / 12.0 < appState.audioLevel ? Color.green : Color.gray.opacity(0.15))
                                        .frame(width: 4, height: 10)
                                }
                                Spacer()
                                Text(appState.audioLevel > 0.01 ? "Receiving audio" : "Waiting for audio...")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .animation(.linear(duration: 0.03), value: appState.audioLevel)
                        }
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
        let accentColor: Color = isSelected ? .blue : (isCurrent ? .red : .blue)

        Button {
            if isSelected {
                appState.selectedCalendarEvent = nil
            } else {
                appState.meetingTitle = event.title
                appState.selectedCalendarEvent = event
            }
        } label: {
            HStack(spacing: 8) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: isSelected ? 40 : 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: isCurrent ? "record.circle.fill" : "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(accentColor)
                        Text(isSelected ? "Selected" : (isCurrent ? "Happening now" : "Starting soon"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .textCase(.uppercase)
                    }

                    Text(event.title)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(event.startDate.formatted(.dateTime.hour().minute())) – \(event.endDate.formatted(.dateTime.hour().minute()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !event.attendees.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("\(event.attendees.count) attendee\(event.attendees.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isSelected && !event.attendees.isEmpty {
                        Text(event.attendees.prefix(4).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.blue : Color.gray.opacity(0.3))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.gray.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private func calendarRow(event: CalendarManager.CalendarEvent) -> some View {
        let isSelected = appState.selectedCalendarEvent?.id == event.id

        Button {
            if isSelected {
                appState.selectedCalendarEvent = nil
            } else {
                appState.meetingTitle = event.title
                appState.selectedCalendarEvent = event
            }
        } label: {
            HStack(spacing: 8) {
                // Time
                Text(event.startDate.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 44, alignment: .leading)

                // Title + details
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(.caption, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isSelected && !event.attendees.isEmpty {
                        Text(event.attendees.prefix(3).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray.opacity(0.3))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
                        appState.showMeetingSummary(recording)
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
                withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
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

            // Microphone
            if appState.audioCaptureManager.availableMics.count > 1 {
                Text("Microphone").font(.caption2).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { appState.audioCaptureManager.selectedMicID },
                    set: { appState.audioCaptureManager.selectedMicID = $0 }
                )) {
                    ForEach(appState.audioCaptureManager.availableMics) { mic in
                        Text(mic.name).tag(Optional(mic.id))
                    }
                }
                .labelsHidden()
                .font(.caption)

                Divider()
            }

            Toggle("Auto-sync to server after recording", isOn: $appState.autoPushToServer)
                .font(.caption)
            Toggle("Save raw audio files", isOn: $appState.saveAudio)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Post-recording Panel

    @ViewBuilder
    private var postRecordingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.dismissPostRecording() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                Spacer()
                if let message = appState.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Transcription progress (shown while whisper is running)
            if appState.isTranscribing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Transcribing audio...")
                                .font(.system(.caption, weight: .medium))
                            if let eta = appState.transcriptionETA {
                                Text(eta)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(appState.transcriptionProgress * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(.blue)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * appState.transcriptionProgress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: appState.transcriptionProgress)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.04))

                Divider().padding(.horizontal, 12)
            }

            // Transcript snippet
            if let snippet = appState.lastTranscriptSnippet, !snippet.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("Transcript preview")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }

                    ScrollView {
                        Text(snippet)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            // Action grid
            VStack(spacing: 2) {
                // Files row
                HStack(spacing: 6) {
                    actionButton(
                        icon: "waveform.circle.fill",
                        iconColor: .purple,
                        label: "Audio",
                        enabled: appState.lastRecordingAudioURL != nil
                    ) {
                        appState.openAudioInFinder()
                    }

                    actionButton(
                        icon: "doc.text.fill",
                        iconColor: .blue,
                        label: "Transcript",
                        enabled: appState.lastRecordingMarkdownURL != nil && !appState.isTranscribing
                    ) {
                        appState.openTranscriptInFinder()
                    }

                    actionButton(
                        icon: "folder.fill",
                        iconColor: .orange,
                        label: "Folder",
                        enabled: true
                    ) {
                        appState.openOutputFolder()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Sync + actions row
                HStack(spacing: 6) {
                    if appState.lastUploadedMeetingId != nil {
                        actionButton(
                            icon: "globe",
                            iconColor: .green,
                            label: "Web UI",
                            enabled: true
                        ) {
                            appState.openInBrowser()
                        }

                        actionButton(
                            icon: "icloud.slash",
                            iconColor: .orange,
                            label: "Unpush",
                            enabled: true
                        ) {
                            appState.deleteFromServer()
                        }
                    } else {
                        actionButton(
                            icon: "icloud.and.arrow.up",
                            iconColor: .blue,
                            label: "Push",
                            enabled: true
                        ) {
                            appState.pushToServer()
                        }
                    }

                    actionButton(
                        icon: "trash",
                        iconColor: .red,
                        label: "Delete",
                        enabled: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { appState.promptDelete() }
                    }

                    actionButton(
                        icon: "plus.circle.fill",
                        iconColor: .mint,
                        label: "New",
                        enabled: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { appState.dismissPostRecording() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }

            // Upload status
            Divider().padding(.horizontal, 12)

            HStack(spacing: 6) {
                if appState.lastUploadedMeetingId != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Synced to server")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if appState.isTranscribing {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    Text("Will sync after transcription")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Not synced (server offline)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Delete confirmation
            if appState.showDeleteConfirm {
                Divider().padding(.horizontal, 12)

                VStack(spacing: 8) {
                    Text("Delete this meeting?")
                        .font(.system(.caption, weight: .semibold))
                    Text("Local files will be permanently removed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        if appState.currentMeeting?.isSynced == true {
                            Button {
                                withAnimation { appState.confirmDelete(alsoFromServer: true) }
                            } label: {
                                Text("Delete everywhere (local + server)")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button {
                                withAnimation { appState.confirmDelete(alsoFromServer: false) }
                            } label: {
                                Text("Delete local only")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                withAnimation { appState.confirmDelete(alsoFromServer: false) }
                            } label: {
                                Text("Delete")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }

                        Button {
                            withAnimation { appState.cancelDelete() }
                        } label: {
                            Text("Cancel")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private func actionButton(
        icon: String,
        iconColor: Color,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(enabled ? iconColor : .gray.opacity(0.4))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(enabled ? .primary : .tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
