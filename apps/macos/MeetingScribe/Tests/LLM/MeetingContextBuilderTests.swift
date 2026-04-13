import Testing
import Foundation
@testable import MeetingScribe

@Suite("MeetingContextBuilder")
struct MeetingContextBuilderTests {

    @Test("builds system message with title and transcript")
    func buildsSystemMessageWithTitleAndTranscript() {
        let context = MeetingContext(
            title: "Weekly 1:1",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1800,
            calendarEventTitle: "Weekly 1:1 with Alex",
            notes: "Discussion of Q2 roadmap",
            transcript: "00:00 Hello.\n00:05 Let's start.",
            summary: nil,
            mode: .postMeeting
        )
        let message = MeetingContextBuilder.buildSystemMessage(context: context)

        #expect(message.role == .system)
        #expect(message.text.contains("Weekly 1:1"))
        #expect(message.text.contains("Weekly 1:1 with Alex"))
        #expect(message.text.contains("00:00 Hello."))
        #expect(message.text.contains("[[mm:ss]]"))
        #expect(message.text.contains("Discussion of Q2 roadmap"))
    }

    @Test("omits missing sections")
    func omitsMissingSections() {
        let context = MeetingContext(
            title: "Quick sync",
            date: Date(),
            durationSeconds: 0,
            calendarEventTitle: nil,
            notes: nil,
            transcript: "Just a test.",
            summary: nil,
            mode: .postMeeting
        )
        let message = MeetingContextBuilder.buildSystemMessage(context: context)

        #expect(!message.text.contains("# User notes"))
        #expect(!message.text.contains("# Summary"))
        #expect(!message.text.contains("Calendar event"))
        #expect(message.text.contains("Just a test."))
    }

    @Test("live mode labels transcript as in progress")
    func liveModeLabelsTranscriptAsInProgress() {
        let context = MeetingContext(
            title: "Live",
            date: Date(),
            durationSeconds: 120,
            calendarEventTitle: nil,
            notes: nil,
            transcript: "Hello world.",
            summary: nil,
            mode: .live
        )
        let message = MeetingContextBuilder.buildSystemMessage(context: context)
        #expect(message.text.contains("Live transcript (in progress)"))
        #expect(message.text.contains("meeting is currently happening"))
    }
}
