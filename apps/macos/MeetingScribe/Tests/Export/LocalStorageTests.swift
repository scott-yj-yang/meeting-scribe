import Testing
import Foundation
@testable import MeetingScribe

@Suite("LocalStorage meeting folders")
struct LocalStorageTests {

    /// 2026-03-25, built with an explicit Gregorian calendar so the fixture
    /// itself never depends on the machine's region settings.
    private static var referenceDate: Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone.current
        return gregorian.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 14, minute: 15))!
    }

    private func makeTempBase(_ label: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStorageTests-\(label)-\(UUID().uuidString)")
            .path
    }

    // MARK: - Naming

    @Test("date components use Gregorian/English regardless of system locale")
    func dateComponentsAreStable() {
        let dir = LocalStorage.meetingDirectory(
            title: "Standup", date: Self.referenceDate, baseDirectory: "/tmp/base"
        )
        #expect(dir.path == "/tmp/base/2026/03-March/25-standup")
    }

    @Test("slug collapses separators, punctuation, and whitespace", arguments: [
        ("Sprint Planning",    "sprint-planning"),
        ("Q3: Review / Retro", "q3-review-retro"),
        (".hidden",            "hidden"),
        ("back\\slash",        "back-slash"),
        ("with\nnewline",      "with-newline"),
        ("  padded  ",         "padded"),
        ("multi   space",      "multi-space"),
        ("...",                "untitled"),
        ("",                   "untitled"),
    ])
    func slugSanitizes(input: String, expected: String) {
        #expect(LocalStorage.slug(input) == expected)
    }

    @Test("slug keeps non-Latin titles readable instead of discarding them")
    func slugPreservesUnicodeLetters() {
        #expect(LocalStorage.slug("会議メモ") == "会議メモ")
    }

    @Test("path components stay within the 255-byte filesystem limit")
    func longTitlesAreCapped() {
        let dir = LocalStorage.meetingDirectory(
            title: String(repeating: "a", count: 400),
            date: Self.referenceDate,
            baseDirectory: "/tmp/base"
        )
        #expect(dir.lastPathComponent.utf8.count <= 255)
    }

    // MARK: - Uniqueness

    @Test("same title on the same day never reuses a folder")
    func sameDaySameTitleGetsSuffix() throws {
        let base = makeTempBase("unique")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: base) }

        let first = LocalStorage.uniqueMeetingDirectory(
            title: "Standup", date: Self.referenceDate, baseDirectory: base
        )
        #expect(first.lastPathComponent == "25-standup")

        try fm.createDirectory(at: first, withIntermediateDirectories: true)
        let second = LocalStorage.uniqueMeetingDirectory(
            title: "Standup", date: Self.referenceDate, baseDirectory: base
        )
        #expect(second.lastPathComponent == "25-standup-2")

        try fm.createDirectory(at: second, withIntermediateDirectories: true)
        let third = LocalStorage.uniqueMeetingDirectory(
            title: "Standup", date: Self.referenceDate, baseDirectory: base
        )
        #expect(third.lastPathComponent == "25-standup-3")
    }

    // MARK: - Reconciliation (title edited mid-recording)

    /// Create a folder as a started recording would, with audio already in it.
    private func startRecording(_ title: String, base: String) throws -> URL {
        let dir = LocalStorage.uniqueMeetingDirectory(
            title: title, date: Self.referenceDate, baseDirectory: base
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "audio".write(to: dir.appendingPathComponent("audio.wav"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test("folder follows a title typed while the recording was running")
    func folderFollowsEditedTitle() throws {
        let base = makeTempBase("reconcile")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: base) }

        let started = try startRecording("Meeting Mar 25, 2:15 PM", base: base)
        let settled = LocalStorage.reconcileMeetingDirectory(
            started, toTitle: "Sprint Planning", date: Self.referenceDate, baseDirectory: base
        )

        #expect(settled.lastPathComponent == "25-sprint-planning")
        #expect(fm.fileExists(atPath: settled.appendingPathComponent("audio.wav").path))
        #expect(!fm.fileExists(atPath: started.path))
    }

    @Test("an unchanged title leaves the folder alone")
    func unchangedTitleIsNoOp() throws {
        let base = makeTempBase("stable")
        defer { try? FileManager.default.removeItem(atPath: base) }

        let dir = try startRecording("Retro", base: base)
        let after = LocalStorage.reconcileMeetingDirectory(
            dir, toTitle: "Retro", date: Self.referenceDate, baseDirectory: base
        )
        #expect(after.path == dir.path)
    }

    @Test("a title that slugs identically is treated as unchanged")
    func equivalentTitleIsNoOp() throws {
        let base = makeTempBase("equivalent")
        defer { try? FileManager.default.removeItem(atPath: base) }

        let dir = try startRecording("Design Review", base: base)
        let after = LocalStorage.reconcileMeetingDirectory(
            dir, toTitle: "Design  Review!", date: Self.referenceDate, baseDirectory: base
        )
        #expect(after.path == dir.path)
    }

    @Test("an already-suffixed folder keeps its suffix")
    func suffixedFolderIsNoOp() throws {
        let base = makeTempBase("suffixed")
        defer { try? FileManager.default.removeItem(atPath: base) }

        _ = try startRecording("Retro", base: base)
        let second = try startRecording("Retro", base: base)
        #expect(second.lastPathComponent == "25-retro-2")

        let after = LocalStorage.reconcileMeetingDirectory(
            second, toTitle: "Retro", date: Self.referenceDate, baseDirectory: base
        )
        #expect(after.path == second.path)
    }

    @Test("renaming onto a taken name does not clobber the existing meeting")
    func renameOntoTakenNameGetsSuffix() throws {
        let base = makeTempBase("collide")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: base) }

        let existing = try startRecording("Sprint Planning", base: base)
        let other = try startRecording("Standup", base: base)

        let moved = LocalStorage.reconcileMeetingDirectory(
            other, toTitle: "Sprint Planning", date: Self.referenceDate, baseDirectory: base
        )

        #expect(moved.lastPathComponent == "25-sprint-planning-2")
        #expect(fm.fileExists(atPath: existing.appendingPathComponent("audio.wav").path))
        #expect(fm.fileExists(atPath: moved.appendingPathComponent("audio.wav").path))
    }

    // MARK: - Saving

    @Test("save writes the transcript into the folder it is handed")
    func saveWritesIntoGivenFolder() throws {
        let base = makeTempBase("save")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: base) }

        let dir = URL(fileURLWithPath: base).appendingPathComponent("2026/03-March/25-demo")
        let url = try LocalStorage.save(markdown: "# Transcript", to: dir)

        #expect(url == dir.appendingPathComponent("transcript.md"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Transcript")
        // The Claude workspace ships alongside so `/summarize` works in-folder.
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("CLAUDE.md").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent(".claude/commands/summarize.md").path))
    }
}
