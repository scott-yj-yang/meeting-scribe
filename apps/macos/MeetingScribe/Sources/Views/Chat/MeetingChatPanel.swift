import SwiftUI

@MainActor
final class MeetingChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?

    /// Closure invoked when the user submits a question. Receives the full message list
    /// (including system + prior turns + the new user turn) and a streaming callback.
    /// Must return the assistant's full response.
    var runChat: (([ChatMessage], @escaping @Sendable (String) -> Void) async throws -> String)?

    /// Called after a successful turn. Used by the caller to persist chat.json.
    var onTurnComplete: (([ChatMessage]) -> Void)?

    /// System message; regenerated each turn by the caller and passed in.
    var systemMessageProvider: (() -> ChatMessage)?

    func loadExisting(_ existing: [ChatMessage]) {
        messages = existing
    }

    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        guard let runChat = runChat, let systemProvider = systemMessageProvider else {
            errorMessage = "Chat not configured."
            return
        }

        errorMessage = nil
        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""

        // Placeholder assistant bubble to stream tokens into
        let assistantId = UUID()
        let assistantPlaceholder = ChatMessage(id: assistantId, role: .assistant, text: "")
        messages.append(assistantPlaceholder)
        isStreaming = true

        let outbound: [ChatMessage] = [systemProvider()] + messages.dropLast() + [userMessage]

        do {
            _ = try await runChat(outbound) { [weak self] token in
                guard let self = self else { return }
                Task { @MainActor in
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                        self.messages[idx].text += token
                    }
                }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages.remove(at: idx)
            }
            errorMessage = error.localizedDescription
        }

        isStreaming = false
        onTurnComplete?(messages)
    }
}

struct MeetingChatPanel: View {
    @ObservedObject var viewModel: MeetingChatViewModel
    let presetMode: PresetQuestionChips.Mode
    var onCitationTap: ((CitationToken) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        } else {
                            ForEach(viewModel.messages) { msg in
                                ChatMessageBubble(message: msg, onCitationTap: onCitationTap)
                                    .id(msg.id)
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: viewModel.messages.last?.id) { _, newID in
                    guard let id = newID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    guard let id = viewModel.messages.last?.id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()

            PresetQuestionChips(mode: presetMode) { text in
                viewModel.inputText = text
                Task { await viewModel.send() }
            }

            // Input
            HStack(spacing: 8) {
                TextField("Ask about this meeting...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .onSubmit {
                        Task { await viewModel.send() }
                    }
                    .disabled(viewModel.isStreaming)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: viewModel.isStreaming ? "circle.dotted" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(viewModel.isStreaming ? Color.secondary : Color.blue)
                        .iconHitTarget(.large)
                }
                .buttonStyle(.plain)
                .clickableHover(cornerRadius: 22)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isStreaming)
                .help("Send message")
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Ask about this meeting")
                .font(.system(.headline, design: .rounded))
            Text("Pick a preset question below or type your own. Answers stream live and cite the transcript where relevant.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
    }
}
