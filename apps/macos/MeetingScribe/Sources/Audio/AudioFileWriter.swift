@preconcurrency import AVFoundation
import Foundation

/// Records audio buffers to a WAV file for whisper.cpp transcription.
/// Accepts buffers from both mic and system audio, writing them all
/// to a single file so whisper gets the full conversation.
final class AudioFileWriter: @unchecked Sendable {
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    let fileURL: URL

    init(directory: String, title: String, date: Date) {
        let expandedDir = NSString(string: directory).expandingTildeInPath
        let audioDir = URL(fileURLWithPath: expandedDir).appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateStr = formatter.string(from: date)
        let safeTitle = title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()

        fileURL = audioDir.appendingPathComponent("\(dateStr)-\(safeTitle).wav")
    }

    /// Start writing audio at the given format from the microphone.
    func start(format: AVAudioFormat) throws {
        outputFormat = format
        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings
        )
        print("[AudioWriter] Writing at \(format.sampleRate) Hz, \(format.channelCount) ch")
    }

    /// Write a mic buffer (AVAudioPCMBuffer) directly
    func write(buffer: AVAudioPCMBuffer) {
        try? audioFile?.write(from: buffer)
    }

    /// Write a system audio buffer (CMSampleBuffer) by converting to PCM first
    func writeSystemAudio(sampleBuffer: CMSampleBuffer) {
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer) else { return }

        // If system audio format differs from output, resample
        guard let outFmt = outputFormat else {
            try? audioFile?.write(from: pcmBuffer)
            return
        }

        if pcmBuffer.format.sampleRate == outFmt.sampleRate &&
           pcmBuffer.format.channelCount == outFmt.channelCount {
            try? audioFile?.write(from: pcmBuffer)
        } else {
            // Convert to match output format
            if let converted = resample(buffer: pcmBuffer, to: outFmt) {
                try? audioFile?.write(from: converted)
            }
        }
    }

    func stop() -> URL {
        audioFile = nil
        converter = nil
        outputFormat = nil
        return fileURL
    }

    // MARK: - Private

    private func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        guard let format = AVAudioFormat(streamDescription: asbd) else { return nil }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let src = dataPointer, let dst = pcmBuffer.floatChannelData?[0] else { return nil }
        memcpy(dst, src, min(length, Int(pcmBuffer.frameCapacity) * MemoryLayout<Float>.size))

        return pcmBuffer
    }

    private func resample(buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter = converter else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames) else {
            return nil
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return error == nil ? outputBuffer : nil
    }
}
