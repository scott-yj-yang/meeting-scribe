import Foundation
import SQLite3

// SQLITE_TRANSIENT is not exported as a Swift constant; define it explicitly.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Provides CRUD operations for meetings against the local SQLite database.
/// Returns `[String: Any]` dictionaries that match the Next.js API response format
/// so React components work without modification.
final class MeetingRepository: @unchecked Sendable {
    static let shared = MeetingRepository()
    private let db = SQLiteDatabase.shared

    private init() {}

    // MARK: - List Meetings

    /// Returns meetings ordered by date descending, with optional search and type filters.
    /// Response mirrors GET /api/meetings: `{ meetings: [...], total: N, page: N, limit: N }`
    /// Each meeting row includes a `summary` stub (id + generatedAt) when one exists.
    func listMeetings(search: String?, type: String?, limit: Int, offset: Int) -> [[String: Any]] {
        var conditions: [String] = []
        var bindings: [(index: Int32, value: BindValue)] = []
        var paramIndex: Int32 = 1

        if let search = search, !search.isEmpty {
            conditions.append("(m.title LIKE ? OR t.rawMarkdown LIKE ?)")
            let pattern = "%\(search)%"
            bindings.append((paramIndex, .text(pattern))); paramIndex += 1
            bindings.append((paramIndex, .text(pattern))); paramIndex += 1
        }

        if let type = type, !type.isEmpty {
            conditions.append("m.meetingType = ?")
            bindings.append((paramIndex, .text(type))); paramIndex += 1
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let sql = """
            SELECT
                m.id, m.title, m.date, m.duration,
                m.audioSources, m.meetingType,
                m.calendarEventId, m.calendarTitle, m.calendarOrganizer,
                m.calendarAttendees, m.calendarStart, m.calendarEnd,
                m.createdAt, m.updatedAt,
                s.id AS summaryId, s.generatedAt AS summaryGeneratedAt
            FROM meetings m
            LEFT JOIN transcripts t ON t.meetingId = m.id
            LEFT JOIN summaries s ON s.meetingId = m.id
            \(whereClause)
            ORDER BY m.date DESC
            LIMIT ? OFFSET ?
        """

        bindings.append((paramIndex, .integer(Int64(limit)))); paramIndex += 1
        bindings.append((paramIndex, .integer(Int64(offset))))

        guard let stmt = db.prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        bindAll(stmt, bindings)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            row["id"]            = text(stmt, col: 0)
            row["title"]         = text(stmt, col: 1)
            row["date"]          = text(stmt, col: 2)
            row["duration"]      = Int(sqlite3_column_int64(stmt, 3))
            row["audioSources"]  = parseJSONArray(text(stmt, col: 4))
            row["meetingType"]   = nullableText(stmt, col: 5)
            row["calendarEventId"]    = nullableText(stmt, col: 6)
            row["calendarTitle"]      = nullableText(stmt, col: 7)
            row["calendarOrganizer"]  = nullableText(stmt, col: 8)
            row["calendarAttendees"]  = parseJSONArray(text(stmt, col: 9))
            row["calendarStart"]      = nullableText(stmt, col: 10)
            row["calendarEnd"]        = nullableText(stmt, col: 11)
            row["createdAt"]     = text(stmt, col: 12)
            row["updatedAt"]     = text(stmt, col: 13)

            // Inline summary stub (id + generatedAt only, matching Prisma select)
            if let summaryId = nullableText(stmt, col: 14) {
                var summaryStub: [String: Any] = ["id": summaryId]
                if let generatedAt = nullableText(stmt, col: 15) {
                    summaryStub["generatedAt"] = generatedAt
                }
                row["summary"] = summaryStub
            } else {
                row["summary"] = NSNull()
            }

            results.append(row)
        }
        return results
    }

    // MARK: - Get Meeting

