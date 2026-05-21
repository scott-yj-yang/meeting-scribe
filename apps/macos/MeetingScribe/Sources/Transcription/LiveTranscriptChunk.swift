import Foundation

/// One finalized whisper-transcribed audio segment from a live recording.
/// Produced by `LiveTranscriber` every ~5s for each captured source.
struct LiveTranscriptChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Seconds since recording start when this chunk's audio began.
    let startTime: TimeInterval
    /// Seconds since recording start when this chunk's audio ended.
    let endTime: TimeInterval
    /// "Me" for mic audio, "Others" for system audio, "" for unknown.
    let speaker: String

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speaker: String = ""
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
    }
}
