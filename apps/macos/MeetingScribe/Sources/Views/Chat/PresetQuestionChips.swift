import SwiftUI

struct PresetQuestionChips: View {
    enum Mode {
        case live
        case postMeeting
    }

    let mode: Mode
    let onSelect: (String) -> Void

    private var presets: [String] {
        switch mode {
        case .live:
            return [
                "Catch me up",
                "What was just decided?",
                "Open questions so far?",
                "Action items?"
            ]
        case .postMeeting:
            return [
                "Summarize decisions",
                "List action items with owners",
                "Draft follow-up email",
                "What were the open questions?"
            ]
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { text in
                    Button {
                        onSelect(text)
                    } label: {
                        Text(text)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                    .background(Capsule().fill(Color.primary.opacity(0.04)))
                            )
                    }
                    .buttonStyle(.plain)
                    .clickableHover(cornerRadius: 20)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