    /// Returns a single meeting with full transcript (+ segments) and summary.
    /// Response mirrors GET /api/meetings/[id].
    func getMeeting(id: String) -> [String: Any]? {
        let sql = """
            SELECT
                m.id, m.title, m.date, m.duration,
                m.audioSources, m.meetingType,
                m.calendarEventId, m.calendarTitle, m.calendarOrganizer,
                m.calendarAttendees, m.calendarStart, m.calendarEnd,
                m.createdAt, m.updatedAt
            FROM meetings m
            WHERE m.id = ?
        """
        guard let stmt = db.prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        var meeting: [String: Any] = [:]
        meeting["id"]            = text(stmt, col: 0)
        meeting["title"]         = text(stmt, col: 1)
        meeting["date"]          = text(stmt, col: 2)
        meeting["duration"]      = Int(sqlite3_column_int64(stmt, 3))
        meeting["audioSources"]  = parseJSONArray(text(stmt, col: 4))
        meeting["meetingType"]   = nullableText(stmt, col: 5)
        meeting["calendarEventId"]    = nullableText(stmt, col: 6)
        meeting["calendarTitle"]      = nullableText(stmt, col: 7)
        meeting["calendarOrganizer"]  = nullableText(stmt, col: 8)
        meeting["calendarAttendees"]  = parseJSONArray(text(stmt, col: 9))
        meeting["calendarStart"]      = nullableText(stmt, col: 10)
        meeting["calendarEnd"]        = nullableText(stmt, col: 11)
        meeting["createdAt"]     = text(stmt, col: 12)
        meeting["updatedAt"]     = text(stmt, col: 13)

        meeting["transcript"] = fetchTranscript(meetingId: id)
        meeting["summary"]    = fetchSummary(meetingId: id) ?? NSNull()

        return meeting
    }

    // MARK: - Create Meeting

