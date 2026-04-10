import SwiftUI
import MarkdownUI

struct NativeSummaryView: View {
    let meeting: LocalMeeting
    @State private var summaryText = ""
    @State private var isLoading = false
    @State private var selectedTemplate = "default"
    @State private var error: String?
    @State private var currentProcess: Process?
    @State private var streamingText = ""
    @State private var cancelRequested = false

    private let templates = [
        ("default", "General Meeting"), ("standup", "Daily Standup"),
        ("planning", "Sprint Planning"), ("retro", "Retrospective"),
        ("one-on-one", "1:1 Meeting"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Summarizing with Claude...").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { cancelSummarization() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal)
                    ScrollView {
                        Markdown(streamingText.isEmpty ? "_Waiting for first tokens…_" : streamingText)
                            .markdownTheme(.gitHub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            } else if !summaryText.isEmpty {
                HStack {
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates, id: \.0) { id, label in Text(label).tag(id) }
                    }.pickerStyle(.menu).frame(width: 200)
                    Button("Resummarize") { runSummarization() }.buttonStyle(.bordered)
                }
                ScrollView {
                    Markdown(summaryText)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No summary yet").font(.headline).foregroundStyle(.secondary)
                    Picker("Template", selection: $selectedTemplate) {
                        ForEach(templates, id: \.0) { id, label in Text(label).tag(id) }
                    }.pickerStyle(.menu).frame(width: 200)
                    Button("Summarize with Claude") { runSummarization() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!isClaudeInstalled)
                    if !isClaudeInstalled {
                        Text("Claude CLI not found").font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
        }
        .onAppear { loadSummary() }
    }

    private var isClaudeInstalled: Bool {
        ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(NSHomeDirectory())/.local/bin/claude"]
            .contains(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func loadSummary() {
        guard let dir = meeting.directoryURL else { return }
        summaryText = (try? String(contentsOf: dir.appendingPathComponent("summary.md"), encoding: .utf8)) ?? ""
    }

    private func runSummarization() {
        guard let dir = meeting.directoryURL else { return }
        let transcriptPath = dir.appendingPathComponent("transcript.md").path
        guard FileManager.default.fileExists(atPath: transcriptPath) else { error = "No transcript"; return }

        isLoading = true
        streamingText = ""
        error = nil
        cancelRequested = false

        Task {
            do {
                let result = try await runClaudeStreaming(
                    transcriptPath: transcriptPath,
                    template: selectedTemplate
                ) { delta in
                    streamingText += delta
                }
                await MainActor.run {
                    if cancelRequested {
                        cancelRequested = false
                        streamingText = ""
                        isLoading = false
                        currentProcess = nil
                        return
                    }
                    summaryText = result
                    isLoading = false
                    currentProcess = nil
                    try? result.write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
                }
            } catch is CancellationError {
                await MainActor.run {
                    isLoading = false
                    currentProcess = nil
                    streamingText = ""
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                    currentProcess = nil
                }
            }
        }
    }

    private func cancelSummarization() {
        cancelRequested = true
        currentProcess?.terminate()
        currentProcess = nil
        isLoading = false
    }

    @MainActor
    private func runClaudeStreaming(
        transcriptPath: String,
        template: String,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let homeDir = NSHomeDirectory()
        let templateDirs = [
            "\(homeDir)/Developer/meeting-scribe/prompts/templates",
            "\(homeDir)/Developer/meeting-scribe/prompts",
        ]
        var promptContent = ""
        for dir in templateDirs {
            for name in [template, "summarize"] {
                let path = "\(dir)/\(name).md"
                if let c = try? String(contentsOfFile: path, encoding: .utf8) { promptContent = c; break }
            }
            if !promptContent.isEmpty { break }
        }
        guard !promptContent.isEmpty else {
            throw NSError(domain: "LLM", code: 0, userInfo: [NSLocalizedDescriptionKey: "No prompt template found"])
        }

        let fullPrompt = "\(promptContent)\n\nThe meeting transcript file is located at: \(transcriptPath)\nPlease read that file and produce the summary."
        let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(homeDir)/.local/bin/claude"]
        guard let claudePath = claudePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(domain: "LLM", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude CLI not installed"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--allowedTools", "Read", "-p", fullPrompt]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        // Store process so Cancel can terminate it
        await MainActor.run { self.currentProcess = process }

        var fullText = ""
        let handle = stdout.fileHandleForReading

        try process.run()

        // Read asynchronously — handle.bytes gives an AsyncSequence<UInt8>
        for try await line in handle.bytes.lines {
            let chunk = line + "\n"
            fullText += chunk
            onDelta(chunk)
        }

        await Task.detached { process.waitUntilExit() }.value

        if process.terminationStatus != 0 && fullText.isEmpty {
            throw NSError(domain: "LLM", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Claude exited with status \(process.terminationStatus)"])
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
