import Foundation

final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {
    var displayName: String { "Claude CLI" }

    private let processLock = NSLock()
    private var _process: Process?

    private func setProcess(_ p: Process?) {
        processLock.lock()
        defer { processLock.unlock() }
        _process = p
    }

    private func getProcess() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return _process
    }

    static var isInstalled: Bool {
        let paths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(NSHomeDirectory())/.local/bin/claude"]
        return paths.contains(where: { FileManager.default.fileExists(atPath: $0) })
    }

    /// Stable working directory for every claude invocation. Pinning to a
    /// single folder means Claude CLI sees a consistent workspace across
    /// calls, so workspace-trust and any per-folder auth state persist.
    private var workingDirectory: URL {
        let outputDir = UserDefaults.standard.string(forKey: "outputDirectory") ?? "~/MeetingScribe"
        let path = NSString(string: outputDir).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func summarize(
        transcript: String,
        template: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Materialize transcript to a temp file so claude can Read it
        let tmpDir = FileManager.default.temporaryDirectory
        let transcriptURL = tmpDir.appendingPathComponent("meetingscribe-\(UUID().uuidString).md")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: transcriptURL) }

        let promptContent = try loadTemplate(template)
        let fullPrompt = "\(promptContent)\n\nThe meeting transcript file is located at: \(transcriptURL.path)\nPlease read that file and produce the summary."

        let homeDir = NSHomeDirectory()
        let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(homeDir)/.local/bin/claude"]
        guard let claudePath = claudePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude CLI not installed"])
        }

        let p = Process()
        setProcess(p)
        p.executableURL = URL(fileURLWithPath: claudePath)
        p.currentDirectoryURL = workingDirectory
        p.arguments = ["--allowedTools", "Read", "-p", fullPrompt]
        let stdout = Pipe()
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice

        try p.run()

        var fullText = ""
        for try await line in stdout.fileHandleForReading.bytes.lines {
            let chunk = line + "\n"
            fullText += chunk
            onToken(chunk)
        }
        await Task.detached { p.waitUntilExit() }.value
        setProcess(nil)

        if p.terminationStatus != 0 && fullText.isEmpty {
            throw NSError(domain: "Claude", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Claude exited with status \(p.terminationStatus)"])
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serializeMessagesToPrompt(_ messages: [ChatMessage]) -> String {
        // Claude CLI expects plain-text prompt. Serialize role-labeled blocks so the model
        // can distinguish system context, prior user turns, and its own prior responses.
        var out = ""
        for msg in messages {
            switch msg.role {
            case .system:
                out += "[Context — do not repeat]\n\(msg.text)\n\n"
            case .user:
                out += "Human: \(msg.text)\n\n"
            case .assistant:
                out += "Assistant: \(msg.text)\n\n"
            }
        }
        // Leave the final turn open so Claude continues as the assistant
        out += "Assistant:"
        return out
    }

    func chat(
        messages: [ChatMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let prompt = serializeMessagesToPrompt(messages)

        let homeDir = NSHomeDirectory()
        let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(homeDir)/.local/bin/claude"]
        guard let claudePath = claudePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude CLI not installed"])
        }

        let p = Process()
        setProcess(p)
        p.executableURL = URL(fileURLWithPath: claudePath)
        p.currentDirectoryURL = workingDirectory
        p.arguments = ["-p", prompt]
        let stdout = Pipe()
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice

        try p.run()

        var fullText = ""
        for try await line in stdout.fileHandleForReading.bytes.lines {
            let chunk = line + "\n"
            fullText += chunk
            onToken(chunk)
        }
        await Task.detached { p.waitUntilExit() }.value
        setProcess(nil)

        if p.terminationStatus != 0 && fullText.isEmpty {
            throw NSError(domain: "Claude", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Claude exited with status \(p.terminationStatus)"])
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        getProcess()?.terminate()
        setProcess(nil)
    }

    private func loadTemplate(_ name: String) throws -> String {
        let homeDir = NSHomeDirectory()
        let templateDirs = [
            "\(homeDir)/Developer/meeting-scribe/prompts/templates",
            "\(homeDir)/Developer/meeting-scribe/prompts",
        ]
        for dir in templateDirs {
            for candidate in [name, "summarize"] {
                let path = "\(dir)/\(candidate).md"
                if let c = try? String(contentsOfFile: path, encoding: .utf8), !c.isEmpty {
                    return c
                }
            }
        }
        throw NSError(domain: "Claude", code: 1, userInfo: [NSLocalizedDescriptionKey: "No prompt template found"])
    }
}
