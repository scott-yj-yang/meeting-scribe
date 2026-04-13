import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var settings = LLMSettings()
    @State private var availableModels: [OllamaModel] = []
    @State private var statusMessage: String?
    @State private var ollamaHealthy = false
    @State private var checkingHealth = false
    /// Debounce token for refreshHealth. Every keystroke in the endpoint
    /// TextField schedules a new refresh; we only fire the URLSession call
    /// 400ms after the last keystroke so rapid typing doesn't spam CFNetwork
    /// with partial-URL tasks (each of which fails with -1002 and may
    /// pollute URLSession.shared's cache).
    @State private var healthRefreshTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Summarize with", selection: $settings.providerKind) {
                    ForEach(LLMProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if settings.providerKind == .claudeCLI {
                Section("Claude CLI") {
                    if ClaudeCLIProvider.isInstalled {
                        Label("Claude CLI installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Claude CLI not found", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Install with: `npm install -g @anthropic-ai/claude-code`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if settings.providerKind == .ollama {
                Section("Ollama") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Endpoint", text: $settings.ollamaEndpoint, prompt: Text("http://localhost:11434"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        HStack(spacing: 6) {
                            Image(systemName: isLocalEndpoint ? "desktopcomputer" : "network")
                                .foregroundStyle(.secondary)
                            Text(isLocalEndpoint ? "Local (this Mac)" : "Remote (\(endpointHost))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Picker("Model", selection: $settings.ollamaModel) {
                            if availableModels.isEmpty {
                                Text(settings.ollamaModel).tag(settings.ollamaModel)
                            }
                            ForEach(availableModels) { m in
                                Text(m.name).tag(m.name)
                            }
                        }
                        Button("Refresh") { Task { await refreshModels() } }
                            .buttonStyle(.bordered)
                    }

                    Picker("Chunk transcripts above", selection: $settings.ollamaMaxContextTokens) {
                        Text("3K tokens (small local models, safe default)").tag(3000)
                        Text("8K tokens (Llama 3.2 3B)").tag(8000)
                        Text("16K tokens").tag(16000)
                        Text("32K tokens (Qwen 2.5, Gemma 2)").tag(32000)
                        Text("64K tokens").tag(64000)
                        Text("128K tokens (Llama 3.1 70B)").tag(128000)
                        Text("Never chunk (any length)").tag(ollamaNeverChunkSentinel)
                    }
                    .help("The transcript is chunked only when it exceeds this. Set it to match the context window of the Ollama model you're using — larger = cleaner summaries but more memory on the server.")

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ollamaHealthy ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(ollamaHealthy ? "Reachable" : "Not reachable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // "Start server" only makes sense for a local endpoint —
                        // we can't start a daemon on a remote machine from here.
                        // For remote endpoints, surface a hint to start it there
                        // manually instead.
                        if !ollamaHealthy && isLocalEndpoint {
                            Button {
                                Task { await startServer() }
                            } label: {
                                if checkingHealth {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Start server")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(checkingHealth)
                        } else if !ollamaHealthy && !isLocalEndpoint {
                            Text("Run `OLLAMA_HOST=0.0.0.0:11434 ollama serve` on \(endpointHost)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                    .task {
                        await refreshHealth()
                    }
                    .onChange(of: settings.ollamaEndpoint) { _, _ in
                        scheduleDebouncedHealthRefresh()
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.hasPrefix("Connected") ? .green : .red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local: install with `./scripts/install-ollama.sh` from the repo root.")
                        Text("Remote: point the endpoint at another Mac on your network running `OLLAMA_HOST=0.0.0.0:11434 ollama serve`. The default Ollama install binds to localhost only, so the `OLLAMA_HOST` prefix is required to accept LAN connections.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 350)
        .task { await refreshModels() }
    }

    private func refreshModels() async {
        guard settings.providerKind == .ollama else { return }
        let provider = OllamaProvider(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        do {
            let models = try await provider.listModels()
            await MainActor.run {
                self.availableModels = models
                self.statusMessage = "Connected — \(models.count) models available"
            }
        } catch {
            await MainActor.run {
                self.availableModels = []
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func refreshHealth() async {
        let provider = OllamaProvider(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        ollamaHealthy = await provider.isHealthy()
    }

    /// Debounced wrapper for refreshHealth: cancels any pending refresh and
    /// schedules a new one 400ms out, so rapid typing in the endpoint field
    /// only fires one URLSession call (the final one) instead of one per
    /// keystroke. Also refreshes the model picker on success so the UI
    /// statusMessage clears when the endpoint finally resolves.
    private func scheduleDebouncedHealthRefresh() {
        healthRefreshTask?.cancel()
        healthRefreshTask = Task { [settings] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await refreshHealth()
            // If the debounced endpoint is healthy, also refresh the model
            // list so statusMessage transitions from a stale error to
            // "Connected — N models available" without requiring a manual
            // click on the Refresh button.
            if ollamaHealthy && settings.providerKind == .ollama {
                await refreshModels()
            }
        }
    }

    private func startServer() async {
        checkingHealth = true
        defer { checkingHealth = false }
        do {
            ollamaHealthy = try await OllamaServerManager.startIfNeeded(
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel
            )
            if ollamaHealthy {
                await refreshModels()
            }
        } catch {
            ollamaHealthy = false
        }
    }

    /// True when the configured Ollama endpoint points at this Mac.
    /// Used to decide whether the "Start server" button is offered — we
    /// can't start a daemon on a remote machine from here.
    private var isLocalEndpoint: Bool {
        let host = URL(string: settings.ollamaEndpoint)?.host?.lowercased() ?? ""
        return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host.isEmpty
    }

    private var endpointHost: String {
        URL(string: settings.ollamaEndpoint)?.host ?? "remote host"
    }
}
