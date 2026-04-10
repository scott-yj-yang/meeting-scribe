import XCTest
@testable import MeetingScribe

final class NotionMarkdownConverterTests: XCTestCase {

    func testHeadingOne() {
        let blocks = NotionMarkdownConverter.convert("# Hello")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "heading_1")
        let h1 = blocks[0]["heading_1"] as? [String: Any]
        let richText = h1?["rich_text"] as? [[String: Any]]
        let text = richText?.first?["text"] as? [String: Any]
        XCTAssertEqual(text?["content"] as? String, "Hello")
    }

    func testHeadingTwoAndThree() {
        let blocks = NotionMarkdownConverter.convert("## Two\n\n### Three")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "heading_2")
        XCTAssertEqual(blocks[1]["type"] as? String, "heading_3")
    }

    func testBulletedList() {
        let blocks = NotionMarkdownConverter.convert("- first\n- second\n- third")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["type"] as? String, "bulleted_list_item")
        XCTAssertEqual(blocks[2]["type"] as? String, "bulleted_list_item")
    }

    func testNumberedList() {
        let blocks = NotionMarkdownConverter.convert("1. one\n2. two")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "numbered_list_item")
    }

    func testParagraph() {
        let blocks = NotionMarkdownConverter.convert("Just a plain line of text.")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "paragraph")
    }

    func testCodeBlock() {
        let input = "```swift\nlet x = 1\n```"
        let blocks = NotionMarkdownConverter.convert(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "code")
        let code = blocks[0]["code"] as? [String: Any]
        XCTAssertEqual(code?["language"] as? String, "swift")
    }

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
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0]["type"] as? String, "heading_1")
        XCTAssertEqual(blocks[1]["type"] as? String, "paragraph")
        XCTAssertEqual(blocks[2]["type"] as? String, "bulleted_list_item")
        XCTAssertEqual(blocks[3]["type"] as? String, "bulleted_list_item")
        XCTAssertEqual(blocks[4]["type"] as? String, "heading_2")
        XCTAssertEqual(blocks[5]["type"] as? String, "paragraph")
    }
}
