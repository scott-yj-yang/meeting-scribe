import Testing
import Foundation
@testable import MeetingScribe

@Suite("ConferenceLinkExtractor")
struct ConferenceLinkExtractorTests {

    @Test("extracts a Zoom link from the url field")
    func zoomFromURL() {
        let link = ConferenceLinkExtractor.extract(
            url: URL(string: "https://us02web.zoom.us/j/8412345678?pwd=abc"),
            location: nil, notes: nil
        )
        #expect(link?.provider == .zoom)
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/8412345678?pwd=abc")
    }

    @Test("extracts a Google Meet link from notes")
    func meetFromNotes() {
        let link = ConferenceLinkExtractor.extract(
            url: nil, location: nil,
            notes: "Join here: https://meet.google.com/abc-defg-hij thanks"
        )
        #expect(link?.provider == .meet)
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("extracts a Teams link from location")
    func teamsFromLocation() {
        let link = ConferenceLinkExtractor.extract(
            url: nil,
            location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x",
            notes: nil
        )
        #expect(link?.provider == .teams)
    }

    @Test("a known provider anywhere beats a generic link in an earlier field")
    func knownBeatsGeneric() {
        let link = ConferenceLinkExtractor.extract(
            url: URL(string: "https://example.com/agenda"),
            location: nil,
            notes: "call: https://us02web.zoom.us/j/999"
        )
        #expect(link?.provider == .zoom)
    }

    @Test("falls back to the first generic https link")
    func genericFallback() {
        let link = ConferenceLinkExtractor.extract(
            url: nil, location: "Room 4",
            notes: "dial in at https://meet.example.org/room/42"
        )
        #expect(link?.provider == .generic)
        #expect(link?.url.absoluteString == "https://meet.example.org/room/42")
    }

    @Test("returns nil when no link is present")
    func noLink() {
        #expect(ConferenceLinkExtractor.extract(url: nil, location: "Room 4", notes: "bring laptop") == nil)
    }
}
