import SwiftUI

struct NativeNotesEditor: View {
    let meeting: LocalMeeting
    let meetingStore: MeetingStore
    @State private var notes = ""
    @State private var lastSavedNotes = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        MarkdownSplitEditor(text: $notes, placeholder: "Your meeting notes…")
            .onAppear {
                notes = meetingStore.loadNotes(meeting)
                lastSavedNotes = notes
            }
            .onChange(of: notes) { _, newValue in
                scheduleSave(newValue)
            }
            .onDisappear {
                saveTask?.cancel()
                if notes != lastSavedNotes {
                    meetingStore.saveNotes(meeting, notes: notes)
                }
            }
    }

    private func scheduleSave(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                meetingStore.saveNotes(meeting, notes: text)
                lastSavedNotes = text
            }
        }
    }
}
