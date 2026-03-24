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
    @AppStorage("saveAudio") var saveAudio = false

    private var timer: Timer?
    private var recordingStartDate: Date?
    private let audioCaptureManager = AudioCaptureManager()
    private let transcriptionManager = TranscriptionManager()
    private let uploadQueue = UploadQueue()

    // Called from button — schedules async work without crashing SwiftUI
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            // Update UI immediately, do async work in background
            statusMessage = "Starting..."
            Task.detached { [weak self] in
                await self?.doStartRecording()
            }
        }
    }

    private func doStartRecording() async {
        do {
            try await transcriptionManager.setup()
            let transcriber = transcriptionManager
            audioCaptureManager.onMicAudio = { buffer, time in
                nonisolated(unsafe) let buffer = buffer
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

            recordingStartDate = Date()
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
            print("Failed to start recording: \(error)")
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

        // Finalize transcription — saves any remaining partial text as segments
        transcriptionManager.finalize()

        guard let startDate = recordingStartDate else { return }
        let title = "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"

        print("[Recording] Stopped. \(transcriptionManager.segments.count) transcript segments.")

        let markdown = MarkdownFormatter.format(
            title: title,
            date: startDate,
            duration: recordingDuration,
            meetingType: nil,
            audioSources: ["system", "microphone"],
            segments: transcriptionManager.segments
        )

        // Save locally
        if let fileURL = try? LocalStorage.save(
            markdown: markdown,
            title: title,
            date: startDate,
            directory: outputDirectory
        ) {
            let recording = Recording(
                id: UUID(),
                title: title,
                date: startDate,
                duration: recordingDuration,
                filePath: fileURL.path
            )
            recentRecordings.insert(recording, at: 0)
            if recentRecordings.count > 5 { recentRecordings.removeLast() }
        }

        // Upload to server
        let client = MeetingAPIClient(serverURL: serverURL)
        do {
            _ = try await client.uploadMeeting(
                title: title,
                date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["system", "microphone"],
                meetingType: nil,
                rawMarkdown: markdown,
                segments: transcriptionManager.segments
            )
            statusMessage = "Meeting saved and uploaded"
        } catch {
            await uploadQueue.enqueue(UploadQueue.PendingUpload(
                filePath: recentRecordings.first?.filePath ?? "",
                title: title,
                date: startDate,
                duration: Int(recordingDuration),
                audioSources: ["system", "microphone"],
                meetingType: nil
            ))
            statusMessage = "Saved locally (server offline)"
        }

        transcriptionManager.reset()
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
