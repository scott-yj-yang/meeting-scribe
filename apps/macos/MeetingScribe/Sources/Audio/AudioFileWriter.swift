import AVFoundation
import Foundation

/// Records audio buffers to a WAV file for post-recording whisper.cpp transcription.
final class AudioFileWriter: @unchecked Sendable {
    private var audioFile: AVAudioFile?
    let fileURL: URL

    init(directory: String, title: String, date: Date) {
        let expandedDir = NSString(string: directory).expandingTildeInPath
        let audioDir = URL(fileURLWithPath: expandedDir).appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateStr = formatter.string(from: date)
        // Use simple filename without colons (colons cause issues on macOS)
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()

        fileURL = audioDir.appendingPathComponent("\(dateStr)-\(safeTitle).wav")
    }

    /// Start writing audio at the NATIVE format from the microphone.
    /// whisper-cli handles resampling internally — no need to convert to 16kHz.
    func start(format: AVAudioFormat) throws {
        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings
        )
        print("[AudioWriter] Writing at \(format.sampleRate) Hz, \(format.channelCount) ch")
    }

    func write(buffer: AVAudioPCMBuffer) {
        try? audioFile?.write(from: buffer)
    }

    func stop() -> URL {
        audioFile = nil
        return fileURL
    }
}
