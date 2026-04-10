import Foundation
import SwiftUI

/// Global LLM config. Backed by @AppStorage so it persists across launches.
@MainActor
final class LLMSettings: ObservableObject {
    @AppStorage("llmProviderKind") private var providerKindRaw: String = LLMProviderKind.claudeCLI.rawValue
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3.2"

    var providerKind: LLMProviderKind {
        get { LLMProviderKind(rawValue: providerKindRaw) ?? .claudeCLI }
        set { providerKindRaw = newValue.rawValue; objectWillChange.send() }
    }
}
