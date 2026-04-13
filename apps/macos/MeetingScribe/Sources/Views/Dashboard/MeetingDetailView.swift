import SwiftUI

struct MeetingDetailView: View {
    let meeting: LocalMeeting
    let meetingStore: MeetingStore
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @StateObject private var notionSettings = NotionSettings()
    @State private var exporting = false
    @State private var exportStatus: String?
    @State private var showDeleteConfirm = false
    @State private var editableTitle: String = ""

    // MARK: - Chat state
    @State private var showChatPanel: Bool = false
    @StateObject private var chatViewModel = MeetingChatViewModel()
    @State private var transcriptScrollTarget: TimeInterval? = nil
    @StateObject private var llmSettings = LLMSettings()

    var body: some View {
        HStack(spacing: 0) {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showChatPanel {
                Divider()
                MeetingChatPanel(
                    viewModel: chatViewModel,
                    presetMode: .postMeeting,
                    onCitationTap: { token in
                        transcriptScrollTarget = token.timeInterval
                    }
                )
                .frame(width: 380)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    let wasOpen = showChatPanel
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showChatPanel.toggle()
                    }
                    if !wasOpen {
                        loadChatSession()
                    }
                } label: {
                    Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        .font(.system(size: 16, weight: .medium))
                        .iconHitTarget(.compact)
                }
                .buttonStyle(.plain)
                .clickableHover()
                .help(showChatPanel ? "Hide chat" : "Ask about this meeting")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await exportToNotion() }
                } label: {
                    if exporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Export to Notion", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(exporting || notionSettings.token.isEmpty || notionSettings.databaseId.isEmpty)
                .help(notionSettings.token.isEmpty ? "Configure Notion in Settings (Cmd-,)" : "Export this meeting to Notion")
            }
            ToolbarItem(placement: .destructiveAction) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this meeting")
            }
        }
        .alert("Delete this meeting?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                appState.meetingStore.delete(meeting)
            }
        } message: {
            Text("This will permanently remove \"\(meeting.title)\" and all its files (audio, transcript, summary, notes).")
        }
        .overlay(alignment: .bottom) {
            if let status = exportStatus {
                Text(status)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding()
            }
        }
        .onAppear {
            editableTitle = meeting.title
        }
        .onChange(of: meeting.id) { _, _ in
            editableTitle = meeting.title
            // Reset chat when switching meetings
            showChatPanel = false
        }
    }

    // MARK: - Main content (extracted so it can be wrapped in the HStack)

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                TextField("Untitled meeting", text: $editableTitle, onCommit: {
                    if editableTitle != meeting.title {
                        meetingStore.rename(meeting, to: editableTitle)
                    }
                })
                .font(.system(.title, design: .rounded, weight: .bold))
                .textFieldStyle(.plain)

                HStack(spacing: 12) {
                    Label(meeting.date.formatted(.dateTime.weekday(.wide).month().day().year()),
                          systemImage: "calendar")
                    Label(formatDuration(meeting.duration), systemImage: "clock")
                    if let type = meeting.meetingType {
                        Text(type)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let calTitle = meeting.calendarEventTitle {
                    Label(calTitle, systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                HStack(spacing: 8) {
                    if notionSettings.token.isEmpty || notionSettings.databaseId.isEmpty {
                        SettingsLink {
                            Label("Set up Notion export", systemImage: "square.and.arrow.up")
                                .font(.caption)
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    } else {
                        Button {
                            Task { await exportToNotion() }
                        } label: {
                            if exporting {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Exporting...")
                                        .font(.caption)
                                }
                            } else {
                                Label("Export to Notion", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                                    .imageScale(.small)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(6)
                        .disabled(exporting)
                    }

                    Button {
                        if let url = meeting.directoryURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open folder", systemImage: "folder")
                            .font(.caption)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Picker("", selection: $selectedTab) {
                Text("Transcript").tag(0)
                Text("Summary").tag(1)
                Text("Notes").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0:
                    let transcript = meetingStore.loadTranscript(meeting)
                    if transcript.isEmpty {
                        ContentUnavailableView("No transcript", systemImage: "doc.text",
                            description: Text("This meeting hasn't been transcribed yet."))
                    } else {
                        NativeTranscriptView(rawMarkdown: transcript)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                case 1:
                    NativeSummaryView(meeting: meeting)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                case 2:
                    NativeNotesEditor(meeting: meeting, meetingStore: meetingStore)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Chat session loading

    private func loadChatSession() {
        guard let dir = meeting.directoryURL else { return }

        // Load persisted history
        let store = ChatSessionStore()
        do {
            let session = try store.load(from: dir)
            chatViewModel.loadExisting(session.messages)
        } catch {
            chatViewModel.loadExisting([])
        }

        // Capture meeting and dir by value so closures don't hold self
        let capturedMeeting = meeting
        let capturedDir = dir

        chatViewModel.systemMessageProvider = {
            let transcriptURL = capturedDir.appendingPathComponent("transcript.md")
            let summaryURL = capturedDir.appendingPathComponent("summary.md")
            let notesURL = capturedDir.appendingPathComponent("notes.md")

            let transcript = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
            let summary = try? String(contentsOf: summaryURL, encoding: .utf8)
            let notes = try? String(contentsOf: notesURL, encoding: .utf8)

            let context = MeetingContext(
                title: capturedMeeting.title,
                date: capturedMeeting.date,
                durationSeconds: capturedMeeting.duration,
                calendarEventTitle: capturedMeeting.calendarEventTitle,
                notes: notes,
                transcript: transcript,
                summary: summary,
                mode: .postMeeting
            )
            return MeetingContextBuilder.buildSystemMessage(context: context)
        }

        // Snapshot LLM settings on MainActor before entering the nonisolated closure
        let kind = llmSettings.providerKind
        let endpoint = llmSettings.ollamaEndpoint
        let model = llmSettings.ollamaModel

        chatViewModel.runChat = { messages, onToken in
            let provider = LLMProviderFactory.make(
                kind: kind,
                ollamaEndpoint: endpoint,
                ollamaModel: model
            )
            return try await provider.chat(messages: messages, onToken: onToken)
        }

        chatViewModel.onTurnComplete = { messages in
            let session = ChatSession(messages: messages)
            try? store.save(session, to: capturedDir)
        }
    }

    // MARK: - Helpers

    private func exportToNotion() async {
        exporting = true
        defer { exporting = false }
        exportStatus = "Exporting…"

        let summary: String = {
            guard let dir = meeting.directoryURL else { return "" }
            return (try? String(contentsOf: dir.appendingPathComponent("summary.md"), encoding: .utf8)) ?? ""
        }()
        let notes = meetingStore.loadNotes(meeting)
        let transcript = meetingStore.loadTranscript(meeting)

        do {
            let pageId = try await NotionExporter.export(
                meeting: meeting,
                summary: summary,
                notes: notes,
                transcript: transcript,
                token: notionSettings.token,
                databaseId: notionSettings.databaseId
            )
            exportStatus = "Exported to Notion ✓"
            print("[Notion] Exported page id: \(pageId)")
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }

        // Hide status after 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        exportStatus = nil
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m == 0 { return "\(Int(seconds))s" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }
}
