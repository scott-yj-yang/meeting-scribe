import Foundation

/// Abstraction over local/cloud LLM providers for summarization.
protocol LLMProvider {
    /// Streaming summarize. `onToken` is called on background thread for each delta.
    /// Returns the full concatenated result.
    func summarize(
        transcript: String,
        template: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String

    /// Async-cancellable by caller via Task.cancel().
    var displayName: String { get }
}

enum LLMProviderKind: String, CaseIterable, Identifiable, Codable {
    case claudeCLI = "claude_cli"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI: return "Claude CLI"
        case .ollama: return "Ollama (local)"
        }
    }
}
