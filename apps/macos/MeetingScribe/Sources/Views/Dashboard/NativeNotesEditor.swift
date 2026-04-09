import SwiftUI

struct NativeNotesEditor: View {
    let meeting: LocalMeeting
    let meetingStore: MeetingStore
    @State private var notes = ""
    @State private var saveTimer: Timer?

    var body: some View {
        TextEditor(text: $notes)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .overlay(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Meeting notes...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: notes) {
                saveTimer?.invalidate()
                saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                    Task { @MainActor in meetingStore.saveNotes(meeting, notes: notes) }
                }
            }
            .onAppear { notes = meetingStore.loadNotes(meeting) }
            .onDisappear { meetingStore.saveNotes(meeting, notes: notes) }
    }
}
