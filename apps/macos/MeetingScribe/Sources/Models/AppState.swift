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
    @Published var liveTranscriptError: String? = nil  // Set when setup() throws; surfaced to chat panel
    @Published var audioLevel: Float = 0  // 0.0 - 1.0, shows mic is receiving audio
    private var liveTranscriptTimer: Timer?

    // MARK: - Live chat during recording
    @Published var showLiveChatPanel: Bool = false
    @Published var liveChatSession: ChatSession = ChatSession(messages: [])

    // Briefly true while the previous recording is being finalized (stopCapture
    // + writer.stop). Prevents a new recording from racing the writer reference.
    @Published var isFinalizingPreviousRecording: Bool = false

    private var timer: Timer?
    private var recordingStartDate: Date?
    let audioCaptureManager = AudioCaptureManager()
    let transcriptionManager = TranscriptionManager()
    private var audioFileWriter: AudioFileWriter?
    private let whisperProcessor = WhisperPostProcessor()

    // Serializes post-processing (whisper transcription + markdown + save) so
    // rapid back-to-back recordings don't run two whisper passes concurrently
    // on the same shared whisperProcessor.
    private var postProcessingTask: Task<Void, Never>?

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
            guard !isFinalizingPreviousRecording else {
                statusMessage = "Finalizing previous recording — try again in a moment..."
                return
            }
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
                guard let self = self else { return }
                // Don't reset if the chat panel is open — the user needs the full transcript
                guard !self.showLiveChatPanel else { return }
                self.liveTranscriptActive = false
                self.transcriptionManager.reset()
            }
        }
    }

    private func disableLiveTranscript() {
        liveTranscriptActive = false
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = nil
        transcriptionManager.reset()
    }

    func openLiveChatPanel() {
        showLiveChatPanel = true
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = nil

        // If transcription was torn down (e.g. by a prior audio-check timeout),
        // bring it back up so the live chat panel has a transcript to work with.
        if !liveTranscriptActive {
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.transcriptionManager.setup()
                    self.liveTranscriptActive = true
                    self.liveTranscriptError = nil
                } catch {
                    print("[Chat] Failed to restart live transcript: \(error.localizedDescription)")
                    self.liveTranscriptActive = false
                    self.liveTranscriptError = error.localizedDescription
                }
            }
        }
    }

    func closeLiveChatPanel() {
        showLiveChatPanel = false
        // Let the regular 60s timer rearm — restart it fresh
        if isRecording {
            enableLiveTranscriptTemporarily()
        }
    }

    private func doStartRecording() async {
        let startDate = Date()

        do {
            // Try live transcript — non-fatal if it fails
            do {
                try await transcriptionManager.setup()
                liveTranscriptActive = true
                liveTranscriptError = nil
                // No 60-second reset during recording — live transcription runs for the
                // entire meeting so mid-meeting chat and post-recording snippet preview
                // have the full transcript buffer.
            } catch {
                print("[Recording] Live transcript unavailable: \(error.localizedDescription)")
                // Surface the failure instead of pretending transcription is running.
                // Audio capture and level meter still work; whisper post-processing still
                // runs on stop. Only the live Q&A context is affected.
                liveTranscriptActive = false
                liveTranscriptError = error.localizedDescription
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
        // === Phase 1: Snapshot all per-recording state BEFORE any `await`.
        // This is the race-prevention trick: once we yield, a rapid
        // doStartRecording may overwrite self.audioFileWriter, meetingTitle,
        // recordingStartDate, etc. By snapshotting first we guarantee
        // post-processing sees the meeting that was actually being stopped.
        let writerToFinalize = audioFileWriter
        audioFileWriter = nil

        let startDate = recordingStartDate ?? Date()
        recordingStartDate = nil
        let duration = recordingDuration
        let capturedTitle: String = {
            let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
                : trimmed
        }()
        let capturedMeetingType = selectedMeetingType
        let capturedNotes = meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedEventTitle = selectedCalendarEvent?.title
        let capturedOutputDir = outputDirectory
        let capturedCaptureMode = audioCaptureManager.captureMode
        let capturedLiveChatSession = liveChatSession

        // Clear per-recording UI state so the next recording starts clean.
        meetingTitle = ""
        selectedMeetingType = nil
        selectedCalendarEvent = nil
        meetingNotes = ""
        liveChatSession = ChatSession(messages: [])

        timer?.invalidate()
        timer = nil
        liveTranscriptTimer?.invalidate()
        liveTranscriptTimer = nil
        liveTranscriptActive = false

        // === Phase 2: Finalize audio. This must complete before a new
        // recording can start (otherwise the shared audioCaptureManager and
        // writer objects can enter a broken state). toggleRecording refuses
        // new starts while `isFinalizingPreviousRecording` is true.
        isFinalizingPreviousRecording = true

        await audioCaptureManager.stopCapture()
        transcriptionManager.reset()
        isRecording = false

        let audioURL = writerToFinalize?.stop()
        lastRecordingAudioURL = audioURL

        isFinalizingPreviousRecording = false

        guard let finalAudioURL = audioURL else { return }

        // === Phase 3: Detached post-processing. Transcription, markdown
        // generation, and meeting-store persistence all run in a detached
        // task that waits for any previous post-processing to finish first
        // (so two whisper passes never run concurrently on the shared
        // whisperProcessor). While this runs, the user can start a new
        // recording immediately.
        let previousPostTask = postProcessingTask
        postProcessingTask = Task.detached { [weak self] in
            await previousPostTask?.value
            await self?.runPostRecordingTranscription(
                audioURL: finalAudioURL,
                startDate: startDate,
                duration: duration,
                title: capturedTitle,
                meetingType: capturedMeetingType,
                notes: capturedNotes,
                calendarEventTitle: capturedEventTitle,
                outputDirectory: capturedOutputDir,
                captureMode: capturedCaptureMode,
                liveChatSession: capturedLiveChatSession
            )
        }
    }

    /// Runs whisper transcription + markdown generation + meeting store
    /// persistence using only the snapshot parameters (never live `self.*`
    /// fields that a concurrent recording could have mutated).
    @MainActor
    private func runPostRecordingTranscription(
        audioURL: URL,
        startDate: Date,
        duration: TimeInterval,
        title: String,
        meetingType: String?,
        notes: String,
        calendarEventTitle: String?,
        outputDirectory: String,
        captureMode: AudioCaptureManager.CaptureMode,
        liveChatSession: ChatSession
    ) async {
        isTranscribing = true
        transcriptionProgress = 0
        showPostRecording = true
        transcriptionETA = "estimating..."
        statusMessage = "Transcribing..."

        whisperProcessor.onProgress = { [weak self] progress, eta in
            self?.transcriptionProgress = progress
            self?.transcriptionETA = eta
        }

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

        let markdown = MarkdownFormatter.format(
            title: title, date: startDate, duration: duration,
            meetingType: meetingType?.lowercased(),
            audioSources: captureMode == .micAndSystem ? ["system", "microphone"] : ["microphone"],
            segments: segments
        )

        let meetingDir = LocalStorage.meetingDirectory(
            title: title, date: startDate, baseDirectory: outputDirectory
        )
        lastRecordingMarkdownURL = try? LocalStorage.save(
            markdown: markdown, title: title, date: startDate, directory: outputDirectory
        )

        if !notes.isEmpty {
            let notesURL = meetingDir.appendingPathComponent("notes.md")
            try? notes.write(to: notesURL, atomically: true, encoding: .utf8)
        }

        statusMessage = "Saved"

        let meeting = meetingStore.createMeeting(
            title: title, date: startDate, duration: duration,
            meetingType: meetingType?.lowercased(),
            transcriptSnippet: snippetText,
            directoryURL: meetingDir,
            calendarEventTitle: calendarEventTitle,
            notes: notes.isEmpty ? nil : notes
        )
        currentMeeting = meeting

        if !liveChatSession.messages.isEmpty {
            let store = ChatSessionStore()
            try? store.save(liveChatSession, to: meetingDir)
        }

        showLiveChatPanel = false
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
