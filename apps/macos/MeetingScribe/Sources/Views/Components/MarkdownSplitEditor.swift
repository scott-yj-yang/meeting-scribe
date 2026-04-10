import SwiftUI
import MarkdownUI

/// A three-mode markdown editor: Edit only, Split, Preview only.
/// Binds to a String. Parent observes `.onChange(of: text)` for auto-save.
struct MarkdownSplitEditor: View {
    @Binding var text: String
    let placeholder: String

    enum Mode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case split = "Split"
        case preview = "Preview"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .split

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggle
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Text("\(text.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))

            Divider()

            // Content
            switch mode {
            case .edit:
                editor
            case .preview:
                preview
            case .split:
                HSplitView {
                    editor.frame(minWidth: 200)
                    preview.frame(minWidth: 200)
                }
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var preview: some View {
        ScrollView {
            Markdown(text.isEmpty ? "_(empty)_" : text)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color.gray.opacity(0.02))
    }
}