    /// Creates a meeting row (and optional transcript + segments) from a POST body.
    /// Returns the created meeting in the same format as getMeeting.
    @discardableResult
    func createMeeting(_ data: [String: Any]) -> [String: Any]? {
        guard
            let title    = data["title"]    as? String,
            let date     = data["date"]     as? String,
            let duration = data["duration"] as? Int
        else {
            print("[MeetingRepository] createMeeting: missing required fields")
            return nil
        }

        let meetingId  = (data["id"] as? String) ?? UUID().uuidString
        let now        = isoNow()
        let audioSources     = jsonStringFrom(data["audioSources"])     ?? "[]"
        let calendarAttendees = jsonStringFrom(data["calendarAttendees"]) ?? "[]"
        let meetingType      = data["meetingType"]      as? String
        let calendarEventId  = data["calendarEventId"]  as? String
        let calendarTitle    = data["calendarTitle"]    as? String
        let calendarOrganizer = data["calendarOrganizer"] as? String
        let calendarStart    = data["calendarStart"]    as? String
        let calendarEnd      = data["calendarEnd"]      as? String

        let insertSQL = """
            INSERT INTO meetings
                (id, title, date, duration, audioSources, meetingType,
                 calendarEventId, calendarTitle, calendarOrganizer,
                 calendarAttendees, calendarStart, calendarEnd,
                 createdAt, updatedAt)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        guard let stmt = db.prepare(insertSQL) else { return nil }
        defer { sqlite3_finalize(stmt) }

        let bindings: [(Int32, BindValue)] = [
            (1,  .text(meetingId)),
            (2,  .text(title)),
            (3,  .text(date)),
            (4,  .integer(Int64(duration))),
            (5,  .text(audioSources)),
            (6,  meetingType.map { .text($0) } ?? .null),
            (7,  calendarEventId.map  { .text($0) } ?? .null),
            (8,  calendarTitle.map    { .text($0) } ?? .null),
            (9,  calendarOrganizer.map { .text($0) } ?? .null),
            (10, .text(calendarAttendees)),
            (11, calendarStart.map { .text($0) } ?? .null),
            (12, calendarEnd.map   { .text($0) } ?? .null),
            (13, .text(now)),
            (14, .text(now)),
        ]
        bindAll(stmt, bindings)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(nil))
            print("[MeetingRepository] createMeeting insert failed: \(err)")
            return nil
        }

        // Optional transcript + segments
        if let rawMarkdown = data["rawMarkdown"] as? String {
            let segments = data["segments"] as? [[String: Any]] ?? []
            createTranscript(meetingId: meetingId, rawMarkdown: rawMarkdown, segments: segments)
        }

        return getMeeting(id: meetingId)
    }

    // MARK: - Delete Meeting

    /// Deletes a meeting by id. Cascades to transcript, segments, and summary via FK.
    @discardableResult
    func deleteMeeting(id: String) -> Bool {
        guard let stmt = db.prepare("DELETE FROM meetings WHERE id = ?") else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - Summary

    /// Returns the summary for a meeting, or nil if none exists.
    func getSummary(meetingId: String) -> [String: Any]? {
        return fetchSummary(meetingId: meetingId)
    }

    /// Creates or updates the summary for a meeting.
    @discardableResult
    func upsertSummary(meetingId: String, content: String, promptUsed: String) -> Bool {
        // Check if one already exists
        let existingSQL = "SELECT id FROM summaries WHERE meetingId = ?"
        guard let checkStmt = db.prepare(existingSQL) else { return false }
        defer { sqlite3_finalize(checkStmt) }
        sqlite3_bind_text(checkStmt, 1, meetingId, -1, SQLITE_TRANSIENT)

        if sqlite3_step(checkStmt) == SQLITE_ROW {
            // Update
            let updateSQL = """
                UPDATE summaries
                SET content = ?, promptUsed = ?, generatedAt = ?
                WHERE meetingId = ?
            """
            guard let stmt = db.prepare(updateSQL) else { return false }
            defer { sqlite3_finalize(stmt) }
            let bindings: [(Int32, BindValue)] = [
                (1, .text(content)),
                (2, .text(promptUsed)),
                (3, .text(isoNow())),
                (4, .text(meetingId)),
            ]
            bindAll(stmt, bindings)
            return sqlite3_step(stmt) == SQLITE_DONE
        } else {
            // Insert
            let insertSQL = """
                INSERT INTO summaries (id, meetingId, content, promptUsed, generatedAt)
                VALUES (?, ?, ?, ?, ?)
            """
            guard let stmt = db.prepare(insertSQL) else { return false }
            defer { sqlite3_finalize(stmt) }
            let bindings: [(Int32, BindValue)] = [
                (1, .text(UUID().uuidString)),
                (2, .text(meetingId)),
                (3, .text(content)),
                (4, .text(promptUsed)),
                (5, .text(isoNow())),
            ]
            bindAll(stmt, bindings)
            return sqlite3_step(stmt) == SQLITE_DONE
        }
    }

    // MARK: - Private Helpers

    private func fetchTranscript(meetingId: String) -> [String: Any]? {
        let sql = "SELECT id, meetingId, rawMarkdown FROM transcripts WHERE meetingId = ?"
        guard let stmt = db.prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, meetingId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let transcriptId = text(stmt, col: 0)
        var transcript: [String: Any] = [
            "id":          transcriptId,
            "meetingId":   text(stmt, col: 1),
            "rawMarkdown": text(stmt, col: 2),
        ]
        transcript["segments"] = fetchSegments(transcriptId: transcriptId)
        return transcript
    }

    private func fetchSegments(transcriptId: String) -> [[String: Any]] {
        let sql = """
            SELECT id, transcriptId, speaker, text, startTime, endTime
            FROM segments
            WHERE transcriptId = ?
            ORDER BY startTime ASC
        """
        guard let stmt = db.prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, transcriptId, -1, SQLITE_TRANSIENT)

        var segments: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let segment: [String: Any] = [
                "id":           text(stmt, col: 0),
                "transcriptId": text(stmt, col: 1),
                "speaker":      text(stmt, col: 2),
                "text":         text(stmt, col: 3),
                "startTime":    sqlite3_column_double(stmt, 4),
                "endTime":      sqlite3_column_double(stmt, 5),
            ]
            segments.append(segment)
        }
        return segments
    }

    private func fetchSummary(meetingId: String) -> [String: Any]? {
        let sql = "SELECT id, meetingId, content, promptUsed, generatedAt FROM summaries WHERE meetingId = ?"
        guard let stmt = db.prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, meetingId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return [
            "id":          text(stmt, col: 0),
            "meetingId":   text(stmt, col: 1),
            "content":     text(stmt, col: 2),
            "promptUsed":  text(stmt, col: 3),
            "generatedAt": text(stmt, col: 4),
        ]
    }

    private func createTranscript(meetingId: String, rawMarkdown: String, segments: [[String: Any]]) {
        let transcriptId = UUID().uuidString
        let sql = "INSERT INTO transcripts (id, meetingId, rawMarkdown) VALUES (?, ?, ?)"
        guard let stmt = db.prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        let bindings: [(Int32, BindValue)] = [
            (1, .text(transcriptId)),
            (2, .text(meetingId)),
            (3, .text(rawMarkdown)),
        ]
        bindAll(stmt, bindings)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return }

        for seg in segments {
            createSegment(transcriptId: transcriptId, data: seg)
        }
    }

    private func createSegment(transcriptId: String, data: [String: Any]) {
        let speaker   = data["speaker"]   as? String ?? ""
        let text_     = data["text"]      as? String ?? ""
        let startTime = (data["startTime"] as? Double) ?? 0.0
        let endTime   = (data["endTime"]   as? Double) ?? 0.0

        let sql = """
            INSERT INTO segments (id, transcriptId, speaker, text, startTime, endTime)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        guard let stmt = db.prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        let bindings: [(Int32, BindValue)] = [
            (1, .text(UUID().uuidString)),
            (2, .text(transcriptId)),
            (3, .text(speaker)),
            (4, .text(text_)),
            (5, .real(startTime)),
            (6, .real(endTime)),
        ]
        bindAll(stmt, bindings)
        sqlite3_step(stmt)
    }

