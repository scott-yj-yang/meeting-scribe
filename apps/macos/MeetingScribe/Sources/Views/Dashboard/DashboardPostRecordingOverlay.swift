import SwiftUI

struct DashboardPostRecordingOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            if appState.isTranscribing {
                transcribingView
            } else {
                completedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transcribing

    private var transcribingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text("Transcribing...")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ProgressView(value: appState.transcriptionProgress, total: 1.0)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(appState.transcriptionProgress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let eta = appState.transcriptionETA {
                        Text("ETA: \(eta)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 350)

            if let snippet = appState.lastTranscriptSnippet {
                snippetPreview(snippet)
            }
        }
    }

    // MARK: - Completed

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            if let message = appState.statusMessage {
                Text(message)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            if let snippet = appState.lastTranscriptSnippet {
                snippetPreview(snippet)
            }

            Text("Select from sidebar to view details")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Snippet

    private func snippetPreview(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: 400, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
