import XCTest
@testable import MeetingScribe

final class TranscriptChunkerTests: XCTestCase {

    func testRoughTokenCountApproximatesCharDivide3() {
        XCTAssertEqual(TranscriptChunker.roughTokenCount("abc"), 1)       // 3 chars → 1
        XCTAssertEqual(TranscriptChunker.roughTokenCount("abcdefghi"), 3) // 9 chars → 3
        XCTAssertEqual(TranscriptChunker.roughTokenCount(""), 0)
    }

    func testShortTranscriptReturnsSingleChunk() {
        let text = String(repeating: "hello world ", count: 100)  // ~1200 chars ~= 400 tokens
        let chunks = TranscriptChunker.chunk(text, maxTokens: 3000, overlap: 100)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], text)
    }

    func testLongTranscriptIsSplitIntoMultipleChunks() {
        // Build a transcript large enough to exceed the threshold.
        // Use "x " (with spaces) so the word-boundary chunker has something to split on.
        let text = String(repeating: "x ", count: 15_000)  // 30_000 chars ~= 10_000 tokens
        let chunks = TranscriptChunker.chunk(text, maxTokens: 3000, overlap: 100)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        // Every chunk should be ≤ maxTokens
        for c in chunks {
            XCTAssertLessThanOrEqual(TranscriptChunker.roughTokenCount(c), 3000)
        }
    }

    func testChunksHaveOverlap() {
        let text = (0..<1000).map { "word\($0) " }.joined()  // 1000 words
        let chunks = TranscriptChunker.chunk(text, maxTokens: 500, overlap: 30)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        // Last ~30 tokens of chunk[0] should appear near the start of chunk[1]
        let chunkOneTail = String(chunks[0].suffix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        let chunkTwoHead = String(chunks[1].prefix(200))
        XCTAssertTrue(chunkTwoHead.contains(String(chunkOneTail.prefix(10))),
                      "Expected chunk[1] to start with tokens overlapping chunk[0]")
    }
}
