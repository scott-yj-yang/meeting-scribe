import Foundation
import SwiftUI
import AVFoundation
import ScreenCaptureKit
import AppKit

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

    /// Non-fatal problem with the recording that just finished — currently, that
    /// system audio had to be dropped. Shown in the post-recording panel so a
    /// mic-only recording is never mistaken for a complete one.
    @Published var lastRecordingWarning: String? = nil

    /// Set to request the dashboard open a specific meeting's detail view. The
    /// dashboard observes this, navigates, then clears it. Needed because the
    /// selected meeting lives in the dashboard's local view state, which the
    /// post-recording "View Meeting" button cannot reach directly.
    @Published var meetingToOpen: LocalMeeting? = nil

    /// Whether screen-recording permission (required to capture system audio) is
    /// granted. Probed before recording so the user is prompted up front, not
    /// mid-meeting. `true` until proven otherwise so the UI doesn't flash a
    /// warning before the first probe completes.
    @Published var systemAudioGranted: Bool = true

    let calendarManager = CalendarManager()
    let meetingStore: MeetingStore

    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = true

    @Published var audioLevel: Float = 0  // 0.0 - 1.0, shows mic is receiving audio

    // MARK: - Live chat during recording
    @Published var showLiveChatPanel: Bool = false
    @Published var liveChatSession: ChatSession = ChatSession(messages: [])

    // Briefly true while the previous recording is being finalized (stopCapture
    // + writer.stop). Prevents a new recording from racing the writer reference.
    @Published var isFinalizingPreviousRecording: Bool = false

    private var timer: Timer?
    private var recordingStartDate: Date?
    let audioCaptureManager = AudioCaptureManager()
    private var audioFileWriter: AudioFileWriter?
    private let whisperProcessor = WhisperPostProcessor()

    /// The folder claimed when the current recording started. Resolved exactly
    /// once so audio, transcript, notes, and metadata can never end up in
    /// different directories when the title is edited mid-recording.
    private var currentMeetingDirectory: URL?

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

    func openLiveChatPanel() {
        showLiveChatPanel = true
    }

    // MARK: - Pre-recording setup

    /// Populate the microphone list so the pre-recording screen can offer a
    /// picker. Safe to call repeatedly.
    func refreshInputDevices() {
        audioCaptureManager.refreshMicList()
    }

    /// Probe screen-recording permission, which system-audio capture requires.
    ///
    /// The first call to `SCShareableContent.current` is what triggers macOS's
    /// permission prompt, so calling this from the pre-recording screen moves
    /// that prompt to *before* the meeting starts instead of surfacing it
    /// mid-recording. Runs off the main actor to match how capture itself
    /// touches ScreenCaptureKit.
    func refreshSystemAudioPermission() async {
        let granted = await Task.detached { () -> Bool in
            ((try? await SCShareableContent.current) != nil)
        }.value
        systemAudioGranted = granted
    }

    /// Deep-link to System Settings so the user can grant screen recording.
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func closeLiveChatPanel() {
        showLiveChatPanel = false
    }

    private func doStartRecording() async {
        let startDate = Date()

        do {
            let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
                : meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            // Claim the meeting folder once, up front, uniquified so a second
            // meeting with the same title on the same day cannot overwrite the
            // first. Everything this recording produces goes here.
            let meetingDir = LocalStorage.uniqueMeetingDirectory(
                title: title, date: startDate, baseDirectory: outputDirectory
            )
            try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)
            currentMeetingDirectory = meetingDir

            let writer = AudioFileWriter(directory: meetingDir)
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
                    guard let self = self else { return }
                    self.audioLevel = capturedLevel
                }
            }
            audioCaptureManager.onSystemAudio = { sampleBuffer in
                writer.writeSystemAudio(sampleBuffer: sampleBuffer)
            }

            try await audioCaptureManager.startCapture()

            // The writer must be open before we claim to be recording —
            // otherwise the whole meeting streams into a file that was never
            // created and the audio is lost with no indication.
            guard let format = audioCaptureManager.micFormat else {
                throw AudioCaptureManager.CaptureError.microphoneUnavailable("no input format available")
            }
            try writer.start(format: format)

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
            // Tear down so a half-started capture doesn't leave the microphone
            // running with no way to stop it from the UI.
            await audioCaptureManager.stopCapture()
            audioFileWriter = nil
            isRecording = false
            recordingStartDate = nil
            timer?.invalidate()
            timer = nil

            // Release the folder we claimed, so a failed start doesn't leave an
            // empty directory that pushes the next recording to a `-2` suffix.
            if let claimed = currentMeetingDirectory {
                let contents = try? FileManager.default.contentsOfDirectory(atPath: claimed.path)
                if contents?.isEmpty != false {
                    try? FileManager.default.removeItem(at: claimed)
                }
            }
            currentMeetingDirectory = nil

            statusMessage = error.localizedDescription
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
        let recordingDirectory = currentMeetingDirectory
        currentMeetingDirectory = nil

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

        // === Phase 2: Finalize audio. This must complete before a new
        // recording can start (otherwise the shared audioCaptureManager and
        // writer objects can enter a broken state). toggleRecording refuses
        // new starts while `isFinalizingPreviousRecording` is true.
        isFinalizingPreviousRecording = true

        await audioCaptureManager.stopCapture()
        isRecording = false

        let stopResult = writerToFinalize?.stop()

        isFinalizingPreviousRecording = false

        guard let recordingDirectory else {
            statusMessage = "Recording failed — no meeting folder was created."
            return
        }

        // The title may have been edited while recording (that is what the
        // recording top bar is for). Bring the folder along so the audio stays
        // with the transcript and metadata instead of being orphaned.
        let meetingDir = LocalStorage.reconcileMeetingDirectory(
            recordingDirectory,
            toTitle: capturedTitle,
            date: startDate,
            baseDirectory: capturedOutputDir
        )

        // The audio moved with its folder, so re-derive its path.
        let audioURL = stopResult?.url.map {
            meetingDir.appendingPathComponent($0.lastPathComponent)
        }
        lastRecordingAudioURL = audioURL

        lastRecordingWarning = (stopResult?.systemAudioDropped == true)
            ? (stopResult?.ffmpegAvailable == false
                ? "System audio was recorded but couldn't be merged because ffmpeg isn't installed — this meeting has your microphone only. Install ffmpeg in Settings → Setup."
                : "System audio was recorded but the merge failed — this meeting has your microphone only.")
            : nil

        guard let finalAudioURL = audioURL else {
            statusMessage = "No audio was captured — nothing to transcribe."
            return
        }

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
                meetingDirectory: meetingDir,
                startDate: startDate,
                duration: duration,
                title: capturedTitle,
                meetingType: capturedMeetingType,
                notes: capturedNotes,
                calendarEventTitle: capturedEventTitle,
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
        meetingDirectory: URL,
        startDate: Date,
        duration: TimeInterval,
        title: String,
        meetingType: String?,
        notes: String,
        calendarEventTitle: String?,
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
            statusMessage = "Transcription not set up — open Settings to install it"
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

        // Write into the folder this recording already owns — never recompute
        // it from the title, which is how audio and transcript used to diverge.
        let meetingDir = meetingDirectory
        lastRecordingMarkdownURL = try? LocalStorage.save(markdown: markdown, to: meetingDir)

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

    /// Dismiss the post-recording view and ask the dashboard to open this
    /// meeting's detail page. This is what "View Meeting" invokes: on its own,
    /// leaving `showPostRecording` true kept the recording view on screen and
    /// the button appeared to do nothing.
    func viewCompletedMeeting(_ meeting: LocalMeeting) {
        showPostRecording = false
        lastRecordingWarning = nil
        lastRecordingAudioURL = nil
        lastRecordingMarkdownURL = nil
        lastTranscriptSnippet = nil
        statusMessage = nil
        meetingToOpen = meeting
    }

    func showMeetingSummary(_ meeting: LocalMeeting) {
        currentMeeting = meeting
        // The warning belongs to the recording that just finished, not to an
        // older meeting the user navigated to.
        lastRecordingWarning = nil
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
        lastRecordingWarning = nil
        currentMeeting = nil
        statusMessage = nil
    }

}
