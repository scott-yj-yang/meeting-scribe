import Testing
@testable import MeetingScribe

@Suite("NotionMarkdownConverter")
struct NotionMarkdownConverterTests {

    @Test("heading one")
    func testHeadingOne() {
        let blocks = NotionMarkdownConverter.convert("# Hello")
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "heading_1")
        let h1 = blocks[0]["heading_1"] as? [String: Any]
        let richText = h1?["rich_text"] as? [[String: Any]]
        let text = richText?.first?["text"] as? [String: Any]
        #expect(text?["content"] as? String == "Hello")
    }

    @Test("heading two and three")
    func testHeadingTwoAndThree() {
        let blocks = NotionMarkdownConverter.convert("## Two\n\n### Three")
        #expect(blocks.count == 2)
        #expect(blocks[0]["type"] as? String == "heading_2")
        #expect(blocks[1]["type"] as? String == "heading_3")
    }

    @Test("bulleted list")
    func testBulletedList() {
        let blocks = NotionMarkdownConverter.convert("- first\n- second\n- third")
        #expect(blocks.count == 3)
        #expect(blocks[0]["type"] as? String == "bulleted_list_item")
        #expect(blocks[2]["type"] as? String == "bulleted_list_item")
    }

    @Test("numbered list")
    func testNumberedList() {
        let blocks = NotionMarkdownConverter.convert("1. one\n2. two")
        #expect(blocks.count == 2)
        #expect(blocks[0]["type"] as? String == "numbered_list_item")
    }

    @Test("paragraph")
    func testParagraph() {
        let blocks = NotionMarkdownConverter.convert("Just a plain line of text.")
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "paragraph")
    }

    @Test("code block")
    func testCodeBlock() {
        let input = "```swift\nlet x = 1\n```"
        let blocks = NotionMarkdownConverter.convert(input)
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "code")
        let code = blocks[0]["code"] as? [String: Any]
        #expect(code?["language"] as? String == "swift")
    }

    @Test("mixed document")
    func testMixedDocument() {
        let input = """
        # Title

        A paragraph.

        - bullet one
        - bullet two

        ## Sub

        Another para.
        """
        let blocks = NotionMarkdownConverter.convert(input)
        #expect(blocks.count == 6)
        #expect(blocks[0]["type"] as? String == "heading_1")
        #expect(blocks[1]["type"] as? String == "paragraph")
        #expect(blocks[2]["type"] as? String == "bulleted_list_item")
        #expect(blocks[3]["type"] as? String == "bulleted_list_item")
        #expect(blocks[4]["type"] as? String == "heading_2")
        #expect(blocks[5]["type"] as? String == "paragraph")
    }
}
