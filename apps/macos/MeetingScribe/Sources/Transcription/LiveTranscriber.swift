import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class LiveTranscriber: ObservableObject {
    @Published private(set) var liveChunks: [LiveTranscriptChunk] = []
    @Published private(set) var lastError: String? = nil

    /// Concatenated text of all chunks in order — convenience for callers
    /// that want the full running transcript as a single string (e.g. menu
    /// bar peek, chat-panel raw context).
    var liveText: String {
        liveChunks.map(\.text).joined(separator: " ")
    }

    private struct PendingJob {
        let sliceURL: URL
        let format: AVAudioFormat
        let speaker: String
        let sliceStartOffset: TimeInterval
        let buffers: [AVAudioPCMBuffer]
    }

    private let tickInterval: TimeInterval = 5.0
    private let maxPendingPerSpeaker = 2
    private let maxRingSeconds: TimeInterval = 30.0

    private var sessionStart: Date?
    private var tickTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?
    private var pendingJobs: [PendingJob] = []
    private var jobAvailable: CheckedContinuation<Void, Never>?
    private var inFlightProcess: Process?

    private var micBuffers: [AVAudioPCMBuffer] = []
    private var sysBuffers: [AVAudioPCMBuffer] = []
    private var micFormat: AVAudioFormat?
    private var sysFormat: AVAudioFormat?
    private var micLastSliceEnd: TimeInterval = 0
    private var sysLastSliceEnd: TimeInterval = 0

    private let whisperBinary: String
    private let vadModel: String?

    init() {
        self.whisperBinary = Self.findWhisperBinary()
        self.vadModel = Self.findVadModel()
    }

    /// True if a whisper binary was found at construction time.
    var isAvailable: Bool { !whisperBinary.isEmpty }

    func start() {
        guard isAvailable else {
            lastError = LiveTranscriberError.whisperMissing.localizedDescription
            return
        }
        liveChunks = []
        lastError = nil
        sessionStart = Date()
        micLastSliceEnd = 0
        sysLastSliceEnd = 0
        startTickTask()
        startConsumerTask()
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
        consumerTask?.cancel(); consumerTask = nil
        jobAvailable?.resume(); jobAvailable = nil
        inFlightProcess?.terminate(); inFlightProcess = nil
        for job in pendingJobs { try? FileManager.default.removeItem(at: job.sliceURL) }
        pendingJobs.removeAll()
        micBuffers.removeAll(); sysBuffers.removeAll()
        sessionStart = nil
    }

    func appendMic(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        if micFormat == nil { micFormat = format }
        micBuffers.append(buffer)
        trimRing(&micBuffers, format: format)
    }

    func appendSystem(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        if sysFormat == nil { sysFormat = format }
        sysBuffers.append(buffer)
        trimRing(&sysBuffers, format: format)
    }

    private func trimRing(_ buffers: inout [AVAudioPCMBuffer], format: AVAudioFormat) {
        var totalSeconds = 0.0
        for b in buffers {
            totalSeconds += Double(b.frameLength) / format.sampleRate
        }
        while totalSeconds > maxRingSeconds, !buffers.isEmpty {
            let dropped = buffers.removeFirst()
            totalSeconds -= Double(dropped.frameLength) / format.sampleRate
        }
    }

    private func startTickTask() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.tickInterval ?? 5.0))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    private func tick() {
        guard sessionStart != nil else { return }

        if let micFormat, !micBuffers.isEmpty {
            let slice = micBuffers
            micBuffers = []
            enqueueSlice(buffers: slice, format: micFormat, speaker: "Me", lastEnd: &micLastSliceEnd)
        }
        if let sysFormat, !sysBuffers.isEmpty {
            let slice = sysBuffers
            sysBuffers = []
            enqueueSlice(buffers: slice, format: sysFormat, speaker: "Others", lastEnd: &sysLastSliceEnd)
        }
    }

    private func enqueueSlice(
        buffers: [AVAudioPCMBuffer],
        format: AVAudioFormat,
        speaker: String,
        lastEnd: inout TimeInterval
    ) {
        let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard frames > 0 else { return }
        let sliceDuration = Double(frames) / format.sampleRate
        let sliceStart = lastEnd
        lastEnd = sliceStart + sliceDuration

        let sliceURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("live-\(UUID().uuidString).wav")
        guard writeWAV(buffers: buffers, format: format, to: sliceURL) else { return }

        pendingJobs.append(PendingJob(
            sliceURL: sliceURL,
            format: format,
            speaker: speaker,
            sliceStartOffset: sliceStart,
            buffers: buffers
        ))

        var sameSpeakerIndices = pendingJobs.indices.filter { pendingJobs[$0].speaker == speaker }
        while sameSpeakerIndices.count > maxPendingPerSpeaker {
            let dropIndex = sameSpeakerIndices.removeFirst()
            let dropped = pendingJobs.remove(at: dropIndex)
            try? FileManager.default.removeItem(at: dropped.sliceURL)
            sameSpeakerIndices = pendingJobs.indices.filter { pendingJobs[$0].speaker == speaker }
        }

        jobAvailable?.resume()
        jobAvailable = nil
    }

    private func writeWAV(
        buffers: [AVAudioPCMBuffer],
        format: AVAudioFormat,
        to url: URL
    ) -> Bool {
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            for buffer in buffers {
                try file.write(from: buffer)
            }
            return true
        } catch {
            print("[LiveTranscriber] writeWAV failed: \(error.localizedDescription)")
            return false
        }
    }

    private func startConsumerTask() {
        consumerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let job = await self?.waitForNextJob() else { return }
                await self?.runJob(job)
            }
        }
    }

    private func waitForNextJob() async -> PendingJob? {
        if let job = pendingJobs.first {
            pendingJobs.removeFirst()
            return job
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            jobAvailable = cont
        }
        if let job = pendingJobs.first {
            pendingJobs.removeFirst()
            return job
        }
        return nil
    }

    private func runJob(_ job: PendingJob) async {
        defer { try? FileManager.default.removeItem(at: job.sliceURL) }
        do {
            let chunks = try await WhisperLiveJob.run(
                whisperBinary: whisperBinary,
                vadModel: vadModel,
                sliceURL: job.sliceURL,
                sliceStartOffset: job.sliceStartOffset,
                speaker: job.speaker
            )
            liveChunks.append(contentsOf: chunks)
        } catch {
            print("[LiveTranscriber] job failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Discovery

    private static func findWhisperBinary() -> String {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cli",
            "\(NSHomeDirectory())/.local/bin/whisper-cli",
        ]
        return candidates.first(where: { fm.fileExists(atPath: $0) }) ?? ""
    }

    private static func findVadModel() -> String? {
        let fm = FileManager.default
        let dirs = [
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
            "\(NSHomeDirectory())/.local/share/whisper-cpp",
        ]
        for dir in dirs {
            let path = "\(dir)/silero-vad.onnx"
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }
}
