import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var onCitationTap: ((CitationToken) -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(background)
                    )
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)

                if message.role == .assistant {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let segments = CitationParser.parse(message.text)
        if segments.count == 1, case .text(let plain) = segments[0] {
            Text(plain)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CitationFlowText(segments: segments, onCitationTap: onCitationTap)
                .font(.body)
        }
    }

    private var background: Color {
        switch message.role {
        case .user: return Color.blue
        case .assistant: return Color.primary.opacity(0.06)
        case .system: return Color.clear
        }
    }

    private var foreground: Color {
        message.role == .user ? .white : .primary
    }
}

/// A wrapping text layout that interleaves plain text runs with citation chip buttons.
private struct CitationFlowText: View {
    let segments: [CitationSegment]
    var onCitationTap: ((CitationToken) -> Void)?

    var body: some View {
        ChatFlowLayout(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let s):
                    // Split on whitespace so the layout wraps word-by-word
                    ForEach(Array(s.split(separator: " ", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, word in
                        Text(String(word) + " ")
                            .fixedSize()
                    }
                case .citation(let token):
                    CitationChip(token: token) {
                        onCitationTap?(token)
                    }
                }
            }
        }
    }
}

/// Minimal flow layout using SwiftUI's Layout protocol (macOS 13+).
private struct ChatFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = size.width + spacing
                rowHeight = size.height
            } else {
                rowWidth += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A tappable timestamp chip with a hover preview.
struct CitationChip: View {
    let token: CitationToken
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "quote.bubble")
                    .font(.caption2)
                Text(token.displayString)
                    .font(.caption.weight(.medium).monospacedDigit())
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.blue.opacity(0.15))
            )
            .foregroundStyle(Color.blue)
        }
        .buttonStyle(.plain)
        .clickableHover(cornerRadius: 20)
        .help("Jump to transcript \(token.displayString)")
    }
}
