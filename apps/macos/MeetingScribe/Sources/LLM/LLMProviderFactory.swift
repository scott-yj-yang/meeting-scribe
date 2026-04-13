import Foundation

/// Shared factory for instantiating the active LLM provider.
/// Accepts pre-snapshotted settings values so the function can be called
/// from nonisolated contexts (callers must snapshot LLMSettings on MainActor first).
enum LLMProviderFactory {
    static func make(
        kind: LLMProviderKind,
        ollamaEndpoint: String,
        ollamaModel: String
    ) -> LLMProvider {
        switch kind {
        case .claudeCLI:
            return ClaudeCLIProvider()
        case .ollama:
            return OllamaProvider(endpoint: ollamaEndpoint, model: ollamaModel)
        }
    }
}
