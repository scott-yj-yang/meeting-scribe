import Foundation

/// Runs whisper.cpp on a saved audio file to produce a high-accuracy transcript.
/// This replaces the live SpeechTranscriber transcript with a more accurate version.
///
/// Architecture:
///   - During recording: SpeechTranscriber provides live (lower accuracy) transcript
///   - After recording: whisper.cpp produces final (higher accuracy) transcript with diarization
///   - The final transcript is what gets uploaded to the web app
final class WhisperPostProcessor: @unchecked Sendable {

    struct TranscriptionResult {
        let text: String
        let segments: [TranscriptSegment]
    }

    /// Path to the whisper-cpp binary
    private let whisperPath: String

    /// Path to the GGML model file
    private let modelPath: String

    init() {
        // whisper-cpp 1.8+ installs as "whisper-cli"
        self.whisperPath = WhisperPostProcessor.findBinary("whisper-cli")
            ?? WhisperPostProcessor.findBinary("whisper-cpp")
            ?? "/opt/homebrew/bin/whisper-cli"

        self.modelPath = WhisperPostProcessor.findModel() ?? ""
    }

    /// Check if whisper.cpp is available
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: whisperPath) &&
        FileManager.default.fileExists(atPath: modelPath)
    }

    /// Transcribe an audio file using whisper.cpp
    func transcribe(audioFile: URL) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw WhisperError.notInstalled
        }

        let outputBase = NSTemporaryDirectory() + "meetingscribe-whisper-\(UUID().uuidString)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioFile.path,
            "-otxt",
            "-of", outputBase,
            "-l", "auto",          // Auto-detect language
            "--no-timestamps", "false",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WhisperError.transcriptionFailed
        }

        let txtFile = outputBase + ".txt"
        guard let text = try? String(contentsOfFile: txtFile, encoding: .utf8) else {
            throw WhisperError.outputNotFound
        }

        // Parse the text into segments (simple line-based parsing)
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let segments = lines.enumerated().map { index, line in
            TranscriptSegment(
                speaker: "Speaker",
                text: line.trimmingCharacters(in: .whitespaces),
                startTime: TimeInterval(index * 5),  // Approximate timing
                endTime: TimeInterval((index + 1) * 5)
            )
        }

        // Cleanup
        try? FileManager.default.removeItem(atPath: txtFile)

        return TranscriptionResult(text: text, segments: segments)
    }

    // MARK: - Private

    private static func findBinary(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func findModel() -> String? {
        let modelNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
        ]

        let searchDirs = [
            "\(NSHomeDirectory())/.local/share/whisper-cpp",
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
        ]

        for dir in searchDirs {
            for model in modelNames {
                let path = "\(dir)/\(model)"
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        }

        return nil
    }

    enum WhisperError: Error, LocalizedError {
        case notInstalled
        case transcriptionFailed
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "whisper-cli not found. Install with: brew install whisper-cpp"
            case .transcriptionFailed: return "whisper.cpp transcription failed"
            case .outputNotFound: return "whisper.cpp output file not found"
            }
        }
    }
}
