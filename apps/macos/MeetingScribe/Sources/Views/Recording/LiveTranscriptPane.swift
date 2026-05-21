import SwiftUI

/// Read-only pane that renders the live transcript as a scrolling list of
/// finalized whisper-transcribed chunks. Each chunk is clickable to insert
/// a timestamp into the notes editor.
struct LiveTranscriptPane: View {
    @ObservedObject var liveTranscriber: LiveTranscriber
    let liveTranscriptError: String?
    let onChunkClick: (LiveTranscriptChunk) -> Void

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
        } else if liveTranscriber.liveChunks.isEmpty {
            listeningView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(liveTranscriber.liveChunks) { chunk in
                            chunkRow(chunk: chunk).id(chunk.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: liveTranscriber.liveChunks.count) { _, _ in
                    if let last = liveTranscriber.liveChunks.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func chunkRow(chunk: LiveTranscriptChunk) -> some View {
        Button {
            onChunkClick(chunk)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TimestampFormatter.format(chunk.startTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 36, alignment: .trailing)
                if !chunk.speaker.isEmpty {
                    Text(chunk.speaker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chunk.speaker == "Me" ? .blue : .purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill((chunk.speaker == "Me" ? Color.blue : Color.purple).opacity(0.15))
                        )
                }
                Text(chunk.text)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to insert [\(TimestampFormatter.format(chunk.startTime))] into notes")
    }

    private var listeningView: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "ear")
                    .foregroundStyle(.tertiary)
                Text("Listening… whisper transcribes every 5 seconds while you record.")
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
