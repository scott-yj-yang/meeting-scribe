import Foundation
import AVFoundation
import Speech

@MainActor
final class TranscriptionManager: ObservableObject, @unchecked Sendable {
    @Published var segments: [TranscriptSegment] = []
    @Published var liveText: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingStartTime = Date()

    // All saved text chunks (one per recognition session, ~1 min each)
    private var savedChunks: [(text: String, time: TimeInterval)] = []
    // Current session's cumulative text (grows as recognizer returns partials)
    private var currentSessionText: String = ""
    private var bufferCount = 0
    private var isRestarting = false
    private var isActive = false

    func setup() async throws {
        recordingStartTime = Date()
        segments.removeAll()
        savedChunks.removeAll()
        currentSessionText = ""
        liveText = ""
        bufferCount = 0
        isRestarting = false
        isActive = true

        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        startNewSession(recognizer: recognizer)
        print("[Transcription] Live transcription started (on-device: \(recognizer.supportsOnDeviceRecognition))")
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, speaker: String) {
        bufferCount += 1
        if bufferCount == 1 {
            print("[Transcription] Receiving audio buffers")
        }
        recognitionRequest?.append(buffer)
    }

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, speaker: String) {
        _ = sampleBuffer
    }

    /// Call when recording stops
    func finalize() {
        isActive = false

        // Save current session's text
        saveCurrentSession()

        // Convert all chunks to segments
        segments.removeAll()
        var lastEnd: TimeInterval = 0
        for chunk in savedChunks {
            let segment = TranscriptSegment(
                speaker: "Speaker",
                text: chunk.text,
                startTime: lastEnd,
                endTime: chunk.time
            )
            segments.append(segment)
            lastEnd = chunk.time
        }

        print("[Transcription] Finalized \(segments.count) segments from \(savedChunks.count) chunks")
        for (i, seg) in segments.enumerated() {
            print("[Transcription]   #\(i+1): \"\(seg.text.prefix(100))\"")
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    func reset() {
        isActive = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognizer = nil
        segments.removeAll()
        savedChunks.removeAll()
        currentSessionText = ""
        liveText = ""
        bufferCount = 0
    }

    // MARK: - Private

    private func saveCurrentSession() {
        let text = currentSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(recordingStartTime)
        savedChunks.append((text: text, time: elapsed))
        print("[Transcription] Saved chunk #\(savedChunks.count): \"\(text.prefix(100))\"")
        currentSessionText = ""
        liveText = ""
    }

    private func startNewSession(recognizer: SFSpeechRecognizer) {
        guard isActive else { return }

        // Clean up old session
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self, self.isActive else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        // This is CUMULATIVE — contains ALL text from session start
                        self.currentSessionText = text
                        self.liveText = self.fullTranscriptPreview()
                    }

                    if result.isFinal {
                        self.saveCurrentSession()
                        self.scheduleRestart()
                    }
                }

                if error != nil {
                    self.saveCurrentSession()
                    self.scheduleRestart()
                }
            }
        }
    }

    /// Show all saved text + current live text
    private func fullTranscriptPreview() -> String {
        let saved = savedChunks.map(\.text).joined(separator: " ")
        if saved.isEmpty {
            return currentSessionText
        }
        if currentSessionText.isEmpty {
            return saved
        }
        return saved + " " + currentSessionText
    }

    private func scheduleRestart() {
        guard isActive, !isRestarting else { return }
        isRestarting = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard self.isActive else { return }
            self.isRestarting = false

            if let recognizer = self.recognizer, recognizer.isAvailable {
                self.startNewSession(recognizer: recognizer)
            }
        }
    }

    enum TranscriptionError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition not authorized."
            case .recognizerUnavailable: return "Speech recognizer not available."
            }
        }
    }
}
