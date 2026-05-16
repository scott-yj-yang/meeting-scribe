import SwiftUI
import MarkdownUI

/// MainActor-isolated streaming buffer for summary generation. Lives outside
/// the View struct so `@Sendable` token callbacks can capture it without
/// pulling in View state (which would force them to be main-actor-isolated
/// and prevent passing to nonisolated `LLMProvider.summarize`).
@MainActor
final class SummaryStreamStore: ObservableObject {
    @Published var text: String = ""
    func append(_ delta: String) { text += delta }
    func reset() { text = "" }
    func set(_ value: String) { text = value }
}

struct NativeSummaryView: View {
    let meeting: LocalMeeting
    @State private var summaryText = ""
    @State private var isLoading = false
    @State private var selectedTemplate = "default"
    @State private var error: String?
    @StateObject private var streamStore = SummaryStreamStore()
    @State private var cancelRequested = false
    @State private var lastSavedText = ""
    @State private var saveTask: Task<Void, Never>?
    @StateObject private var llmSettings = LLMSettings()
    @State private var watcher: SummaryFileWatcher?

    private let templates = [
        ("default", "General Meeting"),
        ("one-on-one", "1:1 Meeting"),
        ("subgroup", "Subgroup Meeting"),
        ("standup", "Daily Standup"),
        ("planning", "Sprint Planning"),
        ("retro", "Retrospective"),
        ("lab-meeting", "Lab Meeting"),
        ("seminar", "Seminar / Talk"),
        ("interview", "Interview Debrief"),
        ("brainstorm", "Brainstorm"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Summarizing with \(llmSettings.providerKind.displayName)...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { cancelSummarization() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal)
                    ScrollView {
                        Markdown(streamStore.text.isEmpty ? "_Waiting for first tokens…_" : streamStore.text)
                            .markdownTheme(.dashboard)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            } else if !summaryText.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Picker("Template", selection: $selectedTemplate) {
                            ForEach(templates, id: \.0) { id, label in Text(label).tag(id) }
                        }.pickerStyle(.menu).frame(width: 200)
                        Button("Open in Claude Code") { revealInFinder() }
                            .buttonStyle(.bordered)
                        if providerAvailable {
                            Button("Resummarize with Ollama") { runSummarization() }.buttonStyle(.bordered)
                        }
                        Spacer()
                        if summaryText != lastSavedText {
                            Text("Unsaved")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    MarkdownSplitEditor(text: $summaryText, placeholder: "Start writing the summary…")
                        .onChange(of: summaryText) { _, newValue in
                            scheduleSave(newValue)
                        }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No summary yet").font(.headline).foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Button("Open in Claude Code") { revealInFinder() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Text("Reveals the meeting folder. Open it in Claude Code and run `/summarize` — the summary will load here automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }

                    if providerAvailable {
                        Divider().frame(maxWidth: 280)
                        VStack(spacing: 8) {
                            Picker("Template", selection: $selectedTemplate) {
                                ForEach(templates, id: \.0) { id, label in Text(label).tag(id) }
                            }.pickerStyle(.menu).frame(width: 200)
                            Button("Summarize with Ollama (local)") { runSummarization() }
                                .buttonStyle(.bordered)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
        }
        .onAppear {
            loadSummary()
            startWatching()
        }
        .onDisappear { watcher = nil }
    }

    private var providerAvailable: Bool {
        switch llmSettings.providerKind {
        case .ollama: return true  // best-effort; errors surface when invoked
        }
    }

    private func loadSummary() {
        guard let dir = meeting.directoryURL else { return }
        summaryText = (try? String(contentsOf: dir.appendingPathComponent("summary.md"), encoding: .utf8)) ?? ""
        lastSavedText = summaryText
    }

    /// Watch the meeting folder for changes to summary.md so an external editor
    /// (Claude Code, VS Code, plain `vim`) can write the file and the UI picks
    /// it up live. We watch the directory rather than the file because the file
    /// may not exist yet, and atomic-write tools (which most editors use) rename
    /// a temp file over the target — that fires a directory event but not a
    /// stable per-file event.
    private func startWatching() {
        guard let dir = meeting.directoryURL else { return }
        watcher = SummaryFileWatcher(directory: dir) { [self] in
            // Skip reload if user is mid-edit and has unsaved changes — don't
            // clobber their typing with a stale on-disk version.
            if summaryText != lastSavedText { return }
            loadSummary()
        }
    }

    private func revealInFinder() {
        guard let dir = meeting.directoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func scheduleSave(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second debounce
            if Task.isCancelled { return }
            guard let dir = meeting.directoryURL else { return }
            try? text.write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
            await MainActor.run { lastSavedText = text }
        }
    }

    private func runSummarization() {
        guard let dir = meeting.directoryURL else { return }
        let transcriptPath = dir.appendingPathComponent("transcript.md").path
        guard let transcript = try? String(contentsOfFile: transcriptPath, encoding: .utf8), !transcript.isEmpty else {
            error = "No transcript"; return
        }

        isLoading = true
        streamStore.reset()
        error = nil
        cancelRequested = false

        // Snapshot settings so the nonisolated worker doesn't have to touch MainActor state
        let kind = llmSettings.providerKind
        let endpoint = llmSettings.ollamaEndpoint
        let model = llmSettings.ollamaModel
        let template = selectedTemplate
        let store = streamStore

        Task {
            do {
                let result = try await summarizeWithProvider(
                    transcript: transcript,
                    store: store,
                    kind: kind,
                    endpoint: endpoint,
                    model: model,
                    template: template
                )
                await MainActor.run {
                    if cancelRequested {
                        cancelRequested = false
                        streamStore.reset()
                        isLoading = false
                        return
                    }
                    summaryText = result
                    lastSavedText = result
                    isLoading = false
                    try? result.write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    nonisolated private func summarizeWithProvider(
        transcript: String,
        store: SummaryStreamStore,
        kind: LLMProviderKind,
        endpoint: String,
        model: String,
        template: String
    ) async throws -> String {
        // Route streaming deltas through a @Sendable callback that hops to MainActor.
        // DispatchQueue.main.async guarantees FIFO ordering (unlike unstructured MainActor
        // Tasks, which have no FIFO guarantee and can reorder rapid tokens). Using
        // MainActor.assumeIsolated is safe because the main DispatchQueue IS the
        // MainActor executor.
        let onToken: @Sendable (String) -> Void = { [store] delta in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    store.append(delta)
                }
            }
        }

        let provider: LLMProvider
        switch kind {
        case .ollama:
            provider = OllamaProvider(endpoint: endpoint, model: model)
        }

        // Ollama: chunk long transcripts to fit local models' smaller contexts.
        // The threshold is user-configurable via LLMSettings.ollamaMaxContextTokens,
        // read directly from UserDefaults here because this method is nonisolated
        // and can't touch @StateObject. Int.max = "never chunk" (large-context
        // models like Llama 3.1 70B 128K).
        let storedMaxTokens = UserDefaults.standard.integer(forKey: "ollamaMaxContextTokens")
        let maxTokens = storedMaxTokens > 0 ? storedMaxTokens : 3000
        let chunks = TranscriptChunker.chunk(transcript, maxTokens: maxTokens, overlap: 100)
        if chunks.count == 1 {
            return try await provider.summarize(transcript: transcript, template: template, onToken: onToken)
        }

        // Multi-chunk: summarize each, then synthesize
        await store.set("_Processing \(chunks.count) chunks…_\n\n")
        var chunkSummaries: [String] = []
        for (i, chunk) in chunks.enumerated() {
            await store.append("\n### Chunk \(i + 1)/\(chunks.count)\n")
            let summary = try await provider.summarize(transcript: chunk, template: template, onToken: onToken)
            chunkSummaries.append(summary)
        }
        let combined = chunkSummaries.enumerated()
            .map { "## Part \($0.offset + 1)\n\n\($0.element)" }
            .joined(separator: "\n\n")
        await store.set("_Synthesizing final summary…_\n\n")
        return try await provider.summarize(transcript: combined, template: template, onToken: onToken)
    }

    private func cancelSummarization() {
        cancelRequested = true
        isLoading = false
    }

}
