import Foundation

/// File-based local database for meetings.
/// Each meeting is a folder with metadata.json, transcript.md, audio.wav, and notes.md.
/// Survives app restarts, works offline.
@MainActor
class MeetingStore: ObservableObject {
    @Published var meetings: [LocalMeeting] = []

    private let baseDirectory: String

    init(baseDirectory: String = "~/MeetingScribe") {
        self.baseDirectory = baseDirectory
        loadAll()
    }

    // MARK: - CRUD

    func loadAll() {
        let basePath = NSString(string: baseDirectory).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: basePath)
        var found: [LocalMeeting] = []

        let fm = FileManager.default
        guard let yearDirs = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            meetings = []
            return
        }

        for yearDir in yearDirs where yearDir.hasDirectoryPath {
            guard let monthDirs = try? fm.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: nil) else { continue }
            for monthDir in monthDirs where monthDir.hasDirectoryPath {
                guard let meetingDirs = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil) else { continue }
                for meetingDir in meetingDirs where meetingDir.hasDirectoryPath {
                    let metaURL = meetingDir.appendingPathComponent("metadata.json")
                    if let data = try? Data(contentsOf: metaURL),
                       var meeting = try? JSONDecoder().decode(LocalMeeting.self, from: data) {
                        meeting.directoryURL = meetingDir
                        found.append(meeting)
                    }
                }
            }
        }

        meetings = found.sorted { $0.date > $1.date }
    }

    func save(_ meeting: LocalMeeting) {
        guard let dir = meeting.directoryURL else { return }
        let metaURL = dir.appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(meeting) {
            try? data.write(to: metaURL)
        }
        // Update in-memory list
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = meeting
        } else {
            meetings.insert(meeting, at: 0)
            meetings.sort { $0.date > $1.date }
        }
    }

    func delete(_ meeting: LocalMeeting) {
        guard let dir = meeting.directoryURL else { return }
        try? FileManager.default.removeItem(at: dir)

        // Clean up empty parent directories
        let monthDir = dir.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil))?.isEmpty == true {
            try? FileManager.default.removeItem(at: monthDir)
            let yearDir = monthDir.deletingLastPathComponent()
            if (try? FileManager.default.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: nil))?.isEmpty == true {
                try? FileManager.default.removeItem(at: yearDir)
            }
        }

        meetings.removeAll { $0.id == meeting.id }
    }

    func saveNotes(_ meeting: LocalMeeting, notes: String) {
        guard let dir = meeting.directoryURL else { return }
        let notesURL = dir.appendingPathComponent("notes.md")
        try? notes.write(to: notesURL, atomically: true, encoding: .utf8)

        var updated = meeting
        updated.notes = notes
        save(updated)
    }

    func loadNotes(_ meeting: LocalMeeting) -> String {
        guard let dir = meeting.directoryURL else { return "" }
        let notesURL = dir.appendingPathComponent("notes.md")
        return (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
    }

    func loadTranscript(_ meeting: LocalMeeting) -> String {
        guard let dir = meeting.directoryURL else { return "" }
        let mdURL = dir.appendingPathComponent("transcript.md")
        return (try? String(contentsOf: mdURL, encoding: .utf8)) ?? ""
    }

    /// Create a new meeting entry from a recording
    func createMeeting(
        title: String,
        date: Date,
        duration: TimeInterval,
        meetingType: String?,
        transcriptSnippet: String?,
        directoryURL: URL,
        calendarEventTitle: String? = nil,
        notes: String? = nil
    ) -> LocalMeeting {
        var meeting = LocalMeeting(
            id: UUID().uuidString,
            title: title,
            date: date,
            duration: duration,
            meetingType: meetingType,
            transcriptSnippet: transcriptSnippet,
            calendarEventTitle: calendarEventTitle,
            notes: notes
        )
        meeting.directoryURL = directoryURL
        save(meeting)
        return meeting
    }
}

struct LocalMeeting: Identifiable, Codable {
    var id: String
    var title: String
    var date: Date
    var duration: TimeInterval
    var meetingType: String?
    var transcriptSnippet: String?
    var calendarEventTitle: String?
    var notes: String?

    // Not persisted in JSON — set after loading
    var directoryURL: URL?

    var hasTranscript: Bool {
        guard let dir = directoryURL else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("transcript.md").path)
    }

    var hasAudio: Bool {
        guard let dir = directoryURL else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.wav").path)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, duration, meetingType, transcriptSnippet
        case calendarEventTitle, notes
    }
}
