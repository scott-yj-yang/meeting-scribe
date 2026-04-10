import Foundation
import SwiftUI

@MainActor
final class NotionSettings: ObservableObject {
    @AppStorage("notionToken") var token: String = ""
    @AppStorage("notionDatabaseId") var databaseId: String = ""
}

enum NotionExporter {
    /// Build blocks for a meeting page and push to Notion.
    static func export(
        meeting: LocalMeeting,
        summary: String,
        notes: String,
        transcript: String,
        token: String,
        databaseId: String
    ) async throws -> String {
        let client = NotionClient(token: token)

        var blocks: [[String: Any]] = []

        // Header: title already lives in Notion's title property. Add subtitle with date + duration.
        let subtitle = "\(meeting.date.formatted(.dateTime.weekday().month().day().year().hour().minute())) · \(Int(meeting.duration / 60)) min"
        blocks.append(paragraphBlock(subtitle))
        blocks.append(dividerBlock())

        if !summary.isEmpty {
            blocks.append(heading1Block("Summary"))
            blocks.append(contentsOf: NotionMarkdownConverter.convert(summary))
        }

        if !notes.isEmpty {
            blocks.append(heading1Block("Notes"))
            blocks.append(contentsOf: NotionMarkdownConverter.convert(notes))
        }

        if !transcript.isEmpty {
            blocks.append(heading1Block("Transcript"))
            // Transcripts are long — convert but rely on append batching to handle overflow
            blocks.append(contentsOf: NotionMarkdownConverter.convert(transcript))
        }

        let pageId = try await client.createPage(
            databaseId: databaseId,
            title: meeting.title,
            children: blocks
        )
        return pageId
    }

    // MARK: - Small block helpers

    private static func paragraphBlock(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": [["type": "text", "text": ["content": text]]],
            ],
        ]
    }

    private static func heading1Block(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "heading_1",
            "heading_1": [
                "rich_text": [["type": "text", "text": ["content": text]]],
            ],
        ]
    }

    private static func dividerBlock() -> [String: Any] {
        return ["object": "block", "type": "divider", "divider": [:]]
    }
}
