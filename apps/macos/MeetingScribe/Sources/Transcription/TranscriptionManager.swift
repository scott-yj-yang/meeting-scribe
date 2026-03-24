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

        // Check current auth status (don't request — it crashes in Swift 6 due to TCC callback threading)
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            // First time: user needs to grant permission via System Settings
            print("Speech recognition permission not yet granted.")
            print("Go to: System Settings > Privacy & Security > Speech Recognition")
            throw TranscriptionError.notAuthorized
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
                    if !text.isEmpty {
                        print("[Transcription] Got text: \"\(text.prefix(80))\" (final: \(result.isFinal))")
                        self.liveText = text
                    }

                    if result.isFinal {
                        // Save whatever text we accumulated (liveText has the last non-empty partial)
                        self.saveCurrentText()
                        self.restartRecognition()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code != 216 {
                        print("[Transcription] Recognition ended: \(error.localizedDescription)")
                    }
                    // Save any accumulated text before restarting
                    self.saveCurrentText()
                    self.restartRecognition()
                }
            }
        }

        print("[Transcription] Live transcription started (on-device: \(recognizer.supportsOnDeviceRecognition), locale: \(recognizer.locale))")
        print("[Transcription] Auth status: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
        print("[Transcription] Recognizer available: \(recognizer.isAvailable)")
    }

    private var bufferCount = 0

    /// Feed microphone audio buffers to the recognizer
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, speaker: String) {
        bufferCount += 1
        if bufferCount == 1 {
            print("[Transcription] Receiving audio buffers (format: \(buffer.format))")
        }
        if bufferCount % 100 == 0 {
            print("[Transcription] Processed \(bufferCount) buffers, segments so far: \(segments.count)")
        }
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

    /// Save current partial text as a transcript segment
    private func saveCurrentText() {
        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(recordingStartTime)
        let segment = TranscriptSegment(
            speaker: "Speaker",
            text: text,
            startTime: lastSegmentEnd,
            endTime: elapsed
        )
        segments.append(segment)
        lastSegmentEnd = elapsed
        liveText = ""
        print("[Transcription] Saved segment #\(segments.count): \"\(text.prefix(80))\"")
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
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        self.liveText = text
                    }
                    if result.isFinal {
                        self.saveCurrentText()
                        self.restartRecognition()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code != 216 {
                        print("[Transcription] Recognition ended: \(error.localizedDescription)")
                    }
                    self.saveCurrentText()
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
