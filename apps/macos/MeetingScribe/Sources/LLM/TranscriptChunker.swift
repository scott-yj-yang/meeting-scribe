import Foundation

/// Token-count based chunker for long transcripts.
/// Ported from meetily's `frontend/src-tauri/src/summary/processor.rs:21-93`.
enum TranscriptChunker {

    /// Rough estimate: ~3 characters per token. Conservative compared to meetily's 0.35.
    static func roughTokenCount(_ text: String) -> Int {
        text.count / 3
    }

    /// Split `text` into chunks of ≤ `maxTokens` with `overlap` tokens of overlap between consecutive chunks.
    /// Splits on word boundaries.
    static func chunk(_ text: String, maxTokens: Int = 3000, overlap: Int = 100) -> [String] {
        let tokenCount = roughTokenCount(text)
        if tokenCount <= maxTokens {
            return [text]
        }

        // Split by whitespace into "words" (our tokens for chunking purposes)
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        // How many words per chunk? Assume 1 word ≈ 1.3 tokens roughly — so chunkWordCount * 1.3 ≈ maxTokens
        // Conservatively: chunkWordCount ≈ maxTokens * 0.75
        let chunkWordCount = max(1, Int(Double(maxTokens) * 0.75))
        let overlapWordCount = max(0, Int(Double(overlap) * 0.75))

        var chunks: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + chunkWordCount, words.count)
            let slice = words[start..<end].joined(separator: " ")
            chunks.append(slice)
            if end == words.count { break }
            start = end - overlapWordCount
        }
        return chunks
    }
}
