import Foundation

struct CitationToken: Hashable, Sendable {
    let minutes: Int
    let seconds: Int

    var timeInterval: TimeInterval {
        TimeInterval(minutes * 60 + seconds)
    }

    var displayString: String {
        String(format: "%02d:%02d", minutes, seconds)
    }
}

enum CitationSegment: Hashable, Sendable {
    case text(String)
    case citation(CitationToken)
}

enum CitationParser {
    // Matches [[mm:ss]] where mm is 1-3 digits and ss is exactly 2 digits.
    // Intentionally strict so malformed markers fall through to plain text.
    private static let pattern = #"\[\[(\d{1,3}):(\d{2})\]\]"#

    static func parse(_ input: String) -> [CitationSegment] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(input)]
        }
        let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, options: [], range: fullRange)
        guard !matches.isEmpty else { return [.text(input)] }

        var segments: [CitationSegment] = []
        var cursor = input.startIndex

        for match in matches {
            guard let range = Range(match.range, in: input),
                  let mRange = Range(match.range(at: 1), in: input),
                  let sRange = Range(match.range(at: 2), in: input) else { continue }

            // Text before the match
            if cursor < range.lowerBound {
                let text = String(input[cursor..<range.lowerBound])
                segments.append(.text(text))
            }

            let minutes = Int(input[mRange]) ?? 0
            let seconds = Int(input[sRange]) ?? 0
            segments.append(.citation(CitationToken(minutes: minutes, seconds: seconds)))

            cursor = range.upperBound
        }

        if cursor < input.endIndex {
            segments.append(.text(String(input[cursor..<input.endIndex])))
        }

        return segments
    }
}
