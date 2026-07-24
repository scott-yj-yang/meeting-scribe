import Foundation

enum ConferenceProvider: String, Equatable {
    case zoom, meet, teams, webex, generic
}

struct ConferenceLink: Equatable {
    let url: URL
    let provider: ConferenceProvider
}

/// Pulls a video-call join link out of an event's url / location / notes.
enum ConferenceLinkExtractor {

    private static let known: [(ConferenceProvider, String)] = [
        (.zoom,  #"https?://[A-Za-z0-9.-]*zoom\.us/[^\s<>"']+"#),
        (.meet,  #"https?://meet\.google\.com/[^\s<>"']+"#),
        (.teams, #"https?://teams\.(?:microsoft|live)\.com/[^\s<>"']+"#),
        (.webex, #"https?://[A-Za-z0-9.-]*webex\.com/[^\s<>"']+"#),
    ]
    private static let generic = #"https?://[^\s<>"']+"#

    static func extract(url: URL?, location: String?, notes: String?) -> ConferenceLink? {
        let fields = [url?.absoluteString, location, notes].compactMap { $0 }

        // Known providers win over a bare link, regardless of which field holds them.
        for field in fields {
            for (provider, pattern) in known {
                if let u = firstURL(pattern, in: field) {
                    return ConferenceLink(url: u, provider: provider)
                }
            }
        }
        for field in fields {
            if let u = firstURL(generic, in: field) {
                return ConferenceLink(url: u, provider: .generic)
            }
        }
        return nil
    }

    private static func firstURL(_ pattern: String, in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        // Trailing punctuation often clings to a URL pasted mid-sentence.
        let raw = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
        return URL(string: raw)
    }
}
