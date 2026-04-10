import Foundation

/// Converts a markdown document to an array of Notion block dicts.
/// Minimal implementation: headings, lists, paragraphs, code fences.
/// Inline formatting (bold/italic) is emitted as plain text — no rich_text annotations.
enum NotionMarkdownConverter {

    static func convert(_ markdown: String) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code fence
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1  // skip closing fence
                blocks.append(codeBlock(codeLines.joined(separator: "\n"), language: language.isEmpty ? "plain text" : language))
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(headingBlock(level: 3, text: String(trimmed.dropFirst(4))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(headingBlock(level: 2, text: String(trimmed.dropFirst(3))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(headingBlock(level: 1, text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Bulleted list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(listItemBlock(type: "bulleted_list_item", text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Numbered list: "1. something"
            if let dotIdx = trimmed.firstIndex(of: "."), Int(trimmed[..<dotIdx]) != nil {
                let after = trimmed.index(after: dotIdx)
                if after < trimmed.endIndex && trimmed[after] == " " {
                    let text = String(trimmed[trimmed.index(after: after)...])
                    blocks.append(listItemBlock(type: "numbered_list_item", text: text))
                    i += 1
                    continue
                }
            }

            // Default: paragraph. Collect consecutive non-special lines into one paragraph
            var paraLines: [String] = [line]
            var j = i + 1
            while j < lines.count {
                let next = lines[j].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("```") { break }
                paraLines.append(lines[j])
                j += 1
            }
            blocks.append(paragraphBlock(text: paraLines.joined(separator: " ")))
            i = j
        }
        return blocks
    }

    // MARK: - Builders

    private static func richText(_ text: String) -> [[String: Any]] {
        // Notion caps rich_text content at 2000 chars per item; split if needed
        var result: [[String: Any]] = []
        var remaining = text
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(2000))
            remaining = String(remaining.dropFirst(chunk.count))
            result.append([
                "type": "text",
                "text": ["content": chunk],
            ])
        }
        return result
    }

    private static func headingBlock(level: Int, text: String) -> [String: Any] {
        let typeKey = "heading_\(level)"
        return [
            "object": "block",
            "type": typeKey,
            typeKey: ["rich_text": richText(text)],
        ]
    }

    private static func listItemBlock(type: String, text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": type,
            type: ["rich_text": richText(text)],
        ]
    }

    private static func paragraphBlock(text: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "paragraph",
            "paragraph": ["rich_text": richText(text)],
        ]
    }

    private static func codeBlock(_ code: String, language: String) -> [String: Any] {
        return [
            "object": "block",
            "type": "code",
            "code": [
                "rich_text": richText(code),
                "language": language,
            ],
        ]
    }
}
