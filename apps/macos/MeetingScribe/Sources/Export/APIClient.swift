import Foundation

final class MeetingAPIClient: Sendable {
    private let serverURL: String
    private let apiKey: String

    init(serverURL: String, apiKey: String = "") {
        self.serverURL = serverURL
        self.apiKey = apiKey
    }

    func uploadMeeting(
        title: String,
        date: Date,
        duration: Int,
        audioSources: [String],
        meetingType: String?,
        rawMarkdown: String,
        segments: [TranscriptSegment]
    ) async throws -> String {
        guard let url = URL(string: "\(serverURL)/api/meetings") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "title": title,
            "date": ISO8601DateFormatter().string(from: date),
            "duration": duration,
            "audioSources": audioSources,
            "meetingType": meetingType as Any,
            "rawMarkdown": rawMarkdown,
            "segments": segments.map { seg in
                [
                    "speaker": seg.speaker,
                    "text": seg.text,
                    "startTime": seg.startTime,
                    "endTime": seg.endTime,
                ] as [String: Any]
            },
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw APIError.uploadFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return result?["id"] as? String ?? ""
    }

    enum APIError: Error {
        case invalidURL
        case uploadFailed
    }
}
