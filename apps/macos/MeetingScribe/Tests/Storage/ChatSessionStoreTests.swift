import Testing
import Foundation
@testable import MeetingScribe

@Suite("ChatSessionStore")
struct ChatSessionStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingscribe-chat-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("loads empty session when file missing")
    func loadsEmptySessionWhenFileMissing() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let store = ChatSessionStore()
        let session = try store.load(from: tempDir)
        #expect(session.messages.count == 0)
    }

    @Test("saves and loads messages")
    func savesAndLoadsMessages() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let store = ChatSessionStore()
        var session = ChatSession(messages: [])
        session.messages.append(.init(role: .user, text: "Hello"))
        session.messages.append(.init(role: .assistant, text: "Hi, how can I help?"))

        try store.save(session, to: tempDir)

        let loaded = try store.load(from: tempDir)
        #expect(loaded.messages.count == 2)
        #expect(loaded.messages[0].role == .user)
        #expect(loaded.messages[0].text == "Hello")
        #expect(loaded.messages[1].role == .assistant)
        #expect(loaded.messages[1].text == "Hi, how can I help?")
    }

    @Test("overwrites existing session atomically")
    func overwritesExistingSession() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let store = ChatSessionStore()
        var session = ChatSession(messages: [.init(role: .user, text: "First")])
        try store.save(session, to: tempDir)

        session.messages.append(.init(role: .assistant, text: "Second"))
        try store.save(session, to: tempDir)

        let loaded = try store.load(from: tempDir)
        #expect(loaded.messages.count == 2)
    }

    @Test("writes valid versioned JSON")
    func writesValidVersionedJSON() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let store = ChatSessionStore()
        let session = ChatSession(messages: [.init(role: .user, text: "Test")])
        try store.save(session, to: tempDir)

        let fileURL = tempDir.appendingPathComponent("chat.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["version"] as? Int == 1)
        #expect(json?["messages"] != nil)
    }
}
