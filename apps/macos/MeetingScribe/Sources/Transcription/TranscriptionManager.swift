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

    // Accumulate all recognized utterances
    private var allUtterances: [(text: String, time: TimeInterval)] = []
    private var currentPartialText: String = ""
    private var bufferCount = 0

    func setup() async throws {
        recordingStartTime = Date()
        segments.removeAll()
        allUtterances.removeAll()
        currentPartialText = ""
        liveText = ""
        bufferCount = 0

        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            print("[Transcription] Not authorized (status: \(status.rawValue))")
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

    /// Call this when recording stops to finalize all segments
    func finalize() {
        // Save any remaining partial text
        if !currentPartialText.isEmpty {
            let elapsed = Date().timeIntervalSince(recordingStartTime)
            allUtterances.append((text: currentPartialText, time: elapsed))
            currentPartialText = ""
        }

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

        // Stop recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    func reset() {
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

    private func startNewRecognitionRequest(recognizer: SFSpeechRecognizer) {
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
                self.handleRecognitionResult(result: result, error: error)
            }
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            let text = result.bestTranscription.formattedString
            if !text.isEmpty {
                currentPartialText = text
                liveText = text
            }

            if result.isFinal {
                // Utterance complete — save it
                if !currentPartialText.isEmpty {
                    let elapsed = Date().timeIntervalSince(recordingStartTime)
                    allUtterances.append((text: currentPartialText, time: elapsed))
                    print("[Transcription] Saved utterance #\(allUtterances.count): \"\(currentPartialText.prefix(80))\"")
                    currentPartialText = ""
                    liveText = ""
                }
                // Restart for next utterance
                if let recognizer = recognizer, recognizer.isAvailable {
                    startNewRecognitionRequest(recognizer: recognizer)
                }
            }
        }

        if let error = error {
            let nsError = error as NSError
            // Save current partial text before restarting
            if !currentPartialText.isEmpty {
                let elapsed = Date().timeIntervalSince(recordingStartTime)
                allUtterances.append((text: currentPartialText, time: elapsed))
                print("[Transcription] Saved utterance #\(allUtterances.count) (on pause): \"\(currentPartialText.prefix(80))\"")
                currentPartialText = ""
                liveText = ""
            }

            if nsError.code != 216 { // 216 = canceled (normal during restart)
                print("[Transcription] Recognition cycle ended: \(error.localizedDescription)")
            }

            // Restart recognition (SFSpeechRecognizer has ~1 min limit per request)
            if let recognizer = recognizer, recognizer.isAvailable {
                startNewRecognitionRequest(recognizer: recognizer)
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
