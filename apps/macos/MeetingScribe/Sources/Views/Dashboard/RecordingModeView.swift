import SwiftUI

/// Full-pane active meeting view with three phases: pre-recording, recording, and post-recording.
struct RecordingModeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var liveChatViewModel = MeetingChatViewModel()
    @StateObject private var liveChatLLMSettings = LLMSettings()

    private let meetingTypes = ["1:1", "Subgroup", "Lab Meeting", "Casual", "Standup"]

    var body: some View {
        VStack {
            if appState.showPostRecording {
                postRecordingPhase
                    .transition(.opacity)
            } else if appState.isRecording {
                recordingPhase
                    .transition(.opacity)
            } else {
                preRecordingPhase
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.35), value: appState.showPostRecording)
    }

    // MARK: - Phase 1: Pre-recording

    private var preRecordingPhase: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Calendar event picker
                CalendarPickerSection()
                    .padding(.horizontal, 24)

                // Meeting type pills
                meetingTypePills

                // Large title field
                TextField("Untitled meeting", text: $appState.meetingTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)

                // Date subtitle
                Text(Date().formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                // Notes area
                notesEditor

                // Start button
                Button {
                    appState.toggleRecording()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }
            .frame(maxWidth: 500)

            Spacer()
        }
        .padding()
    }

    // MARK: - Phase 2: Recording

    private var recordingPhase: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("Recording")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(formatDuration(appState.recordingDuration))
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    // Editable title
                    TextField("Untitled meeting", text: $appState.meetingTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)

                    // Calendar event badge
                    if let event = appState.selectedCalendarEvent {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue.opacity(0.7))
                            Text(event.title)
                                .font(.subheadline)
                                .foregroundStyle(.blue.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    // Waveform visualization
                    WaveformBars(level: appState.audioLevel, tint: .red)
                        .frame(height: 24)

                    // Notes area
                    notesEditor

                    // Stop button
                    Button {
                        appState.toggleRecording()
                    } label: {
                        Label("Stop Recording", systemImage: "stop.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
                .frame(maxWidth: 500)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            if appState.showLiveChatPanel {
                Divider()
                liveChatPanelView
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.showLiveChatPanel)
        .overlay(alignment: .topTrailing) {
            if !appState.showLiveChatPanel {
                Button {
                    appState.openLiveChatPanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Ask AI")
                    }
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.blue))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .clickableHover(cornerRadius: 22)
                .padding(16)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Live Chat Panel

    @ViewBuilder
    private var liveChatPanelView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live chat")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    appState.closeLiveChatPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .iconHitTarget(.compact)
                }
                .buttonStyle(.plain)
                .clickableHover()
            }
            .padding(12)
            Divider()

            MeetingChatPanel(
                viewModel: liveChatViewModel,
                presetMode: .live
            )
        }
        .onAppear {
            configureLiveChatViewModel()
        }
    }

    private func configureLiveChatViewModel() {
        liveChatViewModel.loadExisting(appState.liveChatSession.messages)

        liveChatViewModel.systemMessageProvider = { [weak appState] in
            guard let appState = appState else {
                return ChatMessage(role: .system, text: "")
            }
            let rawTranscript = appState.transcriptionManager.liveText
            let transcriptForPrompt: String
            if let err = appState.liveTranscriptError {
                transcriptForPrompt = "(Live transcription unavailable: \(err). Answer based on the meeting title and user notes only; if the user asks about what was said, explain that live transcription isn't running.)"
            } else if rawTranscript.isEmpty {
                transcriptForPrompt = "(Live transcription is running but no speech has been recognized yet. If the user asks about what was said, say so honestly.)"
            } else {
                transcriptForPrompt = rawTranscript
            }
            print("[LiveChat] Building system message — transcript chars: \(rawTranscript.count), error: \(appState.liveTranscriptError ?? "nil")")
            let context = MeetingContext(
                title: appState.meetingTitle.isEmpty ? "Current meeting" : appState.meetingTitle,
                date: Date(),
                durationSeconds: appState.recordingDuration,
                calendarEventTitle: appState.selectedCalendarEvent?.title,
                notes: appState.meetingNotes.isEmpty ? nil : appState.meetingNotes,
                transcript: transcriptForPrompt,
                summary: nil,
                mode: .live
            )
            return MeetingContextBuilder.buildSystemMessage(context: context)
        }

        // Snapshot LLM settings on MainActor before entering the nonisolated closure
        let kind = liveChatLLMSettings.providerKind
        let endpoint = liveChatLLMSettings.ollamaEndpoint
        let model = liveChatLLMSettings.ollamaModel

        liveChatViewModel.runChat = { messages, onToken in
            let provider = LLMProviderFactory.make(
                kind: kind,
                ollamaEndpoint: endpoint,
                ollamaModel: model
            )
            return try await provider.chat(messages: messages, onToken: onToken)
        }

        liveChatViewModel.onTurnComplete = { [weak appState] messages in
            appState?.liveChatSession = ChatSession(messages: messages)
        }
    }

    // MARK: - Phase 3: Post-recording

    private var postRecordingPhase: some View {
        VStack(spacing: 20) {
            if appState.isTranscribing {
                transcribingCard
            } else {
                completedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcribingCard: some View {
        VStack(spacing: 20) {
            // Stage indicator
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text(stageLabel)
                    .font(.system(.title3, design: .rounded, weight: .medium))
                Text(stageSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // Progress bar
            VStack(spacing: 6) {
                ProgressView(value: appState.transcriptionProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
                HStack {
                    Text("\(Int(appState.transcriptionProgress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(stableETA)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: 420)
            }

            // Snippet reveal
            if let snippet = appState.lastTranscriptSnippet, !snippet.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("First sentences", systemImage: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snippet)
                        .font(.system(.body, design: .serif))
                        .lineLimit(4)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(12)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if appState.isTranscribing {
                // Skeleton placeholder so the user knows text is coming
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 10)
                            .frame(maxWidth: i == 2 ? 280 : .infinity)
                    }
                }
                .frame(maxWidth: 520)
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: appState.transcriptionProgress)
        .animation(.easeInOut(duration: 0.3), value: appState.lastTranscriptSnippet)
    }

    private var stageLabel: String {
        switch appState.transcriptionProgress {
        case 0..<0.05: return "Preparing audio"
        case 0.05..<0.95: return "Transcribing with Whisper"
        default: return "Finalizing"
        }
    }

    private var stageSubtitle: String {
        switch appState.transcriptionProgress {
        case 0..<0.05: return "Loading audio and checking format..."
        case 0.05..<0.95: return "This runs locally on your Mac — no audio leaves the device."
        default: return "Wrapping up and saving transcript..."
        }
    }

    private var stableETA: String {
        if let eta = appState.transcriptionETA, !eta.isEmpty {
            return eta
        }
        if appState.transcriptionProgress < 0.05 { return "estimating..." }
        return "almost done"
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            if let message = appState.statusMessage {
                Text(message)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text("Opening meeting details...")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Shared Components

    private var meetingTypePills: some View {
        HStack(spacing: 6) {
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
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
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
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $appState.meetingNotes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)

            if appState.meetingNotes.isEmpty {
                Text("Add notes...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: 500, minHeight: 100, maxHeight: 200)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

}

// MARK: - Calendar Picker Section

private struct CalendarPickerSection: View {
    @EnvironmentObject var appState: AppState

    private var nowEvents: [CalendarManager.CalendarEvent] {
        var all: [CalendarManager.CalendarEvent] = []
        if let current = appState.calendarManager.currentEvent {
            all.append(current)
        }
        // Include any other upcoming events that already started (isHappeningNow)
        all.append(contentsOf: appState.calendarManager.upcomingEvents.filter { $0.isHappeningNow })
        return dedupe(all)
    }

    private var upcomingEvents: [CalendarManager.CalendarEvent] {
        let upcoming = appState.calendarManager.upcomingEvents.filter { !$0.isHappeningNow }
        return Array(dedupe(upcoming).prefix(5))
    }

    private func dedupe(_ events: [CalendarManager.CalendarEvent]) -> [CalendarManager.CalendarEvent] {
        var seen = Set<String>()
        return events.filter { evt in
            let key = "\(evt.title)|\(evt.startDate.timeIntervalSince1970)"
            return seen.insert(key).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !nowEvents.isEmpty || !upcomingEvents.isEmpty {
                HStack {
                    Label("Calendar", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await appState.calendarManager.fetchCurrentAndUpcoming() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .iconHitTarget(.compact)
                    }
                    .buttonStyle(.plain)
                    .clickableHover()
                    .help("Refresh calendar events")
                }

                if !nowEvents.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(nowEvents, id: \.id) { event in
                            eventRow(event, label: "Now", labelColor: .red)
                        }
                    }
                }

                if !upcomingEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !nowEvents.isEmpty {
                            Text("Upcoming")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        VStack(spacing: 6) {
                            ForEach(upcomingEvents, id: \.id) { event in
                                eventRow(event, label: timeLabel(for: event), labelColor: .blue)
                            }
                        }
                    }
                }

                Button {
                    appState.selectedCalendarEvent = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: appState.selectedCalendarEvent == nil ? "circle.fill" : "circle")
                            .foregroundStyle(appState.selectedCalendarEvent == nil ? .blue : .secondary)
                        Text("No calendar event")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickableHover()
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text("No events on your calendar today.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarManager.CalendarEvent, label: String, labelColor: Color) -> some View {
        let isSelected = appState.selectedCalendarEvent?.id == event.id
        Button {
            if isSelected {
                appState.selectedCalendarEvent = nil
            } else {
                appState.selectedCalendarEvent = event
                if appState.meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appState.meetingTitle = event.title
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))

                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(labelColor, in: Capsule())

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(rangeLabel(for: event))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !event.attendees.isEmpty {
                            Text("· \(event.attendees.count) attendees")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickableHover()
    }

    private func rangeLabel(for event: CalendarManager.CalendarEvent) -> String {
        let fmt = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.startDate.formatted(fmt)) – \(event.endDate.formatted(fmt))"
    }

    private func timeLabel(for event: CalendarManager.CalendarEvent) -> String {
        let minutes = Int(event.startDate.timeIntervalSinceNow / 60)
        if minutes < 60 { return "in \(max(minutes, 0))m" }
        let hours = minutes / 60
        return "in \(hours)h"
    }
}
