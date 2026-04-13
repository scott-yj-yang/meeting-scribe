import Foundation

/// Version-tagged envelope persisted to chat.json per meeting.
struct ChatSession: Codable, Sendable {
    var version: Int
    var messages: [ChatMessage]

    init(version: Int = 1, messages: [ChatMessage]) {
        self.version = version
        self.messages = messages
    }
}

/// Loads and saves a `ChatSession` to `<meetingDir>/chat.json`.
struct ChatSessionStore: Sendable {
    init() {}

    private static let filename = "chat.json"

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load(from meetingDir: URL) throws -> ChatSession {
        let fileURL = meetingDir.appendingPathComponent(Self.filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ChatSession(messages: [])
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ChatSession.self, from: data)
    }

    func save(_ session: ChatSession, to meetingDir: URL) throws {
        // Ensure dir exists
        try FileManager.default.createDirectory(
            at: meetingDir,
            withIntermediateDirectories: true
        )
        let fileURL = meetingDir.appendingPathComponent(Self.filename)
        let data = try encoder.encode(session)
        // Atomic write
        try data.write(to: fileURL, options: .atomic)
    }
}
