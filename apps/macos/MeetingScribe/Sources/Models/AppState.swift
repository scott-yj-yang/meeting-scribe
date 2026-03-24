import Foundation
import SwiftUI
import UserNotifications

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recentRecordings: [Recording] = []
    @Published var serverStatus: ServerStatus = .unknown
    @Published var statusMessage: String? = nil

    @AppStorage("serverURL") var serverURL = "http://localhost:3000"
    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = true

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
            statusMessage = "Starting..."
            Task.detached { [weak self] in
                await self?.doStartRecording()
            }
        }
    }

    private func doStartRecording() async {
        let startDate = Date()

        do {
            // Start live transcription (UI display only — whisper.cpp does the real transcript)
            try await transcriptionManager.setup()
            let transcriber = transcriptionManager

            // Set up audio file writer for whisper.cpp
            let title = "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
            let writer = AudioFileWriter(directory: outputDirectory, title: title, date: startDate)
            self.audioFileWriter = writer

            audioCaptureManager.onMicAudio = { buffer, time in
                nonisolated(unsafe) let buffer = buffer
                // Save audio to file for whisper.cpp
                writer.write(buffer: buffer)
                // Feed to live transcription (UI only)
                Task { @MainActor in
                    transcriber.processAudioBuffer(buffer, speaker: "Local")
                }
            }
            audioCaptureManager.onSystemAudio = { sampleBuffer in
                nonisolated(unsafe) let sampleBuffer = sampleBuffer
                Task { @MainActor in
                    transcriber.processSampleBuffer(sampleBuffer, speaker: "Remote")
                }
            }

            await audioCaptureManager.startCapture()

            // Start audio file writer
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
        isRecording = false

        // Stop live transcription (it was just for UI)
        transcriptionManager.reset()

        // Stop audio file writer
        guard let writer = audioFileWriter else { return }
        let audioURL = writer.stop()
        audioFileWriter = nil

        guard let startDate = recordingStartDate else { return }
        let title = "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"

        print("[Recording] Stopped. Audio: \(audioURL.path)")
        statusMessage = "Transcribing with whisper.cpp..."

        // Run whisper.cpp for accurate, complete transcript
        var segments: [TranscriptSegment] = []
        if whisperProcessor.isAvailable {
            do {
                print("[Whisper] Transcribing...")
                let result = try await whisperProcessor.transcribe(audioFile: audioURL)
                segments = result.segments
                print("[Whisper] Done — \(segments.count) segments")
            } catch {
                print("[Whisper] Failed: \(error.localizedDescription)")
                statusMessage = "Transcription failed. Audio saved."
            }
        } else {
            print("[Whisper] Not installed. Run: brew install whisper-cpp")
            statusMessage = "Install whisper-cpp for transcription"
        }

        let markdown = MarkdownFormatter.format(
            title: title,
            date: startDate,
            duration: recordingDuration,
            meetingType: nil,
            audioSources: audioCaptureManager.captureMode == .micAndSystem
                ? ["system", "microphone"] : ["microphone"],
            segments: segments
        )

        // Save markdown locally
        if let fileURL = try? LocalStorage.save(
            markdown: markdown, title: title, date: startDate, directory: outputDirectory
        ) {
            let recording = Recording(
                id: UUID(), title: title, date: startDate,
                duration: recordingDuration, filePath: fileURL.path
            )
            recentRecordings.insert(recording, at: 0)
            if recentRecordings.count > 5 { recentRecordings.removeLast() }
        }

        // Upload to server
        let client = MeetingAPIClient(serverURL: serverURL)
        do {
            _ = try await client.uploadMeeting(
                title: title, date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["microphone"],
                meetingType: nil,
                rawMarkdown: markdown,
                segments: segments
            )
            statusMessage = "Meeting saved (\(segments.count) segments)"
        } catch {
            await uploadQueue.enqueue(UploadQueue.PendingUpload(
                filePath: recentRecordings.first?.filePath ?? "",
                title: title, date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["microphone"],
                meetingType: nil
            ))
            statusMessage = "Saved locally (server offline)"
        }

        let content = UNMutableNotificationContent()
        content.title = "Meeting Saved"
        content.body = "\(title) — \(segments.count) segments"
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

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
    let filePath: String
}

enum ServerStatus {
    case connected, disconnected, unknown
}
