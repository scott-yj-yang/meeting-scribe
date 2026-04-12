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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .textSelection(.enabled)

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
                        Button {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        } label: {
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
        .toolbar {
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
    }

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
