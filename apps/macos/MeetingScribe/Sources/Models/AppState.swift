import Foundation
import SwiftUI
import UserNotifications
@preconcurrency import ScreenCaptureKit

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recentRecordings: [Recording] = []
    @Published var serverStatus: ServerStatus = .unknown
    @Published var errorMessage: String? = nil
    @Published var showPermissionAlert = false

    @AppStorage("serverURL") var serverURL = "http://localhost:3000"
    @AppStorage("outputDirectory") var outputDirectory = "~/MeetingScribe"
    @AppStorage("saveAudio") var saveAudio = false

    private var timer: Timer?
    private var recordingStartDate: Date?
    private let audioCaptureManager = AudioCaptureManager()
    private let transcriptionManager = TranscriptionManager()
    private let uploadQueue = UploadQueue()

    func startRecording() {
        errorMessage = nil

        Task { @MainActor in
            // Check ScreenCaptureKit permission first
            do {
                _ = try await SCShareableContent.current
            } catch {
                self.errorMessage = "Screen & System Audio Recording permission required.\nGo to System Settings > Privacy & Security > Screen & System Audio Recording and add this app."
                self.showPermissionAlert = true
                return
            }

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
                try await audioCaptureManager.startCapture()

                recordingStartDate = Date()
                isRecording = true
                recordingDuration = 0
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.recordingDuration += 1
                    }
                }
            } catch {
                self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                print("Failed to start recording: \(error)")
            }
        }
    }

    func stopRecording() {
        Task { @MainActor in
            await audioCaptureManager.stopCapture()
            timer?.invalidate()
            timer = nil
            isRecording = false

            guard let startDate = recordingStartDate else { return }
            let title = "Meeting \(startDate.formatted(.dateTime.month().day().hour().minute()))"

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
            } catch {
                await uploadQueue.enqueue(UploadQueue.PendingUpload(
                    filePath: recentRecordings.first?.filePath ?? "",
                    title: title,
                    date: startDate,
                    duration: Int(recordingDuration),
                    audioSources: ["system", "microphone"],
                    meetingType: nil
                ))
            }

            transcriptionManager.reset()

            // Show notification
            let content = UNMutableNotificationContent()
            content.title = "Meeting Saved"
            content.body = "\(title) — \(MarkdownFormatter.formatDuration(recordingDuration))"
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
