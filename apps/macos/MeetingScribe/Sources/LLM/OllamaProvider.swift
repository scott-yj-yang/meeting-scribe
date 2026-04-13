import Foundation

struct OllamaModel: Identifiable, Hashable {
    let name: String
    let size: Int64
    var id: String { name }
}

final class OllamaProvider: LLMProvider {
    let endpoint: String
    let model: String
    private let urlSession: URLSession

    var displayName: String { "Ollama (\(model))" }

    init(endpoint: String, model: String, urlSession: URLSession = .shared) {
        // Defense in depth: trim any stray whitespace or newline that might
        // have landed in the endpoint via copy/paste. A trailing \n makes
        // URL(string:) succeed (Foundation is lenient) but CFNetwork then
        // rejects the request with NSURLErrorUnsupportedURL (-1002).
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    /// GET {endpoint}/api/tags — returns installed models.
    func listModels() async throws -> [OllamaModel] {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw NSError(domain: "Ollama", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint"])
        }
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Ollama", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama not reachable at \(endpoint)"])
        }
        struct TagsResponse: Decodable {
            struct Entry: Decodable { let name: String; let size: Int64 }
            let models: [Entry]
        }
        let parsed = try JSONDecoder().decode(TagsResponse.self, from: data)
        return parsed.models.map { OllamaModel(name: $0.name, size: $0.size) }
    }

    /// Lightweight health check. Returns true if the Ollama daemon answers
    /// /api/tags within 2 seconds. Never throws — returns false for any failure.
    func isHealthy() async -> Bool {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    /// POST {endpoint}/v1/chat/completions with stream: true — parse SSE "data: {...}" lines.
    func summarize(
        transcript: String,
        template: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let promptContent = try loadTemplate(template)
        let systemPrompt = promptContent
        let userPrompt = "Here is the meeting transcript:\n\n\(transcript)"

        guard let url = URL(string: "\(endpoint)/v1/chat/completions") else {
            throw NSError(domain: "Ollama", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ollama chat request failed"])
        }

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                fullText += content
                onToken(content)
            }
        }
        return fullText
    }

    func chat(
        messages: [ChatMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: "\(endpoint)/v1/chat/completions") else {
            throw NSError(domain: "Ollama", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ollama chat request failed"])
        }

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                fullText += content
                onToken(content)
            }
        }
        return fullText
    }

    private func loadTemplate(_ name: String) throws -> String {
        let homeDir = NSHomeDirectory()
        let templateDirs = [
            "\(homeDir)/Developer/meeting-scribe/prompts/templates",
            "\(homeDir)/Developer/meeting-scribe/prompts",
        ]
        for dir in templateDirs {
            for candidate in [name, "summarize"] {
                let path = "\(dir)/\(candidate).md"
                if let c = try? String(contentsOfFile: path, encoding: .utf8), !c.isEmpty {
                    return c
                }
            }
        }
        throw NSError(domain: "Ollama", code: 3, userInfo: [NSLocalizedDescriptionKey: "No prompt template found"])
    }
}
