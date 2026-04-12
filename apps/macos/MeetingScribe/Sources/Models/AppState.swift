import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage: String? = nil
    @Published var meetingTitle: String = ""
    @Published var selectedMeetingType: String? = nil
    @Published var selectedCalendarEvent: CalendarManager.CalendarEvent? = nil
    @Published var meetingNotes: String = ""

    // Post-recording state
    @Published var lastRecordingAudioURL: URL? = nil
    @Published var lastRecordingMarkdownURL: URL? = nil
    @Published var showPostRecording = false
    @Published var isTranscribing = false
    @Published var transcriptionETA: String? = nil
    @Published var transcriptionProgress: Double = 0
    @Published var lastTranscriptSnippet: String? = nil
    @Published var currentMeeting: LocalMeeting? = nil
    @Published var lastCompletedMeeting: LocalMeeting? = nil

    let calendarManager = CalendarManager()
    let meetingStore: MeetingStore

    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = true

    @Published var liveTranscriptActive = false
    @Published var audioLevel: Float = 0  // 0.0 - 1.0, shows mic is receiving audio
    private var liveTranscriptTimer: Timer?

    private var timer: Timer?
    private var recordingStartDate: Date?
    let audioCaptureManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    private var audioFileWriter: AudioFileWriter?
    private let whisperProcessor = WhisperPostProcessor()

    init() {
        meetingStore = MeetingStore(baseDirectory: "~/MeetingScribe")
    }

    var recentRecordings: [LocalMeeting] {
        meetingStore.meetings
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            showPostRecording = false
            currentMeeting = nil
            statusMessage = "Starting..."
            Task.detached { [weak self] in
                await self?.doStartRecording()
            }
        }
    }

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
                self?.liveTranscriptActive = false
                self?.transcriptionManager.reset()
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
            // Try live transcript — non-fatal if it fails
            do {
                try await transcriptionManager.setup()
                liveTranscriptActive = true
                liveTranscriptTimer?.invalidate()
                liveTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.liveTranscriptActive = false
                        self?.transcriptionManager.reset()
                    }
                }
            } catch {
                print("[Recording] Live transcript unavailable: \(error.localizedDescription)")
                liveTranscriptActive = true  // Still show the audio check panel (with level meter)
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

                // Compute audio level from every buffer for responsive meter
                var rms: Float = 0
                let frameCount = Int(buffer.frameLength)
                if frameCount > 0 {
                    if let channelData = buffer.floatChannelData?[0] {
                        var sum: Float = 0
                        for i in stride(from: 0, to: frameCount, by: 4) {
                            sum += channelData[i] * channelData[i]
                        }
                        rms = sqrtf(sum / Float(frameCount / 4))
                    } else if let int16Data = buffer.int16ChannelData?[0] {
                        var sum: Float = 0
                        for i in stride(from: 0, to: frameCount, by: 4) {
                            let s = Float(int16Data[i]) / Float(Int16.max)
                            sum += s * s
                        }
                        rms = sqrtf(sum / Float(frameCount / 4))
                    }
                }
                let level = min(1.0, rms * 15)
                let capturedLevel = level

                Task { @MainActor in
                    self?.audioLevel = capturedLevel
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
            statusMessage = "Failed: \(error.localizedDescription)"
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

        isTranscribing = true
        transcriptionProgress = 0
        showPostRecording = true
        transcriptionETA = "estimating..."
        statusMessage = "Transcribing..."

        // Wire up progress callback
        whisperProcessor.onProgress = { [weak self] progress, eta in
            self?.transcriptionProgress = progress
            self?.transcriptionETA = eta
        }

        // Transcribe
        var segments: [TranscriptSegment] = []
        var snippetText: String? = nil
        if whisperProcessor.isAvailable {
            do {
                let result = try await whisperProcessor.transcribe(audioFile: audioURL)
                segments = result.segments
                snippetText = String(result.text.prefix(500))
                statusMessage = "Transcription complete"
            } catch {
                statusMessage = "Transcription failed"
            }
        } else {
            statusMessage = "Install whisper-cpp"
        }
        isTranscribing = false
        transcriptionETA = nil
        lastTranscriptSnippet = snippetText

        // Save markdown
        let markdown = MarkdownFormatter.format(
            title: title, date: startDate, duration: recordingDuration,
            meetingType: selectedMeetingType?.lowercased(),
            audioSources: audioCaptureManager.captureMode == .micAndSystem
                ? ["system", "microphone"] : ["microphone"],
            segments: segments
        )

        let meetingDir = LocalStorage.meetingDirectory(title: title, date: startDate, baseDirectory: outputDirectory)
        lastRecordingMarkdownURL = try? LocalStorage.save(
            markdown: markdown, title: title, date: startDate, directory: outputDirectory
        )

        // Save notes if any
        let notes = meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            let notesURL = meetingDir.appendingPathComponent("notes.md")
            try? notes.write(to: notesURL, atomically: true, encoding: .utf8)
        }

        statusMessage = "Saved"

        // Save to local database
        let meeting = meetingStore.createMeeting(
            title: title, date: startDate, duration: recordingDuration,
            meetingType: selectedMeetingType?.lowercased(),
            transcriptSnippet: snippetText,
            directoryURL: meetingDir,
            calendarEventTitle: selectedCalendarEvent?.title,
            notes: notes.isEmpty ? nil : notes
        )
        currentMeeting = meeting

        meetingTitle = ""
        selectedMeetingType = nil
        selectedCalendarEvent = nil
        meetingNotes = ""
        lastCompletedMeeting = meeting
    }

    // MARK: - Post-recording actions

    func showMeetingSummary(_ meeting: LocalMeeting) {
        currentMeeting = meeting
        lastRecordingAudioURL = meeting.hasAudio ? meeting.directoryURL?.appendingPathComponent("audio.wav") : nil
        lastRecordingMarkdownURL = meeting.hasTranscript ? meeting.directoryURL?.appendingPathComponent("transcript.md") : nil
        lastTranscriptSnippet = meeting.transcriptSnippet
        statusMessage = meeting.title
        showPostRecording = true
    }

    func openAudioInFinder() {
        guard let url = lastRecordingAudioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTranscriptInFinder() {
        guard let url = lastRecordingMarkdownURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openOutputFolder() {
        if let dir = currentMeeting?.directoryURL {
            NSWorkspace.shared.open(dir)
        } else {
            let path = NSString(string: outputDirectory).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    @Published var showDeleteConfirm = false

    func promptDelete() {
        showDeleteConfirm = true
    }

    func confirmDelete() {
        guard let meeting = currentMeeting else { return }
        meetingStore.delete(meeting)
        showDeleteConfirm = false
        dismissPostRecording()
    }

    func cancelDelete() {
        showDeleteConfirm = false
    }

    func dismissPostRecording() {
        showPostRecording = false
        lastRecordingAudioURL = nil
        lastRecordingMarkdownURL = nil
        lastTranscriptSnippet = nil
        currentMeeting = nil
        statusMessage = nil
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 { return "~\(seconds)s" }
        let min = seconds / 60
        let sec = seconds % 60
        return sec > 0 ? "~\(min)m \(sec)s" : "~\(min)m"
    }
}
