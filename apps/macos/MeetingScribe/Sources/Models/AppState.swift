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

    @AppStorage("serverURL") var serverURL = "http://localhost:3000"
    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = true
    @AppStorage("enableLiveTranscript") var enableLiveTranscript = false

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
        let useLive = enableLiveTranscript

        do {
            // Only start live transcription if enabled (saves CPU)
            if useLive {
                try await transcriptionManager.setup()
            }
            let transcriber = transcriptionManager

            // Determine title
            let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
                : meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let writer = AudioFileWriter(directory: outputDirectory, title: title, date: startDate)
            self.audioFileWriter = writer

            audioCaptureManager.onMicAudio = { buffer, time in
                nonisolated(unsafe) let buffer = buffer
                writer.write(buffer: buffer)
                if useLive {
                    Task { @MainActor in
                        transcriber.processAudioBuffer(buffer, speaker: "Local")
                    }
                }
            }
            audioCaptureManager.onSystemAudio = { sampleBuffer in
                nonisolated(unsafe) let sampleBuffer = sampleBuffer
                if useLive {
                    Task { @MainActor in
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
        isRecording = false
        transcriptionManager.reset()

        guard let writer = audioFileWriter else { return }
        let audioURL = writer.stop()
        audioFileWriter = nil

        guard let startDate = recordingStartDate else { return }
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"
            : meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Recording] Stopped. Audio: \(audioURL.path)")
        statusMessage = "Transcribing..."

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
            print("[Whisper] Not installed.")
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
            statusMessage = "\(title) saved (\(segments.count) segments)"
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

        // Clear title for next recording
        meetingTitle = ""
        print("[Recording] Complete: \(title) — \(segments.count) segments")
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
