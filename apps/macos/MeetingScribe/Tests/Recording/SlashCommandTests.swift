import Testing
import Foundation
@testable import MeetingScribe

@Suite("SlashCommand")
struct SlashCommandTests {

    @Test("each command has the expected callout prefix")
    func calloutPrefixes() {
        #expect(SlashCommand.action.calloutPrefix == "> [!action] ")
        #expect(SlashCommand.decision.calloutPrefix == "> [!decision] ")
        #expect(SlashCommand.question.calloutPrefix == "> [!question] ")
        #expect(SlashCommand.note.calloutPrefix == "> [!note] ")
    }

    @Test("each command has a human-readable label")
    func labels() {
        #expect(SlashCommand.action.label == "Action")
        #expect(SlashCommand.decision.label == "Decision")
        #expect(SlashCommand.question.label == "Question")
        #expect(SlashCommand.note.label == "Note")
    }

    @Test("insertion replaces the trigger '/' and inserts the prefix at line start")
    func insertReplacesSlashAtLineStart() {
        let result = SlashCommand.action.applyInsertion(into: "/", triggerSlashLocation: 0)
        #expect(result.text == "> [!action] ")
        #expect(result.caretLocation == result.text.utf16.count)
    }

    @Test("insertion in the middle of an existing document replaces the / on the current line")
    func insertOnNonEmptyLine() {
        let buffer = "earlier note\n/"
        let result = SlashCommand.decision.applyInsertion(into: buffer, triggerSlashLocation: 13)
        #expect(result.text == "earlier note\n> [!decision] ")
        #expect(result.caretLocation == result.text.utf16.count)
    }
}
