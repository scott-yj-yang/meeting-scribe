import Foundation

/// Organizes meeting files into a date-based hierarchy:
///   ~/MeetingScribe/
///     2026/
///       03-March/
///         25-sprint-planning/
///           transcript.md
///           audio.wav
struct LocalStorage {

    /// Save transcript markdown and return the file URL
    static func save(markdown: String, title: String, date: Date, directory: String) throws -> URL {
        let meetingDir = meetingDirectory(title: title, date: date, baseDirectory: directory)
        try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let fileURL = meetingDir.appendingPathComponent("transcript.md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Get the organized directory for a meeting's files
    static func meetingDirectory(title: String, date: Date, baseDirectory: String) -> URL {
        let expandedDir = NSString(string: baseDirectory).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expandedDir)

        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let day = calendar.component(.day, from: date)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MM-MMMM"
        let monthStr = monthFormatter.string(from: date)

        let safeTitle = title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()

        let dayStr = String(format: "%02d", day)

        // ~/MeetingScribe/2026/03-March/25-sprint-planning/
        return baseURL
            .appendingPathComponent("\(year)")
            .appendingPathComponent(monthStr)
            .appendingPathComponent("\(dayStr)-\(safeTitle)")
    }
}
