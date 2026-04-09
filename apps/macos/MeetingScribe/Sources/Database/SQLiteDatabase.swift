import Foundation
import SQLite3

/// Manages the local SQLite database for meetings, transcripts, and summaries.
/// Schema mirrors the Prisma PostgreSQL schema for API compatibility.
final class SQLiteDatabase: @unchecked Sendable {
    private var db: OpaquePointer?

    static let shared = SQLiteDatabase()

    private init() {
        let dbDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MeetingScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("meetings.db").path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[SQLiteDatabase] Failed to open database at \(dbPath)")
            return
        }

        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")

        createTables()
        print("[SQLiteDatabase] Opened at \(dbPath)")
    }

    deinit {
        sqlite3_close(db)
    }

    private func createTables() {
        execute("""
            CREATE TABLE IF NOT EXISTS meetings (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                date TEXT NOT NULL,
                duration INTEGER NOT NULL,
                audioSources TEXT NOT NULL DEFAULT '[]',
                meetingType TEXT,
                calendarEventId TEXT,
                calendarTitle TEXT,
                calendarOrganizer TEXT,
                calendarAttendees TEXT NOT NULL DEFAULT '[]',
                calendarStart TEXT,
                calendarEnd TEXT,
                createdAt TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
                updatedAt TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS transcripts (
                id TEXT PRIMARY KEY,
                meetingId TEXT NOT NULL UNIQUE,
                rawMarkdown TEXT NOT NULL,
                FOREIGN KEY (meetingId) REFERENCES meetings(id) ON DELETE CASCADE
            )
        """)

        execute("""
            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                transcriptId TEXT NOT NULL,
                speaker TEXT NOT NULL,
                text TEXT NOT NULL,
                startTime REAL NOT NULL,
                endTime REAL NOT NULL,
                FOREIGN KEY (transcriptId) REFERENCES transcripts(id) ON DELETE CASCADE
            )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_segments_transcriptId ON segments(transcriptId)")

        execute("""
            CREATE TABLE IF NOT EXISTS summaries (
                id TEXT PRIMARY KEY,
                meetingId TEXT NOT NULL UNIQUE,
                content TEXT NOT NULL,
                promptUsed TEXT NOT NULL,
                generatedAt TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
                FOREIGN KEY (meetingId) REFERENCES meetings(id) ON DELETE CASCADE
            )
        """)
    }

    // MARK: - Helpers

    @discardableResult
    func execute(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[SQLiteDatabase] Error: \(msg)")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("[SQLiteDatabase] Failed to prepare: \(err)\nSQL: \(sql)")
            return nil
        }
        return stmt
    }
}
