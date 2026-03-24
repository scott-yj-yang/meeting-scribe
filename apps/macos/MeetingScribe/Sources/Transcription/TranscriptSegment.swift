import Foundation

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let speaker: String
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(speaker: String, text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = UUID()
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}
