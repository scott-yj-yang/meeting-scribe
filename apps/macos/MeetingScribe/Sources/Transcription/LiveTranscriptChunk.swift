import Foundation

/// One finalized chunk from the live `SFSpeechRecognizer` session.
/// `TranscriptionManager` produces a stream of these as recognition sessions
/// finalize (~once per minute due to SFSpeechRecognizer's native session limit).
///
/// The in-flight (not-yet-finalized) text is exposed separately by
/// `TranscriptionManager.currentSessionText`; consumers that want the full
/// running text can read `liveText` (which already concatenates chunks +
/// in-flight text and is unchanged by this work).
struct LiveTranscriptChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Seconds since recording start when this chunk's session began.
    let startTime: TimeInterval
    /// Seconds since recording start when this chunk's session finalized.
    let endTime: TimeInterval

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
