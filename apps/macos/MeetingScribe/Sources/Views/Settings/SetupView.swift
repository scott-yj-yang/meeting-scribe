import SwiftUI

struct SetupView: View {
    @State private var ollamaInstalled = false
    @State private var ollamaServerRunning = false
    @State private var ffmpegInstalled = false

    @State private var installingOllama = false
    @State private var startingOllamaServer = false
    @State private var installingFFmpeg = false

    @State private var installLog = ""
    @State private var showLog = false

    var body: some View {
        Form {
            Section("Transcription") {
                WhisperSetupView()
            }

            Section("Audio") {
                Text("ffmpeg merges your microphone with the system audio from video calls. Without it, recordings capture your voice only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                dependencyRow(
                    name: "ffmpeg",
                    description: "Merges microphone and system audio into one track",
                    installed: ffmpegInstalled,
                    installing: installingFFmpeg
                ) {
                    installingFFmpeg = true
                    await runCommand("/opt/homebrew/bin/brew", arguments: ["install", "ffmpeg"])
                    refreshStatus()
                    installingFFmpeg = false
                }
            }

            Section("Summarization") {
                Text("Open the meeting folder in Claude Code and run /summarize — the summary appears in the panel automatically. Or install Ollama below for fully-local automatic summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                    if ollamaInstalled {
                        await startOllamaServer()
                        refreshStatus()
                    }
                }

                dependencyRow(
                    name: "Ollama server",
                    description: "Start the background daemon so the app can talk to Ollama.",
                    installed: ollamaServerRunning,
                    installing: startingOllamaServer
                ) {
                    startingOllamaServer = true
                    await startOllamaServer()
                    let endpoint = UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434"
                    let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
                    ollamaServerRunning = await OllamaProvider(endpoint: endpoint, model: model).isHealthy()
                    startingOllamaServer = false
                }
            }

            if showLog {
                Section("Ollama install log") {
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
        .task { await refreshOllamaHealth() }
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
        let ollamaPaths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
        ]
        ollamaInstalled = ollamaPaths.contains(where: { fm.fileExists(atPath: $0) })
            || fm.fileExists(atPath: "/Applications/Ollama.app")
        ffmpegInstalled = FFmpegLocator.isAvailable
    }

    private func refreshOllamaHealth() async {
        let endpoint = UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434"
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
        ollamaServerRunning = await OllamaProvider(endpoint: endpoint, model: model).isHealthy()
    }

    private func startOllamaServer() async {
        let endpoint = UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434"
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2"
        showLog = true
        do {
            let running = try await OllamaServerManager.startIfNeeded(endpoint: endpoint, model: model)
            if running {
                installLog += "Ollama server is running on \(endpoint)\n"
            } else {
                installLog += "Ollama did not become healthy within timeout\n"
            }
        } catch {
            installLog += "Failed to start Ollama: \(error.localizedDescription)\n"
        }
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
