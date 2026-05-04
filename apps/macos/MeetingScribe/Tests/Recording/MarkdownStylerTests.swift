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

@Suite("MarkdownStyler — inline")
struct MarkdownStylerInlineTests {

    @Test("**bold** applies bold to the inner text")
    func boldApplied() {
        let storage = NSMutableAttributedString(string: "this is **bold** text")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 11, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("*italic* applies italic to the inner text")
    func italicApplied() {
        let storage = NSMutableAttributedString(string: "an *italic* word")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("_italic_ also applies italic")
    func underscoreItalicApplied() {
        let storage = NSMutableAttributedString(string: "an _italic_ word")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("**bold** is not matched as italic")
    func boldNotItalic() {
        let storage = NSMutableAttributedString(string: "**bold**")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }

    @Test("`code` applies monospaced font")
    func codeApplied() {
        let storage = NSMutableAttributedString(string: "use `swift build` here")
        MarkdownStyler.applyAttributes(to: storage)
        let attrs = storage.attributes(at: 8, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font?.isFixedPitch == true)
    }
}
