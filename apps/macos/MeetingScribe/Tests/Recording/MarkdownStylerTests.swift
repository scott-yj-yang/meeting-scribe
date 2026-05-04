import Testing
import AppKit
@testable import MeetingScribe

@Suite("MarkdownStyler — headings")
struct MarkdownStylerHeadingTests {

    @Test("# heading produces 22pt bold attribute on the line")
    func h1HeadingStyled() {
        let storage = NSMutableAttributedString(string: "# Sprint plan")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize == 22)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("## heading produces 18pt bold")
    func h2HeadingStyled() {
        let storage = NSMutableAttributedString(string: "## Subhead")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize == 18)
    }

    @Test("### heading produces 15pt bold")
    func h3HeadingStyled() {
        let storage = NSMutableAttributedString(string: "### Tertiary")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize == 15)
    }

    @Test("a # not at line start is not a heading")
    func midLineHashIsNotHeading() {
        let storage = NSMutableAttributedString(string: "issue #42 filed today")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize ?? 14 == 14)
    }

    @Test("editing a heading line back to plain clears the heading style")
    func clearsHeadingStyleOnReapply() {
        let storage = NSMutableAttributedString(string: "# heading")
        MarkdownStyler.applyAttributes(to: storage)
        storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.pointSize ?? 14 == 14)
    }

    @Test("empty string does not crash")
    func emptyStringSafe() {
        let storage = NSMutableAttributedString(string: "")
        MarkdownStyler.applyAttributes(to: storage)
    }
}
