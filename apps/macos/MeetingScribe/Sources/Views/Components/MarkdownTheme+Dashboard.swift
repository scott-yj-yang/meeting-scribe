import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    @MainActor static let dashboard = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 24, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(22)
                    FontFamily(.system(.rounded))
                    ForegroundColor(.primary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(18)
                    FontFamily(.system(.rounded))
                    ForegroundColor(.primary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    FontFamily(.system(.rounded))
                    ForegroundColor(.primary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 8)
                .markdownTextStyle {
                    FontSize(14)
                    ForegroundColor(.primary)
                }
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(.blue)
            BackgroundColor(Color.blue.opacity(0.06))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(13)
                    ForegroundColor(.primary)
                }
                .padding(12)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 8, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                        FontStyle(.italic)
                    }
                    .padding(.leading, 12)
            }
            .markdownMargin(top: 8, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .thematicBreak {
            Divider()
                .markdownMargin(top: 12, bottom: 12)
        }
        .link {
            ForegroundColor(.blue)
        }
}
