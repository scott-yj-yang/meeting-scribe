import Testing
import Foundation
@testable import MeetingScribe

@Suite("CitationParser")
struct CitationParserTests {

    @Test("parses plain text with no citations")
    func parsesPlainText() {
        let segments = CitationParser.parse("Hello world.")
        #expect(segments.count == 1)
        guard case .text(let s) = segments[0] else {
            Issue.record("Expected .text segment")
            return
        }
        #expect(s == "Hello world.")
    }

    @Test("parses a single citation with surrounding text")
    func parsesSingleCitation() {
        let segments = CitationParser.parse("We shipped Thursday [[02:15]].")
        #expect(segments.count == 3)

        guard case .text(let a) = segments[0] else {
            Issue.record("Expected .text at index 0")
            return
        }
        #expect(a == "We shipped Thursday ")

        guard case .citation(let token) = segments[1] else {
            Issue.record("Expected .citation at index 1")
            return
        }
        #expect(token.minutes == 2)
        #expect(token.seconds == 15)
        #expect(token.timeInterval == 135.0)
        #expect(token.displayString == "02:15")

        guard case .text(let b) = segments[2] else {
            Issue.record("Expected .text at index 2")
            return
        }
        #expect(b == ".")
    }

    @Test("parses multiple citations")
    func parsesMultipleCitations() {
        let segments = CitationParser.parse("A [[00:10]] then B [[15:42]].")
        #expect(segments.count == 5)
        var citationCount = 0
        for seg in segments {
            if case .citation = seg { citationCount += 1 }
        }
        #expect(citationCount == 2)
    }

    @Test("ignores malformed markers")
    func ignoresMalformedMarkers() {
        let segments = CitationParser.parse("Not a cite [[foo]] nor [[1:2:3]].")
        #expect(segments.count == 1)
        guard case .text(let s) = segments[0] else {
            Issue.record("Expected single text segment")
            return
        }
        #expect(s == "Not a cite [[foo]] nor [[1:2:3]].")
    }

    @Test("handles minutes up to 3 digits")
    func handlesLargeMinutes() {
        let segments = CitationParser.parse("Later [[125:30]] happened.")
        var found: CitationToken?
        for seg in segments {
            if case .citation(let t) = seg { found = t }
        }
        #expect(found?.minutes == 125)
        #expect(found?.timeInterval == TimeInterval(125 * 60 + 30))
    }
}
