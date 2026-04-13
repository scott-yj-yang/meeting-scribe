import Testing
import Foundation
@testable import MeetingScribe

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test("round-trips through JSON")
    func testChatMessageRoundTripsThroughJSON() throws {
        let msg = ChatMessage(
            role: .user,
            text: "What was decided about the budget?",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.role == .user)
        #expect(decoded.text == "What was decided about the budget?")
        #expect(decoded.id == msg.id)
        #expect(abs(decoded.createdAt.timeIntervalSince1970 - 1_700_000_000) < 0.001)
    }
}
