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
    private var lastSegmentEnd: TimeInterval = 0

    func setup() async throws {
        recordingStartTime = Date()
        segments.removeAll()
        liveText = ""

        // Request speech recognition authorization
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Enable on-device recognition for privacy and speed
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // Allow long-form audio (meetings)
        request.addsPunctuation = true

        self.recognitionRequest = request

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.liveText = text

                    // When we get a final result (end of utterance), save as a segment
                    if result.isFinal {
                        let elapsed = Date().timeIntervalSince(self.recordingStartTime)
                        let segment = TranscriptSegment(
                            speaker: "Speaker",
                            text: text,
                            startTime: self.lastSegmentEnd,
                            endTime: elapsed
                        )
                        self.segments.append(segment)
                        self.lastSegmentEnd = elapsed
                        self.liveText = ""

                        // Start a new recognition request for the next utterance
                        self.restartRecognition()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    // Error 1110 = "no speech detected" — normal, just restart
                    // Error 216 = "request was canceled" — normal during restart
                    if nsError.code != 1110 && nsError.code != 216 {
                        print("Recognition error: \(error.localizedDescription)")
                    }
                    // Save any partial text as a segment
                    if !self.liveText.isEmpty {
                        let elapsed = Date().timeIntervalSince(self.recordingStartTime)
                        let segment = TranscriptSegment(
                            speaker: "Speaker",
                            text: self.liveText,
                            startTime: self.lastSegmentEnd,
                            endTime: elapsed
                        )
                        self.segments.append(segment)
                        self.lastSegmentEnd = elapsed
                        self.liveText = ""
                    }

                    // Restart recognition (SFSpeechRecognizer has a ~1 min limit per request)
                    self.restartRecognition()
                }
            }
        }

        print("Live transcription started (on-device: \(recognizer.supportsOnDeviceRecognition))")
    }

    /// Feed microphone audio buffers to the recognizer
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, speaker: String) {
        recognitionRequest?.append(buffer)
    }

    /// System audio (CMSampleBuffer) — convert to PCM and feed to recognizer
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, speaker: String) {
        // For now, system audio is not fed to SFSpeechRecognizer
        // (it expects a single audio stream; mixing would require AVAudioMixerNode)
        // System audio transcription is handled by whisper.cpp post-processing
        _ = sampleBuffer
    }

    func reset() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognizer = nil
        segments.removeAll()
        liveText = ""
        lastSegmentEnd = 0
    }

    /// Restart recognition (needed because Apple limits each request to ~1 minute)
    private func restartRecognition() {
        guard let recognizer = recognizer, recognizer.isAvailable else { return }

        // End the current request
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        // Create a new request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true

        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    self.liveText = result.bestTranscription.formattedString

                    if result.isFinal {
                        let elapsed = Date().timeIntervalSince(self.recordingStartTime)
                        let segment = TranscriptSegment(
                            speaker: "Speaker",
                            text: result.bestTranscription.formattedString,
                            startTime: self.lastSegmentEnd,
                            endTime: elapsed
                        )
                        self.segments.append(segment)
                        self.lastSegmentEnd = elapsed
                        self.liveText = ""
                        self.restartRecognition()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code != 1110 && nsError.code != 216 {
                        print("Recognition error: \(error.localizedDescription)")
                    }
                    if !self.liveText.isEmpty {
                        let elapsed = Date().timeIntervalSince(self.recordingStartTime)
                        let segment = TranscriptSegment(
                            speaker: "Speaker",
                            text: self.liveText,
                            startTime: self.lastSegmentEnd,
                            endTime: elapsed
                        )
                        self.segments.append(segment)
                        self.lastSegmentEnd = elapsed
                        self.liveText = ""
                    }
                    self.restartRecognition()
                }
            }
        }
    }

    enum TranscriptionError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition not authorized. Check System Settings > Privacy & Security > Speech Recognition."
            case .recognizerUnavailable: return "Speech recognizer is not available."
            }
        }
    }
}