    // MARK: - Binding Utilities

    private enum BindValue {
        case text(String)
        case integer(Int64)
        case real(Double)
        case null
    }

    private func bindAll(_ stmt: OpaquePointer, _ bindings: [(index: Int32, value: BindValue)]) {
        for (index, value) in bindings {
            switch value {
            case .text(let s):
                sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
            case .integer(let i):
                sqlite3_bind_int64(stmt, index, i)
            case .real(let d):
                sqlite3_bind_double(stmt, index, d)
            case .null:
                sqlite3_bind_null(stmt, index)
            }
        }
    }

    // Convenience overload that accepts non-named tuples
    private func bindAll(_ stmt: OpaquePointer, _ bindings: [(Int32, BindValue)]) {
        for (index, value) in bindings {
            switch value {
            case .text(let s):
                sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
            case .integer(let i):
                sqlite3_bind_int64(stmt, index, i)
            case .real(let d):
                sqlite3_bind_double(stmt, index, d)
            case .null:
                sqlite3_bind_null(stmt, index)
            }
        }
    }

    // MARK: - Column Readers

    private func text(_ stmt: OpaquePointer, col: Int32) -> String {
        if let ptr = sqlite3_column_text(stmt, col) {
            return String(cString: ptr)
        }
        return ""
    }

    private func nullableText(_ stmt: OpaquePointer, col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: ptr)
    }

    // MARK: - JSON Helpers

    /// Parses a JSON-encoded text column back into an array (e.g. `["microphone"]`).
    private func parseJSONArray(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return array
    }

    /// Serializes an array or other JSON-compatible value to a JSON string for storage.
    private func jsonStringFrom(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns the current time as an ISO-8601 string matching SQLite's `strftime` default.
    private func isoNow() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
    }
}
