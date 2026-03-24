import AVFoundation
import Foundation

/// Records audio buffers to a WAV file for post-recording whisper.cpp transcription.
/// The macOS app does live transcription via SpeechTranscriber (lower accuracy, real-time)
/// and saves the raw audio so whisper.cpp can produce a higher-accuracy final transcript.
final class AudioFileWriter: @unchecked Sendable {
    private var audioFile: AVAudioFile?
    private let outputURL: URL

    init(directory: String, title: String, date: Date) {
        let expandedDir = NSString(string: directory).expandingTildeInPath
        let audioDir = URL(fileURLWithPath: expandedDir).appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let dateStr = formatter.string(from: date)
        let safeTitle = title.replacingOccurrences(of: " ", with: "-").lowercased()

        outputURL = audioDir.appendingPathComponent("\(dateStr)-\(safeTitle).wav")
    }

    func start(format: AVAudioFormat) throws {
        // Convert to 16kHz mono WAV — the format whisper.cpp expects
        guard let wavFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileError.invalidFormat
        }

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: wavFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    func write(buffer: AVAudioPCMBuffer) {
        try? audioFile?.write(from: buffer)
    }

    func stop() -> URL {
        audioFile = nil
        return outputURL
    }

    var fileURL: URL { outputURL }

    enum AudioFileError: Error {
        case invalidFormat
    }
}
