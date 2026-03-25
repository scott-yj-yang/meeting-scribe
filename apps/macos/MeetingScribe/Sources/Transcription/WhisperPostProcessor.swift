import Foundation

/// Runs whisper.cpp on a saved audio file to produce a high-accuracy transcript.
final class WhisperPostProcessor: @unchecked Sendable {

    struct TranscriptionResult {
        let text: String
        let segments: [TranscriptSegment]
    }

    private let whisperPath: String
    private let modelPath: String

    /// Called on main thread with progress (0.0-1.0) and ETA string
    var onProgress: (@MainActor (Double, String) -> Void)?

    init() {
        self.whisperPath = WhisperPostProcessor.findBinary("whisper-cli")
            ?? WhisperPostProcessor.findBinary("whisper-cpp")
            ?? "/opt/homebrew/bin/whisper-cli"
        self.modelPath = WhisperPostProcessor.findModel() ?? ""
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: whisperPath) &&
        FileManager.default.fileExists(atPath: modelPath)
    }

    func transcribe(audioFile: URL) async throws -> TranscriptionResult {
        guard isAvailable else { throw WhisperError.notInstalled }

        let outputBase = NSTemporaryDirectory() + "meetingscribe-whisper-\(UUID().uuidString)"
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioFile.path,
            "-otxt",
            "-of", outputBase,
            "-l", "auto",
            "--no-timestamps", "false",
            "-pp",       // print progress
            "-ml", "80", // max segment length (chars) — prevents hallucination loops
            "-bo", "3",  // best-of candidates — improves accuracy
            "-et", "2.2", // entropy threshold — reject low-confidence (hallucinated) segments
        ]

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        // Parse progress from stderr in real-time
        let progressCallback = onProgress
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

            // whisper outputs: "whisper_print_progress_callback: progress =  45%"
            if line.contains("progress =") {
                let parts = line.components(separatedBy: "=")
                if let last = parts.last,
                   let pctStr = last.trimmingCharacters(in: .whitespaces).components(separatedBy: "%").first,
                   let pct = Double(pctStr.trimmingCharacters(in: .whitespaces)) {
                    let progress = pct / 100.0
                    let elapsed = Date().timeIntervalSince(startTime)

                    // Calculate ETA
                    var eta = ""
                    if progress > 0.01 {
                        let totalEstimate = elapsed / progress
                        let remaining = totalEstimate - elapsed
                        if remaining > 60 {
                            eta = String(format: "~%.0fm left", remaining / 60)
                        } else if remaining > 5 {
                            eta = String(format: "~%.0fs left", remaining)
                        } else {
                            eta = "almost done"
                        }
                    }

                    if let callback = progressCallback {
                        Task { @MainActor in
                            callback(progress, eta)
                        }
                    }
                }
            }
        }

        try process.run()

        // Wait for completion without blocking MainActor
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw WhisperError.transcriptionFailed
        }

        let txtFile = outputBase + ".txt"
        guard let text = try? String(contentsOfFile: txtFile, encoding: .utf8) else {
            throw WhisperError.outputNotFound
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let segments = trimmed.isEmpty ? [] : [
            TranscriptSegment(
                speaker: "Speaker",
                text: trimmed,
                startTime: 0,
                endTime: 0
            )
        ]

        try? FileManager.default.removeItem(atPath: txtFile)

        return TranscriptionResult(text: trimmed, segments: segments)
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
