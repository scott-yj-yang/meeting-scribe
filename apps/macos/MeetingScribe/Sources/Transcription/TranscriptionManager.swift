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

    private var allUtterances: [(text: String, time: TimeInterval)] = []
    private var currentPartialText: String = ""
    private var lastTextUpdateTime: Date = Date()
    private var saveTimer: Timer?
    private var bufferCount = 0
    private var isRestarting = false
    private var isActive = false

    func setup() async throws {
        recordingStartTime = Date()
        segments.removeAll()
        allUtterances.removeAll()
        currentPartialText = ""
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

        startNewRecognitionRequest(recognizer: recognizer)
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
        saveTimer?.invalidate()
        saveTimer = nil

        // Save any remaining partial text
        savePartialText()

        // Convert all utterances to segments
        segments.removeAll()
        var lastEnd: TimeInterval = 0
        for utterance in allUtterances {
            let segment = TranscriptSegment(
                speaker: "Speaker",
                text: utterance.text,
                startTime: lastEnd,
                endTime: utterance.time
            )
            segments.append(segment)
            lastEnd = utterance.time
        }

        print("[Transcription] Finalized \(segments.count) segments from \(allUtterances.count) utterances")

        // Clean up recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    func reset() {
        isActive = false
        saveTimer?.invalidate()
        saveTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognizer = nil
        segments.removeAll()
        allUtterances.removeAll()
        currentPartialText = ""
        liveText = ""
        bufferCount = 0
    }

    // MARK: - Private

    private func savePartialText() {
        let text = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(recordingStartTime)
        allUtterances.append((text: text, time: elapsed))
        print("[Transcription] Saved utterance #\(allUtterances.count): \"\(text.prefix(100))\"")
        currentPartialText = ""
        liveText = ""
    }

    private func startNewRecognitionRequest(recognizer: SFSpeechRecognizer) {
        guard isActive else { return }

        // Clean up old request
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
                        self.currentPartialText = text
                        self.liveText = text
                        self.lastTextUpdateTime = Date()

                        // Auto-save after 2 seconds of no new text (pause between sentences)
                        self.saveTimer?.invalidate()
                        self.saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.savePartialText()
                            }
                        }
                    }

                    if result.isFinal {
                        self.saveTimer?.invalidate()
                        self.savePartialText()
                        self.scheduleRestart()
                    }
                }

                if error != nil {
                    self.saveTimer?.invalidate()
                    self.savePartialText()
                    self.scheduleRestart()
                }
            }
        }
    }

    /// Debounced restart to prevent cascading restarts
    private func scheduleRestart() {
        guard isActive, !isRestarting else { return }
        isRestarting = true

        // Small delay to let any cascading callbacks settle
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard self.isActive else { return }
            self.isRestarting = false

            if let recognizer = self.recognizer, recognizer.isAvailable {
                self.startNewRecognitionRequest(recognizer: recognizer)
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
