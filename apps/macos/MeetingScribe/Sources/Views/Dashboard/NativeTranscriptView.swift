import SwiftUI

struct NativeTranscriptView: View {
    let rawMarkdown: String
    @State private var searchText = ""

    private var segments: [ParsedSegment] { parseTranscript(rawMarkdown) }

    private var filtered: [ParsedSegment] {
        guard !searchText.isEmpty else { return segments }
        let q = searchText.lowercased()
        return segments.filter { $0.text.lowercased().contains(q) || $0.speaker.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcript...", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No transcript" : "No matches",
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "This meeting has no transcript yet." : "No segments match your search.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { idx, seg in
                            let prev = idx > 0 ? filtered[idx - 1] : nil
                            let gap = prev.map { seg.startTime - $0.startTime } ?? 0

                            if gap > 30 {
                                HStack {
                                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                                    Text("\(Int(gap / 60))m gap")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                                }.padding(.vertical, 4)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text(formatTimestamp(seg.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    if !seg.speaker.isEmpty {
                                        Text(seg.speaker)
                                            .font(.system(.caption, weight: .semibold))
                                    }
                                    Text(seg.text)
                                        .font(.system(.body))
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    struct ParsedSegment {
        let speaker: String
        let text: String
        let startTime: TimeInterval
    }

    private func parseTranscript(_ md: String) -> [ParsedSegment] {
        var segments: [ParsedSegment] = []
        for line in md.components(separatedBy: .newlines) {
            guard line.hasPrefix("["), let bracketEnd = line.firstIndex(of: "]") else { continue }
            let tsStr = String(line[line.index(after: line.startIndex)..<bracketEnd])
            guard let time = parseTime(tsStr) else { continue }
            let rest = String(line[line.index(after: bracketEnd)...]).trimmingCharacters(in: .whitespaces)
            var speaker = ""
            var text = rest
            if rest.hasPrefix("**"),
               let endBold = rest.range(of: "**", range: rest.index(rest.startIndex, offsetBy: 2)..<rest.endIndex) {
                speaker = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<endBold.lowerBound])
                text = String(rest[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)
                if text.hasPrefix(":") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
            }
            if !text.isEmpty { segments.append(ParsedSegment(speaker: speaker, text: text, startTime: time)) }
        }
        return segments
    }

    private func parseTime(_ str: String) -> TimeInterval? {
        let parts = str.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
