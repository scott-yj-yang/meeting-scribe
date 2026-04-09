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

    /// whisper.cpp -ojf JSON format: segments live under "transcription",
    /// timestamps are in "offsets" (milliseconds), and confidence is per-token "p".
    struct WhisperToken: Decodable {
        let text: String
        let p: Double  // token probability (0.0-1.0)
    }

    struct WhisperOffsets: Decodable {
        let from: Int  // milliseconds
        let to: Int    // milliseconds
    }

    struct WhisperSegment: Decodable {
        let text: String
        let offsets: WhisperOffsets
        let tokens: [WhisperToken]?

        /// Average token probability (excluding special tokens).
        var avgTokenProb: Double {
            guard let tokens = tokens else { return 1.0 }
            let real = tokens.filter { !$0.text.hasPrefix("[") && !$0.text.hasPrefix("<") }
            guard !real.isEmpty else { return 1.0 }
            return real.map(\.p).reduce(0, +) / Double(real.count)
        }

        var startSeconds: Double { Double(offsets.from) / 1000.0 }
        var endSeconds: Double { Double(offsets.to) / 1000.0 }
    }

    struct WhisperJSON: Decodable {
        let transcription: [WhisperSegment]
    }

    /// Minimum average token probability — segments below this are likely hallucinated.
    static let minAvgTokenProb = 0.4

    /// Known whisper hallucination phrases from YouTube training data.
    /// Matched case-insensitively after stripping punctuation.
    static let hallucinationPhrases: Set<String> = [
        "thank you for watching",
        "thanks for watching",
        "thanks for listening",
        "thank you for listening",
        "subscribe to my channel",
        "please subscribe",
        "like and subscribe",
        "please like and subscribe",
        "don't forget to subscribe",
        "hit the bell icon",
        "see you in the next video",
        "see you next time",
        "leave a comment below",
        "check out my other videos",
        "turn on notifications",
        "subtitles by",
        "subtitles created by",
        "translated by",
        "amara org",
        "you",
        "bye bye",
        "谢谢观看",
        "请订阅",
        "感谢收看",
        "字幕由",
    ]

    func transcribe(audioFile: URL) async throws -> TranscriptionResult {
        guard isAvailable else { throw WhisperError.notInstalled }

        let outputBase = NSTemporaryDirectory() + "meetingscribe-whisper-\(UUID().uuidString)"
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioFile.path,
            "-ojf",               // full JSON output (includes confidence metrics)
            "-of", outputBase,
            "-l", "auto",
            "--no-timestamps", "false",
            "-pp",                // print progress
            "-ml", "40",          // max segment length (chars)
            "-bo", "5",           // best-of candidates
            "-bs", "5",           // beam size
            "-et", "2.4",         // entropy threshold
            "-lpt", "-0.5",       // log probability threshold
            "-sns",               // suppress non-speech tokens
            "-mc", "0",           // max-context 0 — prevents cascading hallucinations
        ]

        // Add VAD if model available — filters silence to prevent hallucinations
        if let vadPath = WhisperPostProcessor.findVadModel() {
            process.arguments! += [
                "--vad-model", vadPath,
                "--vad-threshold", "0.5",
                "--vad-min-speech-duration-ms", "250",
                "--vad-min-silence-duration-ms", "100",
            ]
            print("[WhisperPostProcessor] VAD enabled (Silero)")
        }

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

        let jsonFile = outputBase + ".json"
        guard let jsonData = FileManager.default.contents(atPath: jsonFile) else {
            throw WhisperError.outputNotFound
        }

        let decoder = JSONDecoder()
        let whisperOutput = try decoder.decode(WhisperJSON.self, from: jsonData)

        // Filter out low-confidence segments using average token probability
        let confident = whisperOutput.transcription.filter { seg in
            seg.avgTokenProb >= WhisperPostProcessor.minAvgTokenProb
        }

        let filteredCount = whisperOutput.transcription.count - confident.count
        if filteredCount > 0 {
            print("[WhisperPostProcessor] Filtered \(filteredCount)/\(whisperOutput.transcription.count) low-confidence segments")
        }

        let rawText = confident.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        let (dehalluced, phraseCount) = WhisperPostProcessor.removeHallucinationPhrases(rawText)
        if phraseCount > 0 {
            print("[WhisperPostProcessor] Removed \(phraseCount) known hallucination phrases")
        }
        let trimmed = WhisperPostProcessor.collapseRepetitions(dehalluced)

        let mergedSegs = WhisperPostProcessor.mergeAtSentenceBoundaries(confident)
        let segments = mergedSegs.map { seg in
            TranscriptSegment(
                speaker: "Speaker",
                text: WhisperPostProcessor.collapseRepetitions(seg.text),
                startTime: seg.start,
                endTime: seg.end
            )
        }.filter { !$0.text.isEmpty }

        try? FileManager.default.removeItem(atPath: jsonFile)

        return TranscriptionResult(text: trimmed, segments: segments)
    }

    // MARK: - Post-processing

    /// Merge short whisper segments at sentence boundaries to avoid mid-sentence breaks.
    /// Consecutive segments are joined until the text ends with sentence punctuation
    /// or the merged duration exceeds maxDuration seconds.
    static func mergeAtSentenceBoundaries(_ segments: [WhisperSegment], maxDuration: Double = 30.0) -> [(text: String, start: Double, end: Double)] {
        guard !segments.isEmpty else { return [] }

        var merged: [(text: String, start: Double, end: Double)] = []
        var currentText = segments[0].text.trimmingCharacters(in: .whitespaces)
        var currentStart = segments[0].startSeconds
        var currentEnd = segments[0].endSeconds

        for i in 1..<segments.count {
            let seg = segments[i]
            let duration = seg.endSeconds - currentStart
            let endsWithPunctuation = currentText.hasSuffix(".") || currentText.hasSuffix("!") || currentText.hasSuffix("?")

            if endsWithPunctuation || duration > maxDuration {
                merged.append((text: currentText, start: currentStart, end: currentEnd))
                currentText = seg.text.trimmingCharacters(in: .whitespaces)
                currentStart = seg.startSeconds
                currentEnd = seg.endSeconds
            } else {
                currentText += " " + seg.text.trimmingCharacters(in: .whitespaces)
                currentEnd = seg.endSeconds
            }
        }
        // Don't forget the last accumulated segment
        merged.append((text: currentText, start: currentStart, end: currentEnd))

        return merged
    }

    /// Remove known hallucination phrases from transcript text.
    /// Returns the cleaned text and the count of phrases removed.
    static func removeHallucinationPhrases(_ text: String) -> (text: String, removedCount: Int) {
        var cleaned = text
        var removedCount = 0

        for phrase in hallucinationPhrases {
            let normalizedPhrase = phrase.lowercased()
            let escaped = NSRegularExpression.escapedPattern(for: normalizedPhrase)
            let pattern = "\\b\(escaped)\\b[.!?,;]*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                let matches = regex.numberOfMatches(in: cleaned, range: range)
                if matches > 0 {
                    removedCount += matches
                    cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
                }
            }
        }

        // Collapse multiple spaces left by removals
        cleaned = cleaned.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return (cleaned, removedCount)
    }

    /// Collapse repeated phrases that whisper.cpp hallucinates.
    /// Detects when any n-gram (1–25 words) repeats 3+ consecutive times
    /// and keeps only a single instance.
    static func collapseRepetitions(_ text: String) -> String {
        // Pass 1: Sentence-level dedup
        let sentenceCleaned = collapseSentenceRepetitions(text)

        // Pass 2+: Word-level n-gram collapse (with normalization)
        var words = sentenceCleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for _ in 0..<5 {
            let before = words
            words = collapsePass(words)
            if words == before { break }
        }
        return words.joined(separator: " ")
    }

    /// Collapse repeated sentences. Splits on sentence boundaries (. ! ?)
    /// and removes consecutive duplicates (normalized comparison).
    static func collapseSentenceRepetitions(_ text: String) -> String {
        let pattern = "(?<=[.!?])\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var lastEnd = text.startIndex
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let matchRange = match.flatMap({ Range($0.range, in: text) }) else { return }
            let sentence = String(text[lastEnd..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { sentences.append(sentence) }
            lastEnd = matchRange.upperBound
        }
        let last = String(text[lastEnd...]).trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { sentences.append(last) }

        guard sentences.count > 1 else { return text }

        var deduped: [String] = [sentences[0]]
        for i in 1..<sentences.count {
            let prev = sentences[i-1].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let curr = sentences[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if curr != prev {
                deduped.append(sentences[i])
            }
        }

        return deduped.joined(separator: " ")
    }

    /// Normalize a word for fuzzy repetition matching:
    /// lowercase + strip trailing/leading punctuation.
    private static func normalize(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .symbols)
    }

    private static func collapsePass(_ words: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < words.count {
            var bestLen = 0
            var bestCount = 0
            let maxPhraseLen = min(25, (words.count - i) / 2)
            for plen in stride(from: maxPhraseLen, through: 1, by: -1) {
                guard i + plen * 2 <= words.count else { continue }
                // Normalize for comparison (lowercase, strip punctuation)
                let phrase = (i..<i+plen).map { normalize(words[$0]) }
                var count = 1
                var j = i + plen
                while j + plen <= words.count {
                    let candidate = (j..<j+plen).map { normalize(words[$0]) }
                    if candidate == phrase {
                        count += 1
                        j += plen
                    } else {
                        break
                    }
                }
                if count >= 3 && plen * count > bestLen * bestCount {
                    bestLen = plen
                    bestCount = count
                }
            }
            if bestLen > 0 && bestCount >= 3 {
                // Keep the first occurrence (original casing/punctuation)
                result.append(contentsOf: words[i..<i+bestLen])
                i += bestLen * bestCount
            } else {
                result.append(words[i])
                i += 1
            }
        }
        return result
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

    private static func findVadModel() -> String? {
        let searchDirs = [
            "\(NSHomeDirectory())/.local/share/whisper-cpp",
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
            "\(NSHomeDirectory())/.local/share/whisper-cli",
            "/opt/homebrew/share/whisper-cli",
        ]
        for dir in searchDirs {
            let path = "\(dir)/silero-vad.onnx"
            if FileManager.default.fileExists(atPath: path) {
                return path
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
