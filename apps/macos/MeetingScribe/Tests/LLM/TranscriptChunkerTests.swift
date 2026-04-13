import Testing
@testable import MeetingScribe

@Suite("TranscriptChunker")
struct TranscriptChunkerTests {

    @Test("rough token count approximates char divide 3")
    func testRoughTokenCountApproximatesCharDivide3() {
        #expect(TranscriptChunker.roughTokenCount("abc") == 1)       // 3 chars → 1
        #expect(TranscriptChunker.roughTokenCount("abcdefghi") == 3) // 9 chars → 3
        #expect(TranscriptChunker.roughTokenCount("") == 0)
    }

    @Test("short transcript returns single chunk")
    func testShortTranscriptReturnsSingleChunk() {
        let text = String(repeating: "hello world ", count: 100)  // ~1200 chars ~= 400 tokens
        let chunks = TranscriptChunker.chunk(text, maxTokens: 3000, overlap: 100)
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    @Test("long transcript is split into multiple chunks")
    func testLongTranscriptIsSplitIntoMultipleChunks() {
        // Build a transcript large enough to exceed the threshold.
        // Use "x " (with spaces) so the word-boundary chunker has something to split on.
        let text = String(repeating: "x ", count: 15_000)  // 30_000 chars ~= 10_000 tokens
        let chunks = TranscriptChunker.chunk(text, maxTokens: 3000, overlap: 100)
        #expect(chunks.count >= 3)
        // Every chunk should be <= maxTokens
        for c in chunks {
            #expect(TranscriptChunker.roughTokenCount(c) <= 3000)
        }
    }

    @Test("chunks have overlap")
    func testChunksHaveOverlap() {
        let text = (0..<1000).map { "word\($0) " }.joined()  // 1000 words
        let chunks = TranscriptChunker.chunk(text, maxTokens: 500, overlap: 30)
        #expect(chunks.count >= 2)
        // Last ~30 tokens of chunk[0] should appear near the start of chunk[1]
        let chunkOneTail = String(chunks[0].suffix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        let chunkTwoHead = String(chunks[1].prefix(200))
        #expect(chunkTwoHead.contains(String(chunkOneTail.prefix(10))))
    }
}
