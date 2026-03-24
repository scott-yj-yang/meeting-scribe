import Foundation

actor UploadQueue {
    private var queue: [PendingUpload] = []
    private let storageKey = "pendingUploads"

    struct PendingUpload: Codable {
        let filePath: String
        let title: String
        let date: Date
        let duration: Int
        let audioSources: [String]
        let meetingType: String?
    }

    func enqueue(_ upload: PendingUpload) {
        queue.append(upload)
        save()
    }

    func processQueue(client: MeetingAPIClient) async {
        var remaining: [PendingUpload] = []

        for upload in queue {
            do {
                let markdown = try String(contentsOfFile: upload.filePath, encoding: .utf8)
                _ = try await client.uploadMeeting(
                    title: upload.title,
                    date: upload.date,
                    duration: upload.duration,
                    audioSources: upload.audioSources,
                    meetingType: upload.meetingType,
                    rawMarkdown: markdown,
                    segments: []
                )
            } catch {
                remaining.append(upload)
            }
        }

        queue = remaining
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let uploads = try? JSONDecoder().decode([PendingUpload].self, from: data) {
            queue = uploads
        }
    }

    var pendingCount: Int { queue.count }
}
