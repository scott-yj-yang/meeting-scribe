import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recentRecordings: [Recording] = []
    @Published var serverStatus: ServerStatus = .unknown
    @Published var statusMessage: String? = nil
    @Published var meetingTitle: String = ""
    @Published var selectedMeetingType: String? = nil
    @Published var selectedCalendarEvent: CalendarManager.CalendarEvent? = nil

    // Post-recording state
    @Published var lastRecordingAudioURL: URL? = nil
    @Published var lastRecordingMarkdownURL: URL? = nil
    @Published var lastUploadedMeetingId: String? = nil
    @Published var showPostRecording = false
    @Published var isTranscribing = false
    @Published var transcriptionETA: String? = nil

    let calendarManager = CalendarManager()

    @AppStorage("serverURL") var serverURL = "http://localhost:3000"
    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = true

    @Published var liveTranscriptActive = false
    private var liveTranscriptTimer: Timer?

    private var timer: Timer?
    private var recordingStartDate: Date?
    let audioCaptureManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    private let uploadQueue = UploadQueue()
    private var audioFileWriter: AudioFileWriter?
    private let whisperProcessor = WhisperPostProcessor()

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            showPostRecording = false
            statusMessage = "Starting..."
            Task.detached { [weak self] in
                await self?.doStartRecording()
            }
        }
    }

    /// Toggle live transcript on for 60 seconds (audio check)
    func toggleLiveTranscriptCheck() {
        if liveTranscriptActive {
            disableLiveTranscript()
        } else {
            enableLiveTranscriptTemporarily()
        }
    }

    private func enableLiveTranscriptTemporarily() {
        liveTranscriptActive = true
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.disableLiveTranscript()
            }
        }
    }

    private func disableLiveTranscript() {
        liveTranscriptActive = false
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = nil
        transcriptionManager.reset()
    }

    private func doStartRecording() async {
        let startDate = Date()

        do {
            try await transcriptionManager.setup()
            liveTranscriptActive = true
            liveTranscriptTimer?.invalidate()
            liveTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.liveTranscriptActive = false
                    self?.transcriptionManager.reset()
                    print("[Transcription] Auto-disabled live transcript after 60s")
                }
            }

            let transcriber = transcriptionManager
            let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
                : meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let writer = AudioFileWriter(directory: outputDirectory, title: title, date: startDate)
            self.audioFileWriter = writer

            audioCaptureManager.onMicAudio = { [weak self] buffer, time in
                nonisolated(unsafe) let buffer = buffer
                writer.write(buffer: buffer)
                Task { @MainActor in
                    if self?.liveTranscriptActive == true {
                        transcriber.processAudioBuffer(buffer, speaker: "Local")
                    }
                }
            }
            audioCaptureManager.onSystemAudio = { [weak self] sampleBuffer in
                nonisolated(unsafe) let sampleBuffer = sampleBuffer
                writer.writeSystemAudio(sampleBuffer: sampleBuffer)
                Task { @MainActor in
                    if self?.liveTranscriptActive == true {
                        transcriber.processSampleBuffer(sampleBuffer, speaker: "Remote")
                    }
                }
            }

            await audioCaptureManager.startCapture()

            if let format = audioCaptureManager.micFormat {
                try writer.start(format: format)
                print("[Recording] Audio file: \(writer.fileURL.path)")
            }

            recordingStartDate = startDate
            isRecording = true
            recordingDuration = 0
            statusMessage = nil

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 1
                }
            }
        } catch {
            statusMessage = "Recording failed: \(error.localizedDescription)"
            print("[Recording] Failed: \(error)")
        }
    }

    func stopRecording() {
        Task.detached { [weak self] in
            await self?.doStopRecording()
        }
    }

    private func doStopRecording() async {
        await audioCaptureManager.stopCapture()
        timer?.invalidate()
        timer = nil
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = nil
        liveTranscriptActive = false
        isRecording = false
        transcriptionManager.reset()

        guard let writer = audioFileWriter else { return }
        let audioURL = writer.stop()
        audioFileWriter = nil
        lastRecordingAudioURL = audioURL

        guard let startDate = recordingStartDate else { return }
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
            : meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Recording] Stopped. Audio: \(audioURL.path)")
        isTranscribing = true
        showPostRecording = true

        // Estimate transcription time (~1/10th of recording duration for large-v3-turbo)
        let etaSeconds = max(5, Int(recordingDuration / 10))
        transcriptionETA = formatETA(etaSeconds)
        statusMessage = "Transcribing..."

        var segments: [TranscriptSegment] = []
        if whisperProcessor.isAvailable {
            do {
                print("[Whisper] Transcribing... (ETA: ~\(etaSeconds)s)")
                let result = try await whisperProcessor.transcribe(audioFile: audioURL)
                segments = result.segments
                print("[Whisper] Done — \(segments.count) segments")
                statusMessage = "Transcription complete"
            } catch {
                print("[Whisper] Failed: \(error.localizedDescription)")
                statusMessage = "Transcription failed. Audio saved."
            }
        } else {
            print("[Whisper] Not installed.")
            statusMessage = "Install whisper-cpp for transcription"
        }
        isTranscribing = false
        transcriptionETA = nil

        let markdown = MarkdownFormatter.format(
            title: title,
            date: startDate,
            duration: recordingDuration,
            meetingType: selectedMeetingType?.lowercased(),
            audioSources: audioCaptureManager.captureMode == .micAndSystem
                ? ["system", "microphone"] : ["microphone"],
            segments: segments
        )

        // Save locally
        if let fileURL = try? LocalStorage.save(
            markdown: markdown, title: title, date: startDate, directory: outputDirectory
        ) {
            lastRecordingMarkdownURL = fileURL
        }

        // Auto-upload to server
        var calInfo: MeetingAPIClient.CalendarInfo? = nil
        if let event = selectedCalendarEvent {
            calInfo = MeetingAPIClient.CalendarInfo(
                eventId: event.id, title: event.title, organizer: event.organizer,
                attendees: event.attendees, start: event.startDate, end: event.endDate
            )
        }

        let client = MeetingAPIClient(serverURL: serverURL)
        do {
            let meetingId = try await client.uploadMeeting(
                title: title, date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["microphone"],
                meetingType: selectedMeetingType?.lowercased(),
                rawMarkdown: markdown,
                segments: segments,
                calendar: calInfo
            )
            lastUploadedMeetingId = meetingId
            statusMessage = "\(title) saved"
        } catch {
            await uploadQueue.enqueue(UploadQueue.PendingUpload(
                filePath: recentRecordings.first?.filePath ?? "",
                title: title, date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["microphone"],
                meetingType: nil
            ))
            lastUploadedMeetingId = nil
            statusMessage = "Saved locally (server offline)"
        }

        // Save to recent recordings (now we have the server ID)
        let recording = Recording(
            id: UUID(), title: title, date: startDate,
            duration: recordingDuration,
            filePath: lastRecordingMarkdownURL?.path ?? "",
            audioPath: audioURL.path,
            serverMeetingId: lastUploadedMeetingId
        )
        recentRecordings.insert(recording, at: 0)
        if recentRecordings.count > 5 { recentRecordings.removeLast() }

        meetingTitle = ""
        selectedMeetingType = nil
        selectedCalendarEvent = nil
        print("[Recording] Complete: \(title)")
    }

    // MARK: - Post-recording actions

    func openAudioInFinder() {
        guard let url = lastRecordingAudioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTranscriptInFinder() {
        guard let url = lastRecordingMarkdownURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openOutputFolder() {
        let expandedDir = NSString(string: outputDirectory).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedDir))
    }

    func openInBrowser() {
        guard let meetingId = lastUploadedMeetingId else { return }
        if let url = URL(string: "\(serverURL)/meetings/\(meetingId)") {
            NSWorkspace.shared.open(url)
        }
    }

    func deleteFromServer() {
        guard let meetingId = lastUploadedMeetingId else { return }
        Task {
            guard let url = URL(string: "\(serverURL)/api/meetings/\(meetingId)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                    lastUploadedMeetingId = nil
                    statusMessage = "Removed from server (local files kept)"
                    print("[Server] Deleted meeting \(meetingId)")
                }
            } catch {
                statusMessage = "Failed to delete from server"
            }
        }
    }

    /// Show a past recording's summary panel
    func showRecordingSummary(_ recording: Recording) {
        lastRecordingMarkdownURL = recording.filePath.isEmpty ? nil : URL(fileURLWithPath: recording.filePath)
        lastRecordingAudioURL = recording.audioPath.flatMap { URL(fileURLWithPath: $0) }
        lastUploadedMeetingId = recording.serverMeetingId
        statusMessage = recording.title
        showPostRecording = true
    }

    func dismissPostRecording() {
        showPostRecording = false
        lastRecordingAudioURL = nil
        lastRecordingMarkdownURL = nil
        lastUploadedMeetingId = nil
        statusMessage = nil
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 { return "~\(seconds)s" }
        let min = seconds / 60
        let sec = seconds % 60
        return sec > 0 ? "~\(min)m \(sec)s" : "~\(min)m"
    }

    // MARK: - Server

    func checkServerStatus() {
        Task {
            guard let url = URL(string: "\(serverURL)/api/meetings?limit=1") else {
                serverStatus = .disconnected
                return
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    serverStatus = .connected
                } else {
                    serverStatus = .disconnected
                }
            } catch {
                serverStatus = .disconnected
            }
        }
    }
}

struct Recording: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let duration: TimeInterval
    let filePath: String        // markdown path
    let audioPath: String?      // audio file path
    let serverMeetingId: String? // uploaded meeting ID
}

enum ServerStatus {
    case connected, disconnected, unknown
}
