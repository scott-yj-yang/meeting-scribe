import Foundation

/// One whisper invocation against a slice WAV. Pure: takes paths in, returns
/// chunks. Caller is responsible for serializing invocations and deleting
/// the slice file after success/failure.
enum WhisperLiveJob {
    /// Runs whisper-cli against `sliceURL`. Segments returned have their
    /// timestamps offset by `sliceStartOffset` (seconds since recording start),
    /// so the caller doesn't have to do bookkeeping.
    static func run(
        whisperBinary: String,
        vadModel: String?,
        sliceURL: URL,
        sliceStartOffset: TimeInterval,
        speaker: String
    ) async throws -> [LiveTranscriptChunk] {
        let tempJSONBase = sliceURL.deletingPathExtension().path
        var args: [String] = [
            "-f", sliceURL.path,
            "-oj", "-np",
            "-of", tempJSONBase,
            "-l", "en",
            "-t", "4",
        ]
        if let vadModel {
            args += ["--vad", "--vad-model", vadModel]
        }

        // Find an installed model. WhisperPostProcessor's `findModel()` does the
        // same search; we duplicate it here to keep the job self-contained.
        guard let modelPath = findModel() else {
            throw LiveTranscriberError.processFailed("No whisper model found in known paths")
        }
        args += ["-m", modelPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperBinary)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // discard

        do {
            try process.run()
        } catch {
            throw LiveTranscriberError.processFailed("Failed to launch: \(error.localizedDescription)")
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw LiveTranscriberError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let jsonURL = URL(fileURLWithPath: tempJSONBase + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            throw LiveTranscriberError.jsonParseFailed("Output JSON not found at \(jsonURL.path)")
        }

        return try parseSegments(
            jsonData: jsonData,
            sliceStartOffset: sliceStartOffset,
            speaker: speaker
        )
    }

    /// Parses whisper-cli's `-oj` JSON output into chunks. Each segment in
    /// the JSON's `transcription` array has `offsets.from`/`offsets.to`
    /// in milliseconds (relative to slice start). We add `sliceStartOffset`
    /// to map them back to seconds-since-recording-start.
    static func parseSegments(
        jsonData: Data,
        sliceStartOffset: TimeInterval,
        speaker: String
    ) throws -> [LiveTranscriptChunk] {
        struct Root: Decodable {
            let transcription: [Segment]
        }
        struct Segment: Decodable {
            let text: String
            let offsets: Offsets
        }
        struct Offsets: Decodable {
            let from: Int
            let to: Int
        }

        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: jsonData)
        } catch {
            throw LiveTranscriberError.jsonParseFailed(error.localizedDescription)
        }

        return root.transcription.compactMap { seg in
            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LiveTranscriptChunk(
                text: trimmed,
                startTime: sliceStartOffset + Double(seg.offsets.from) / 1000.0,
                endTime: sliceStartOffset + Double(seg.offsets.to) / 1000.0,
                speaker: speaker
            )
        }
    }

    private static func findModel() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let modelDirs = [
            "\(home)/.local/share/whisper-cpp",
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
        ]
        let modelNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
        ]
        for dir in modelDirs {
            for name in modelNames {
                let path = "\(dir)/\(name)"
                if fm.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }
}
