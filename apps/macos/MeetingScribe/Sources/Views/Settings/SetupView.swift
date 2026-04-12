import SwiftUI

struct SetupView: View {
    @State private var whisperInstalled = false
    @State private var whisperModelInstalled = false
    @State private var claudeInstalled = false
    @State private var ollamaInstalled = false

    @State private var installingWhisper = false
    @State private var installingModel = false
    @State private var installingClaude = false
    @State private var installingOllama = false

    @State private var installLog = ""
    @State private var showLog = false

    var body: some View {
        Form {
            Section("Transcription") {
                dependencyRow(
                    name: "whisper-cpp",
                    description: "Speech-to-text transcription engine",
                    installed: whisperInstalled,
                    installing: installingWhisper
                ) {
                    installingWhisper = true
                    await runCommand("/opt/homebrew/bin/brew", arguments: ["install", "whisper-cpp"])
                    refreshStatus()
                    installingWhisper = false
                }

                dependencyRow(
                    name: "Whisper model",
                    description: "Large-v3-turbo model (~800 MB download)",
                    installed: whisperModelInstalled,
                    installing: installingModel
                ) {
                    installingModel = true
                    let dir = NSHomeDirectory() + "/.local/share/whisper-cpp"
                    await runCommand("/bin/mkdir", arguments: ["-p", dir])
                    let dest = dir + "/ggml-large-v3-turbo.bin"
                    await runCommand(
                        "/usr/bin/curl",
                        arguments: [
                            "-L", "-o", dest,
                            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
                        ]
                    )
                    refreshStatus()
                    installingModel = false
                }
            }

            Section("Summarization (choose one)") {
                dependencyRow(
                    name: "Claude CLI",
                    description: "Anthropic Claude for meeting summaries",
                    installed: claudeInstalled,
                    installing: installingClaude
                ) {
                    installingClaude = true
                    await runCommand("/opt/homebrew/bin/npm", arguments: ["install", "-g", "@anthropic-ai/claude-code"])
                    refreshStatus()
                    installingClaude = false
                }

                dependencyRow(
                    name: "Ollama",
                    description: "Local LLM runtime for offline summaries",
                    installed: ollamaInstalled,
                    installing: installingOllama
                ) {
                    installingOllama = true
                    await runCommand("/opt/homebrew/bin/brew", arguments: ["install", "--cask", "ollama"])
                    refreshStatus()
                    installingOllama = false
                }
            }

            if showLog {
                Section("Install log") {
                    ScrollView {
                        Text(installLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 350)
        .onAppear { refreshStatus() }
    }

    // MARK: - Dependency Row

    @ViewBuilder
    private func dependencyRow(
        name: String,
        description: String,
        installed: Bool,
        installing: Bool,
        install: @escaping () async -> Void
    ) -> some View {
        HStack {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(installed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Text("Installed")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else if installing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Install") { Task { await install() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Status Checks

    private func refreshStatus() {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        // whisper-cpp binary
        let whisperPaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cli",
            "\(home)/.local/bin/whisper-cli",
        ]
        whisperInstalled = whisperPaths.contains(where: { fm.fileExists(atPath: $0) })

        // whisper model
        let modelDirs = [
            "\(home)/.local/share/whisper-cpp",
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
        ]
        let modelNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
        ]
        whisperModelInstalled = modelDirs.contains { dir in
            modelNames.contains { name in
                fm.fileExists(atPath: "\(dir)/\(name)")
            }
        }

        // Claude CLI
        claudeInstalled = ClaudeCLIProvider.isInstalled

        // Ollama
        let ollamaPaths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
        ]
        ollamaInstalled = ollamaPaths.contains(where: { fm.fileExists(atPath: $0) })
            || fm.fileExists(atPath: "/Applications/Ollama.app")
    }

    // MARK: - Process Runner

    private func runCommand(_ executable: String, arguments: [String]) async {
        let display = ([executable] + arguments).joined(separator: " ")
        showLog = true
        installLog += "$ \(display)\n"

        let output: String = await { @Sendable () async -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let home = NSHomeDirectory()
            process.environment = ProcessInfo.processInfo.environment.merging([
                "PATH": "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": home,
            ], uniquingKeysWith: { _, new in new })

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                return "Failed to launch: \(error.localizedDescription)\n"
            }

            return await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: text)
                }
            }
        }()

        installLog += output + "\n"
    }
}
