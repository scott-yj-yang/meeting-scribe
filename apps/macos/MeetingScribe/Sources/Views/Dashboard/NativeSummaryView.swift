import SwiftUI
import MarkdownUI

struct NativeSummaryView: View {
    let meeting: LocalMeeting
    @State private var summaryText = ""
    @State private var isLoading = false
    @State private var selectedTemplate = "default"
    @State private var error: String?

    private let templates = [
        ("default", "General Meeting"), ("standup", "Daily Standup"),
        ("planning", "Sprint Planning"), ("retro", "Retrospective"),
        ("one-on-one", "1:1 Meeting"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Summarizing with Claude...").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
        isLoading = true; error = nil

        Task.detached {
            let result = await Self.runClaude(transcriptPath: transcriptPath, template: selectedTemplate)
            await MainActor.run {
                isLoading = false
                switch result {
                case .success(let text):
                    summaryText = text
                    try? text.write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
        }
    }

    private static func runClaude(transcriptPath: String, template: String) async -> Result<String, Error> {
        let homeDir = NSHomeDirectory()
        let templateDirs = ["\(homeDir)/Developer/meeting-scribe/prompts/templates", "\(homeDir)/Developer/meeting-scribe/prompts"]
        var promptContent = ""
        for dir in templateDirs {
            for name in [template, "summarize"] {
                let path = "\(dir)/\(name).md"
                if let c = try? String(contentsOfFile: path, encoding: .utf8) { promptContent = c; break }
            }
            if !promptContent.isEmpty { break }
        }
        guard !promptContent.isEmpty else {
            return .failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No prompt template found"]))
        }

        let fullPrompt = "\(promptContent)\n\nThe meeting transcript file is located at: \(transcriptPath)\nPlease read that file and produce the summary."
        let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(homeDir)/.local/bin/claude"]
        guard let claudePath = claudePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return .failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude CLI not installed"]))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--allowedTools", "Read", "-p", fullPrompt]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
                return .failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude returned empty output"]))
            }
            return .success(output)
        } catch { return .failure(error) }
    }
}
