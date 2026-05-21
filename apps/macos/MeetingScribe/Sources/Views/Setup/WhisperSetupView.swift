import SwiftUI
import AppKit

/// Two-row UI for installing whisper-cli + its model. Shared between
/// the Settings → Setup tab and the first-launch Welcome flow.
///
/// Render this directly inside any container — no outer Form/Section
/// wrapper is provided so callers can match their surrounding styling.
struct WhisperSetupView: View {
    /// Reported up to the caller whenever install status changes.
    var onStatusChange: ((Bool) -> Void)? = nil

    @State private var brewInstalled = false
    @State private var whisperInstalled = false
    @State private var modelInstalled = false
    @State private var installingWhisper = false
    @State private var installingModel = false
    @State private var installLog = ""
    @State private var showLog = false

    var isInstalled: Bool { whisperInstalled && modelInstalled }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !brewInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Homebrew required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout.weight(.semibold))
                    Text("MeetingScribe uses Homebrew to install the speech-recognition tool. It's free and only needs to be set up once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Install Homebrew (opens browser)", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            if brewInstalled {
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
                    installed: modelInstalled,
                    installing: installingModel
                ) {
                    installingModel = true
                    let dir = NSHomeDirectory() + "/.local/share/whisper-cpp"
                    await runCommand("/bin/mkdir", arguments: ["-p", dir])
                    let dest = dir + "/ggml-large-v3-turbo.bin"
                    await runCommand(
                        "/usr/bin/curl",
                        arguments: [
                            "-L", "--progress-bar", "-o", dest,
                            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
                        ]
                    )
                    refreshStatus()
                    installingModel = false
                }
            }

            if showLog {
                DisclosureGroup("Install log", isExpanded: $showLog) {
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
        .onAppear { refreshStatus() }
        .onChange(of: isInstalled) { _, newValue in
            onStatusChange?(newValue)
        }
    }

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
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(name == "Whisper model" ? "Downloading… (~5-15 min)" : "Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Install") { Task { await install() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func refreshStatus() {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        brewInstalled = fm.fileExists(atPath: "/opt/homebrew/bin/brew") || fm.fileExists(atPath: "/usr/local/bin/brew")

        let whisperPaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cli",
            "\(home)/.local/bin/whisper-cli",
        ]
        whisperInstalled = whisperPaths.contains(where: { fm.fileExists(atPath: $0) })

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
        modelInstalled = modelDirs.contains { dir in
            modelNames.contains { name in
                fm.fileExists(atPath: "\(dir)/\(name)")
            }
        }
    }

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
