import SwiftUI

/// Read-only pane that renders the live transcript as a scrolling list of
/// chunks plus the in-flight (not-yet-finalized) text as a tentative
/// trailing chunk. Each chunk is **clickable** in Task 13 — for now this
/// renders the streaming view with empty/error states.
struct LiveTranscriptPane: View {
    @ObservedObject var transcriptionManager: TranscriptionManager
    let liveTranscriptError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 320)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = liveTranscriptError {
            errorView(error)
        } else if transcriptionManager.liveChunks.isEmpty && transcriptionManager.currentSessionText.isEmpty {
            listeningView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcriptionManager.liveChunks) { chunk in
                            chunkRow(chunk: chunk, isInFlight: false)
                                .id(chunk.id)
                        }
                        if !transcriptionManager.currentSessionText.isEmpty {
                            chunkRow(
                                text: transcriptionManager.currentSessionText,
                                timestampLabel: "now",
                                isInFlight: true
                            )
                            .id("in-flight")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: transcriptionManager.liveChunks.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("in-flight", anchor: .bottom)
                    }
                }
                .onChange(of: transcriptionManager.currentSessionText) { _, _ in
                    proxy.scrollTo("in-flight", anchor: .bottom)
                }
            }
        }
    }

    private func chunkRow(chunk: LiveTranscriptChunk, isInFlight: Bool) -> some View {
        chunkRow(text: chunk.text, timestampLabel: TimestampFormatter.format(chunk.startTime), isInFlight: isInFlight)
    }

    private func chunkRow(text: String, timestampLabel: String, isInFlight: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timestampLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 36, alignment: .trailing)
            Text(text)
                .font(.system(.body))
                .foregroundStyle(isInFlight ? .primary : .secondary)
                .opacity(isInFlight ? 1.0 : 0.85)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var listeningView: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "ear")
                    .foregroundStyle(.tertiary)
                Text("Listening… speak to see the live transcript here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Live transcript unavailable", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Recording continues; full transcript will appear after stop.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
