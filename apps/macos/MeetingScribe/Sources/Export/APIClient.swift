import Foundation

final class MeetingAPIClient: Sendable {
    private let serverURL: String
    private let apiKey: String

    init(serverURL: String, apiKey: String = "") {
        self.serverURL = serverURL
        self.apiKey = apiKey
    }

    struct CalendarInfo {
        let eventId: String?
        let title: String?
        let organizer: String?
        let attendees: [String]
        let start: Date?
        let end: Date?
    }

    func uploadMeeting(
        title: String,
        date: Date,
        duration: Int,
        audioSources: [String],
        meetingType: String?,
        rawMarkdown: String,
        segments: [TranscriptSegment],
        calendar: CalendarInfo? = nil
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

        let isoFormatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "title": title,
            "date": isoFormatter.string(from: date),
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

        // Add calendar data if available
        if let cal = calendar {
            if let eventId = cal.eventId { body["calendarEventId"] = eventId }
            if let calTitle = cal.title { body["calendarTitle"] = calTitle }
            if let organizer = cal.organizer { body["calendarOrganizer"] = organizer }
            if !cal.attendees.isEmpty { body["calendarAttendees"] = cal.attendees }
            if let start = cal.start { body["calendarStart"] = isoFormatter.string(from: start) }
            if let end = cal.end { body["calendarEnd"] = isoFormatter.string(from: end) }
        }

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
