import Foundation
import WebKit

/// Intercepts `app://api/...` requests from the React dashboard WKWebView
/// and handles them locally using SQLite, returning JSON responses.
final class APISchemeHandler: NSObject, WKURLSchemeHandler {
    private let repo = MeetingRepository.shared

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            respond(urlSchemeTask, status: 400, body: ["error": "Invalid request"])
            return
        }

        // Parse path from app://api/... URL
        // URL format: app://api/meetings/123 → host="api", path="/meetings/123"
        // or app:///api/meetings/123 → path="/api/meetings/123"
        let fullPath: String
        if let host = url.host, !host.isEmpty {
            fullPath = "/\(host)\(url.path)"
        } else {
            fullPath = url.path
        }

        let method = urlSchemeTask.request.httpMethod ?? "GET"
        let body = urlSchemeTask.request.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }

        // Route: /api/meetings
        if fullPath == "/api/meetings" || fullPath == "/api/meetings/" {
            handleMeetings(urlSchemeTask, method: method, body: body, url: url)
            return
        }

        // Route: /api/meetings/[id]/summarize/status
        if let id = extractId(from: fullPath, pattern: "/api/meetings/([^/]+)/summarize/status") {
            handleSummarizeStatus(urlSchemeTask, meetingId: id)
            return
        }

        // Route: /api/meetings/[id]/summarize
        if let id = extractId(from: fullPath, pattern: "/api/meetings/([^/]+)/summarize") {
            handleSummarize(urlSchemeTask, meetingId: id, method: method, body: body)
            return
        }

        // Route: /api/meetings/[id]/export
        if let id = extractId(from: fullPath, pattern: "/api/meetings/([^/]+)/export") {
            handleExport(urlSchemeTask, meetingId: id)
            return
        }

        // Route: /api/meetings/[id]/chat
        if let id = extractId(from: fullPath, pattern: "/api/meetings/([^/]+)/chat") {
            handleChat(urlSchemeTask, meetingId: id, method: method, body: body)
            return
        }

        // Route: /api/meetings/[id]
        if let id = extractId(from: fullPath, pattern: "/api/meetings/([^/]+)$") {
            handleMeeting(urlSchemeTask, id: id, method: method, body: body)
            return
        }

        // Route: /api/health/claude
        if fullPath == "/api/health/claude" {
            handleClaudeHealth(urlSchemeTask)
            return
        }

        respond(urlSchemeTask, status: 404, body: ["error": "Not found: \(fullPath)"])
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op for synchronous handlers
    }

    // MARK: - Route Handlers

    private func handleMeetings(_ task: any WKURLSchemeTask, method: String, body: [String: Any]?, url: URL) {
        switch method {
        case "GET":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let search = components?.queryItems?.first(where: { $0.name == "search" })?.value
            let type = components?.queryItems?.first(where: { $0.name == "type" })?.value
            let limit = Int(components?.queryItems?.first(where: { $0.name == "limit" })?.value ?? "") ?? 50
            let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "") ?? 0
            let meetings = repo.listMeetings(search: search, type: type, limit: limit, offset: offset)
            respond(task, status: 200, body: ["meetings": meetings, "total": meetings.count])
        case "POST":
            guard let body = body else {
                respond(task, status: 400, body: ["error": "Missing body"])
                return
            }
            if let meeting = repo.createMeeting(body) {
                respond(task, status: 201, body: meeting)
            } else {
                respond(task, status: 500, body: ["error": "Failed to create meeting"])
            }
        default:
            respond(task, status: 405, body: ["error": "Method not allowed"])
        }
    }

    private func handleMeeting(_ task: any WKURLSchemeTask, id: String, method: String, body: [String: Any]?) {
        switch method {
        case "GET":
            if let meeting = repo.getMeeting(id: id) {
                respond(task, status: 200, body: meeting)
            } else {
                respond(task, status: 404, body: ["error": "Meeting not found"])
            }
        case "DELETE":
            repo.deleteMeeting(id: id)
            respondEmpty(task, status: 204)
        default:
            respond(task, status: 405, body: ["error": "Method not allowed"])
        }
    }

    private func handleSummarize(_ task: any WKURLSchemeTask, meetingId: String, method: String, body: [String: Any]?) {
        if method == "POST" {
            let template = body?["template"] as? String ?? "default"
            Task.detached { [repo] in
                await self.runSummarization(meetingId: meetingId, template: template, repo: repo)
            }
            respond(task, status: 202, body: ["status": "started", "meetingId": meetingId])
        } else if method == "DELETE" {
            respond(task, status: 200, body: ["status": "cancelled"])
        } else {
            respond(task, status: 405, body: ["error": "Method not allowed"])
        }
    }

    private func handleSummarizeStatus(_ task: any WKURLSchemeTask, meetingId: String) {
        if repo.getSummary(meetingId: meetingId) != nil {
            respond(task, status: 200, body: ["status": "completed"])
        } else {
            respond(task, status: 200, body: ["status": "idle"])
        }
    }

    private func handleExport(_ task: any WKURLSchemeTask, meetingId: String) {
        guard let meeting = repo.getMeeting(id: meetingId),
              let transcript = meeting["transcript"] as? [String: Any],
              let rawMarkdown = transcript["rawMarkdown"] as? String else {
            respond(task, status: 404, body: ["error": "Not found"])
            return
        }

        let data = rawMarkdown.data(using: String.Encoding.utf8) ?? Data()
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/markdown; charset=utf-8",
                "Content-Disposition": "attachment; filename=\"transcript.md\"",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func handleChat(_ task: any WKURLSchemeTask, meetingId: String, method: String, body: [String: Any]?) {
        // Chat requires streaming (SSE) which WKURLSchemeHandler doesn't support well.
        // Return a simple non-streaming response for now.
        respond(task, status: 501, body: ["error": "Chat is not yet supported in desktop mode. Use the web app for chat."])
    }

    private func handleClaudeHealth(_ task: any WKURLSchemeTask) {
        let paths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     "\(NSHomeDirectory())/.local/bin/claude"]
        let available = paths.contains(where: { FileManager.default.fileExists(atPath: $0) })
        respond(task, status: 200, body: ["status": available ? "ready" : "not_installed"])
    }

    // MARK: - Summarization

    private func runSummarization(meetingId: String, template: String, repo: MeetingRepository) async {
        guard let meeting = repo.getMeeting(id: meetingId),
              let transcript = meeting["transcript"] as? [String: Any],
              let rawMarkdown = transcript["rawMarkdown"] as? String else {
            print("[Summarize] Meeting or transcript not found: \(meetingId)")
            return
        }

        let tmpFile = NSTemporaryDirectory() + "meetingscribe-\(meetingId).md"
        try? rawMarkdown.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        // Find prompt template
        let promptDirs = [
            Bundle.main.resourcePath.map { "\($0)/prompts/templates" },
            "\(NSHomeDirectory())/Developer/meeting-scribe/prompts/templates",
        ].compactMap { $0 }

        var promptContent: String?
        for dir in promptDirs {
            let path = "\(dir)/\(template).md"
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                promptContent = content
                break
            }
        }

        guard let prompt = promptContent else {
            print("[Summarize] Template '\(template)' not found")
            return
        }

        let fullPrompt = "\(prompt)\n\nThe meeting transcript file is located at: \(tmpFile)\nPlease read that file and produce the summary."

        // Find claude CLI
        let claudePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(NSHomeDirectory())/.local/bin/claude"]
        guard let claudePath = claudePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            print("[Summarize] Claude CLI not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--allowedTools", "Read", "-p", fullPrompt]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                repo.upsertSummary(meetingId: meetingId, content: output, promptUsed: template)
                print("[Summarize] Summary saved for \(meetingId)")
            }
        } catch {
            print("[Summarize] Error: \(error)")
        }
    }

    // MARK: - Helpers

    private func extractId(from path: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else { return nil }
        return String(path[range])
    }

    private func respond(_ task: any WKURLSchemeTask, status: Int, body: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            respondEmpty(task, status: 500)
            return
        }
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func respondEmpty(_ task: any WKURLSchemeTask, status: Int) {
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        task.didReceive(response)
        task.didFinish()
    }
}
