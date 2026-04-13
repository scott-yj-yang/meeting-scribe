import Foundation
import SwiftUI

/// Global LLM config. Backed by @AppStorage so it persists across launches.
@MainActor
final class LLMSettings: ObservableObject {
    @AppStorage("llmProviderKind") private var providerKindRaw: String = LLMProviderKind.claudeCLI.rawValue
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3.2"

    /// Approximate token budget per Ollama summarization call. If the transcript
    /// exceeds this, it's chunked and each chunk is summarized separately (then
    /// the chunk summaries are synthesized). Set this to match your remote or
    /// local model's effective context window. Set to Int.max to disable
    /// chunking entirely for models with very large contexts (128K+).
    /// Default 3000 is conservative for small local models like Llama 3.2 3B.
    /// Claude CLI ignores this setting — it always runs single-pass.
    @AppStorage("ollamaMaxContextTokens") var ollamaMaxContextTokens: Int = 3000

    var providerKind: LLMProviderKind {
        get { LLMProviderKind(rawValue: providerKindRaw) ?? .claudeCLI }
        set { providerKindRaw = newValue.rawValue; objectWillChange.send() }
    }
}

/// Sentinel for "disable chunking" on the Ollama context size picker.
/// Exposed as a top-level constant so both LLMSettings/UI and the summary
/// view can reference the same value.
let ollamaNeverChunkSentinel: Int = Int.max
