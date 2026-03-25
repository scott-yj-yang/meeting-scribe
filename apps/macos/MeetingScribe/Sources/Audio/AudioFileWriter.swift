@preconcurrency import AVFoundation
import Foundation

/// Records mic and system audio to separate WAV files, then merges them
/// into a single file for whisper.cpp. This avoids choppy interleaving
/// that happens when two async streams write to the same file.
final class AudioFileWriter: @unchecked Sendable {
    private var micFile: AVAudioFile?
    private var sysFile: AVAudioFile?
    private var outputFormat: AVAudioFormat?
    private var sysConverter: AVAudioConverter?

    let fileURL: URL          // final merged output
    private let micURL: URL   // temp mic-only file
    private let sysURL: URL   // temp system-only file
    private let meetingDir: URL
    private var micStartTime: Date?
    private var sysStartTime: Date?

    init(directory: String, title: String, date: Date) {
        meetingDir = LocalStorage.meetingDirectory(title: title, date: date, baseDirectory: directory)
        try? FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)
        fileURL = meetingDir.appendingPathComponent("audio.wav")
        micURL = meetingDir.appendingPathComponent(".mic_temp.wav")
        sysURL = meetingDir.appendingPathComponent(".sys_temp.wav")
    }

    func start(format: AVAudioFormat) throws {
        outputFormat = format
        micFile = try AVAudioFile(forWriting: micURL, settings: format.settings)
        sysFile = try AVAudioFile(forWriting: sysURL, settings: format.settings)
        print("[AudioWriter] Mic: \(format.sampleRate) Hz, \(format.channelCount) ch")
    }

    /// Write mic buffer — direct, same format
    func write(buffer: AVAudioPCMBuffer) {
        if micStartTime == nil { micStartTime = Date() }
        try? micFile?.write(from: buffer)
    }

    /// Write system audio buffer — convert format if needed
    func writeSystemAudio(sampleBuffer: CMSampleBuffer) {
        if sysStartTime == nil { sysStartTime = Date() }
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer) else { return }
        guard let outFmt = outputFormat else { return }

        if pcmBuffer.format.sampleRate == outFmt.sampleRate &&
           pcmBuffer.format.channelCount == outFmt.channelCount {
            try? sysFile?.write(from: pcmBuffer)
        } else {
            if let converted = resample(buffer: pcmBuffer, to: outFmt) {
                try? sysFile?.write(from: converted)
            }
        }
    }

    /// Stop recording and merge the two files
    func stop() -> URL {
        micFile = nil
        sysFile = nil
        sysConverter = nil

        // Merge mic + system audio using ffmpeg
        mergeFiles()

        return fileURL
    }

    // MARK: - Private

    private func mergeFiles() {
        let fm = FileManager.default
        let micExists = fm.fileExists(atPath: micURL.path)
        let sysExists = fm.fileExists(atPath: sysURL.path)

        if micExists && sysExists {
            // Calculate timing offset between mic and system audio start
            var sysDelay: Double = 0
            if let micStart = micStartTime, let sysStart = sysStartTime {
                sysDelay = sysStart.timeIntervalSince(micStart)
                print("[AudioWriter] Stream offset: \(String(format: "%.3f", sysDelay))s (sys started \(sysDelay > 0 ? "after" : "before") mic)")
            }

            // Merge with offset correction and echo reduction
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")

            // Build filter: delay the later stream to align, then mix
            let delayMs = Int(abs(sysDelay) * 1000)
            var filterComplex: String
            if sysDelay > 0.01 {
                // System started after mic — delay mic or pad system
                filterComplex = "[0:a]volume=0.5,adelay=\(delayMs)|0[mic];[1:a]volume=0.5[sys];[mic][sys]amix=inputs=2:duration=longest[mixed];[mixed]dynaudnorm=p=0.95[out]"
            } else if sysDelay < -0.01 {
                // System started before mic — delay system
                filterComplex = "[0:a]volume=0.5[mic];[1:a]volume=0.5,adelay=\(delayMs)|0[sys];[mic][sys]amix=inputs=2:duration=longest[mixed];[mixed]dynaudnorm=p=0.95[out]"
            } else {
                // Close enough — just mix with volume reduction + normalization
                filterComplex = "[0:a]volume=0.5[mic];[1:a]volume=0.5[sys];[mic][sys]amix=inputs=2:duration=longest[mixed];[mixed]dynaudnorm=p=0.95[out]"
            }

            process.arguments = [
                "-i", micURL.path,
                "-i", sysURL.path,
                "-filter_complex", filterComplex,
                "-map", "[out]",
                "-ac", "1",
                "-ar", "48000",
                "-y",
                fileURL.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    print("[AudioWriter] Merged mic + system audio")
                } else {
                    // ffmpeg failed — fall back to mic-only
                    print("[AudioWriter] Merge failed, using mic-only")
                    try? fm.moveItem(at: micURL, to: fileURL)
                }
            } catch {
                // ffmpeg not found — fall back to mic-only
                print("[AudioWriter] ffmpeg not available, using mic-only")
                try? fm.moveItem(at: micURL, to: fileURL)
            }
        } else if micExists {
            try? fm.moveItem(at: micURL, to: fileURL)
        } else if sysExists {
            try? fm.moveItem(at: sysURL, to: fileURL)
        }

        // Clean up temp files
        try? fm.removeItem(at: micURL)
        try? fm.removeItem(at: sysURL)
    }

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
        if sysConverter == nil || sysConverter?.inputFormat != buffer.format {
            sysConverter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter = sysConverter else { return nil }

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
