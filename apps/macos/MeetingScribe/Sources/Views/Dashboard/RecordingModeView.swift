import SwiftUI

/// Full-pane active meeting view with three phases: pre-recording, recording, and post-recording.
struct RecordingModeView: View {
    @EnvironmentObject var appState: AppState

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
                // Calendar event suggestion
                if let event = appState.calendarManager.suggestedEvent {
                    calendarSuggestionRow(event)
                }

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
        .padding()
    }

    // MARK: - Phase 3: Post-recording

    private var postRecordingPhase: some View {
        VStack(spacing: 20) {
            if appState.isTranscribing {
                transcribingView
            } else {
                completedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcribingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text("Transcribing...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ProgressView(value: appState.transcriptionProgress, total: 1.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(appState.transcriptionProgress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let eta = appState.transcriptionETA {
                        Text("ETA: \(eta)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 350)

            if let snippet = appState.lastTranscriptSnippet {
                snippetPreview(snippet)
            }
        }
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

    private func calendarSuggestionRow(_ event: CalendarManager.CalendarEvent) -> some View {
        let isSelected = appState.selectedCalendarEvent?.id == event.id

        return Button {
            if isSelected {
                appState.selectedCalendarEvent = nil
                appState.meetingTitle = ""
            } else {
                appState.selectedCalendarEvent = event
                appState.meetingTitle = event.title
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(event.isHappeningNow ? Color.red : Color.blue)
                    .frame(width: 8, height: 8)

                Text(event.isHappeningNow ? "Now" : "Up next")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(event.isHappeningNow ? .red : .blue)

                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text(formatTimeRange(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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

    private func snippetPreview(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: 400, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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

    private func formatTimeRange(_ event: CalendarManager.CalendarEvent) -> String {
        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start) - \(end)"
    }
}
