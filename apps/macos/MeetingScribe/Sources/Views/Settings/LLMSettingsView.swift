import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var settings = LLMSettings()
    @State private var availableModels: [OllamaModel] = []
    @State private var statusMessage: String?
    @State private var ollamaHealthy = false
    @State private var checkingHealth = false

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
                    TextField("Endpoint", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)

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

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ollamaHealthy ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(ollamaHealthy ? "Running" : "Not running")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !ollamaHealthy {
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
                        }
                    }
                    .padding(.vertical, 4)
                    .task {
                        await refreshHealth()
                    }
                    .onChange(of: settings.ollamaEndpoint) { _, _ in
                        Task { await refreshHealth() }
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.hasPrefix("Connected") ? .green : .red)
                    }

                    Text("Install Ollama with `./scripts/install-ollama.sh` from the repo root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}
