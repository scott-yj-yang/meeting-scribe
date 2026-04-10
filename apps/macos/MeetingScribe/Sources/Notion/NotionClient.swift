import Foundation

final class NotionClient {
    private let token: String
    private let baseURL = URL(string: "https://api.notion.com/v1")!
    private let urlSession: URLSession

    init(token: String, urlSession: URLSession = .shared) {
        self.token = token
        self.urlSession = urlSession
    }

    struct DatabaseInfo {
        let id: String
        let title: String
    }

    enum NotionError: LocalizedError {
        case invalidResponse
        case apiError(Int, String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from Notion API"
            case .apiError(let code, let msg): return "Notion API \(code): \(msg)"
            }
        }
    }

    private func makeRequest(path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// Verify credentials by retrieving a database.
    func retrieveDatabase(id: String) async throws -> DatabaseInfo {
        let cleanId = id.replacingOccurrences(of: "-", with: "")
        let request = try makeRequest(path: "databases/\(cleanId)", method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse }
        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.apiError(http.statusCode, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let titleArr = obj["title"] as? [[String: Any]] else {
            throw NotionError.invalidResponse
        }
        let title = titleArr.compactMap { ($0["plain_text"] as? String) }.joined()
        return DatabaseInfo(id: cleanId, title: title.isEmpty ? "(untitled)" : title)
    }

    /// Create a page in a database with the given title, properties, and children blocks.
    /// Returns the page ID.
    func createPage(
        databaseId: String,
        title: String,
        titlePropertyName: String = "Name",
        extraProperties: [String: Any] = [:],
        children: [[String: Any]]
    ) async throws -> String {
        // Notion caps children at 100 per request
        let firstBatch = Array(children.prefix(100))
        let rest = Array(children.dropFirst(100))

        var properties: [String: Any] = extraProperties
        properties[titlePropertyName] = [
            "title": [
                ["text": ["content": title]]
            ]
        ]

        let body: [String: Any] = [
            "parent": ["database_id": databaseId.replacingOccurrences(of: "-", with: "")],
            "properties": properties,
            "children": firstBatch,
        ]
        let request = try makeRequest(path: "pages", method: "POST", body: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse }
        if http.statusCode != 200 && http.statusCode != 201 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.apiError(http.statusCode, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageId = obj["id"] as? String else {
            throw NotionError.invalidResponse
        }

        // Append any overflow children
        if !rest.isEmpty {
            try await appendChildren(blockId: pageId, children: rest)
        }
        return pageId
    }

    /// Append up to 100 children at a time to a parent block.
    func appendChildren(blockId: String, children: [[String: Any]]) async throws {
        let clean = blockId.replacingOccurrences(of: "-", with: "")
        var remaining = children
        while !remaining.isEmpty {
            let batch = Array(remaining.prefix(100))
            remaining = Array(remaining.dropFirst(100))
            let body: [String: Any] = ["children": batch]
            let request = try makeRequest(path: "blocks/\(clean)/children", method: "PATCH", body: body)
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse }
            if http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw NotionError.apiError(http.statusCode, msg)
            }
        }
    }
}
