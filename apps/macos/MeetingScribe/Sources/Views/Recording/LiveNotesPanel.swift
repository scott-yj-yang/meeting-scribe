import SwiftUI

/// Collapsible notes editor shown during recording.
/// Notes are bound to AppState.meetingNotes and auto-saved with the meeting.
struct LiveNotesPanel: View {
    @Binding var notes: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                    Text("Meeting Notes")
                        .font(.system(size: 10, weight: .semibold))
                    if !notes.isEmpty {
                        Circle()
                            .fill(.blue)
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                    if !isExpanded && !notes.isEmpty {
                        Text("\(notes.split(separator: "\n").count) lines")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                TextEditor(text: $notes)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 60, maxHeight: 120)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Questions, observations, action items...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}
