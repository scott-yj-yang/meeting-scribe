import Foundation

struct LocalStorage {
    static func save(markdown: String, title: String, date: Date, directory: String) throws -> URL {
        let expandedDir = NSString(string: directory).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: expandedDir)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let dateStr = formatter.string(from: date)
        let safeTitle = title.replacingOccurrences(of: " ", with: "-").lowercased()
        let filename = "\(dateStr)-\(safeTitle).md"

        let fileURL = dirURL.appendingPathComponent(filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
