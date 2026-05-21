# Whisper Live Transcript — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SFSpeechRecognizer-based live transcript with periodic `whisper-cli --vad` calls. Implements spec at `docs/superpowers/specs/2026-05-21-whisper-live-transcript-design.md`.

**Architecture (recap):** A `LiveTranscriber` (`@MainActor` ObservableObject) accumulates mic + system audio buffers, flushes every 5s to temp WAVs, runs `whisper-cli --vad` per slice, publishes `[LiveTranscriptChunk]` to UI. SFSpeechRecognizer code path deleted entirely; speech-recognition permission dropped.

**Build invariant:** Each task ends with a passing `swift build -c debug`.

---

### Task 1: Add `speaker` field to LiveTranscriptChunk

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriptChunk.swift`

- [ ] **Step 1: Replace the file with this content**

```swift
import Foundation

/// One finalized whisper-transcribed audio segment from a live recording.
/// Produced by `LiveTranscriber` every ~5s for each captured source.
struct LiveTranscriptChunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Seconds since recording start when this chunk's audio began.
    let startTime: TimeInterval
    /// Seconds since recording start when this chunk's audio ended.
    let endTime: TimeInterval
    /// "Me" for mic audio, "Others" for system audio, "" for unknown.
    let speaker: String

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speaker: String = ""
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/scottyang/Developer/meeting-scribe/apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe
git add apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriptChunk.swift
git commit -m "feat(live): add speaker field to LiveTranscriptChunk"
```

---

### Task 2: Add new types — error, job, transcriber

**Files (create all three):**
- Create: `apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriberError.swift`
- Create: `apps/macos/MeetingScribe/Sources/Transcription/WhisperLiveJob.swift`
- Create: `apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriber.swift`

- [ ] **Step 1: LiveTranscriberError.swift**

```swift
import Foundation

enum LiveTranscriberError: Error, LocalizedError {
    case whisperMissing
    case vadModelMissing
    case processFailed(String)
    case jsonParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperMissing:
            return "whisper-cli not found. Install via Settings → Setup."
        case .vadModelMissing:
            return "silero-vad.onnx not found alongside whisper. Live transcript falling back to non-VAD."
        case .processFailed(let stderr):
            return "whisper-cli failed: \(stderr)"
        case .jsonParseFailed(let detail):
            return "Failed to parse whisper output: \(detail)"
        }
    }
}
```

- [ ] **Step 2: WhisperLiveJob.swift**

```swift
import Foundation

/// One whisper invocation against a slice WAV. Pure: takes paths in, returns
/// chunks. Caller is responsible for serializing invocations and deleting
/// the slice file after success/failure.
enum WhisperLiveJob {
    /// Runs whisper-cli against `sliceURL`. Segments returned have their
    /// timestamps offset by `sliceStartOffset` (seconds since recording start),
    /// so the caller doesn't have to do bookkeeping.
    static func run(
        whisperBinary: String,
        vadModel: String?,
        sliceURL: URL,
        sliceStartOffset: TimeInterval,
        speaker: String
    ) async throws -> [LiveTranscriptChunk] {
        let tempJSONBase = sliceURL.deletingPathExtension().path
        var args: [String] = [
            "-f", sliceURL.path,
            "-oj", "-np",
            "-of", tempJSONBase,
            "-l", "en",
            "-t", "4",
        ]
        if let vadModel {
            args += ["--vad", "--vad-model", vadModel]
        }

        // Find an installed model. WhisperPostProcessor's `findModel()` does the
        // same search; we duplicate it here to keep the job self-contained.
        guard let modelPath = findModel() else {
            throw LiveTranscriberError.processFailed("No whisper model found in known paths")
        }
        args += ["-m", modelPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperBinary)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // discard

        do {
            try process.run()
        } catch {
            throw LiveTranscriberError.processFailed("Failed to launch: \(error.localizedDescription)")
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw LiveTranscriberError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let jsonURL = URL(fileURLWithPath: tempJSONBase + ".json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: jsonURL)
        } catch {
            throw LiveTranscriberError.jsonParseFailed("Output JSON not found at \(jsonURL.path)")
        }

        return try parseSegments(
            jsonData: jsonData,
            sliceStartOffset: sliceStartOffset,
            speaker: speaker
        )
    }

    /// Parses whisper-cli's `-oj` JSON output into chunks. Each segment in
    /// the JSON's `transcription` array has `offsets.from`/`offsets.to`
    /// in milliseconds (relative to slice start). We add `sliceStartOffset`
    /// to map them back to seconds-since-recording-start.
    static func parseSegments(
        jsonData: Data,
        sliceStartOffset: TimeInterval,
        speaker: String
    ) throws -> [LiveTranscriptChunk] {
        struct Root: Decodable {
            let transcription: [Segment]
        }
        struct Segment: Decodable {
            let text: String
            let offsets: Offsets
        }
        struct Offsets: Decodable {
            let from: Int
            let to: Int
        }

        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: jsonData)
        } catch {
            throw LiveTranscriberError.jsonParseFailed(error.localizedDescription)
        }

        return root.transcription.compactMap { seg in
            let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return LiveTranscriptChunk(
                text: trimmed,
                startTime: sliceStartOffset + Double(seg.offsets.from) / 1000.0,
                endTime: sliceStartOffset + Double(seg.offsets.to) / 1000.0,
                speaker: speaker
            )
        }
    }

    private static func findModel() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let modelDirs = [
            "\(home)/.local/share/whisper-cpp",
            "/opt/homebrew/share/whisper-cpp",
            "/usr/local/share/whisper-cpp",
        ]
        let modelNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-base.bin",
        ]
        for dir in modelDirs {
            for name in modelNames {
                let path = "\(dir)/\(name)"
                if fm.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }
}
```

- [ ] **Step 3: LiveTranscriber.swift**

```swift
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
```

- [ ] **Step 4: Build + commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe/apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -3
cd /Users/scottyang/Developer/meeting-scribe
git add apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriberError.swift \
        apps/macos/MeetingScribe/Sources/Transcription/WhisperLiveJob.swift \
        apps/macos/MeetingScribe/Sources/Transcription/LiveTranscriber.swift
git commit -m "feat(live): LiveTranscriber + WhisperLiveJob scaffolding"
```

---

### Task 3: Swap AppState + UI consumers from TranscriptionManager → LiveTranscriber

**Files (one atomic commit):**
- Modify: `apps/macos/MeetingScribe/Sources/Models/AppState.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/Recording/LiveTranscriptPane.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/Recording/RecordingWorkspace.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/MenuBarView.swift` (line 385-386 only)
- Modify: `apps/macos/MeetingScribe/Sources/Views/Dashboard/RecordingModeView.swift` (line 146 only)

Per spec § "What gets removed": deletes the 60s timer, `enableLiveTranscriptTemporarily()`, `disableLiveTranscript()`, `toggleLiveTranscriptCheck()`, and routes audio callbacks to the new transcriber.

- [ ] **Step 1: AppState.swift edits**

Apply these edits:

**a.** Replace the property declaration at AppState.swift:54 (`let transcriptionManager = TranscriptionManager()`) with:
```swift
let liveTranscriber = LiveTranscriber()
```

**b.** Replace `private var liveTranscriptTimer: Timer?` (around line 41) — DELETE the line entirely.

**c.** Default flip: Replace `@AppStorage("liveTranscriptEnabled") var liveTranscriptEnabled = false` (line 36) with:
```swift
@AppStorage("liveTranscriptEnabled") var liveTranscriptEnabled = true
```
Also delete the multi-line comment block above it (the `// Live transcription (SFSpeechRecognizer)...` block, lines ~30-35). Replace with a single short comment:
```swift
// Defaults to true. Toggled in Settings → Setup. Read at recording start;
// runtime toggle via toggleLiveTranscript() also supported.
```

**d.** Replace the body of `toggleLiveTranscript()` (lines ~99-120) with:
```swift
func toggleLiveTranscript() {
    liveTranscriptEnabled.toggle()
    guard isRecording else { return }
    if liveTranscriptEnabled {
        liveTranscriber.start()
        liveTranscriptActive = liveTranscriber.isAvailable
        liveTranscriptError = liveTranscriber.lastError
    } else {
        liveTranscriber.stop()
        liveTranscriptActive = false
        liveTranscriptError = nil
    }
}
```

**e.** Delete `enableLiveTranscriptTemporarily()` (lines ~122-134), `disableLiveTranscript()` (~136-141), and `toggleLiveTranscriptCheck()` (~88-94) — all three are gone.

**f.** Replace the body of `openLiveChatPanel()` (lines ~143-170) with:
```swift
func openLiveChatPanel() {
    showLiveChatPanel = true
    // No timer to cancel anymore. Live transcript runs the full recording
    // when liveTranscriptEnabled. If it isn't running and the user wants
    // it now, they can flip it from the recording top bar.
    guard liveTranscriptEnabled, isRecording, !liveTranscriber.isAvailable == false else { return }
    if !liveTranscriptActive {
        liveTranscriber.start()
        liveTranscriptActive = liveTranscriber.isAvailable
        liveTranscriptError = liveTranscriber.lastError
    }
}
```

**g.** Replace `closeLiveChatPanel()` (lines ~172-178) with:
```swift
func closeLiveChatPanel() {
    showLiveChatPanel = false
    // Live transcript continues running; no timer to rearm anymore.
}
```

**h.** In `doStartRecording()` (lines ~180-208), replace the `if liveTranscriptEnabled { … } else { … }` block + the `let transcriber = transcriptionManager` line with:
```swift
if liveTranscriptEnabled {
    liveTranscriber.start()
    liveTranscriptActive = liveTranscriber.isAvailable
    liveTranscriptError = liveTranscriber.lastError
} else {
    liveTranscriptActive = false
    liveTranscriptError = nil
}
```
(Drop the `let transcriber = transcriptionManager` capture — we'll reference `self?.liveTranscriber` from the callbacks via the weak-self pattern.)

**i.** Replace the `audioCaptureManager.onMicAudio = { ... }` closure body's transcription line. Find:
```swift
Task { @MainActor in
    self?.audioLevel = capturedLevel
    if self?.liveTranscriptActive == true {
        transcriber.processAudioBuffer(buffer, speaker: "Local")
    }
}
```
Replace with:
```swift
Task { @MainActor in
    guard let self = self else { return }
    self.audioLevel = capturedLevel
    if self.liveTranscriptActive, let format = self.audioCaptureManager.micFormat {
        self.liveTranscriber.appendMic(buffer, format: format)
    }
}
```

**j.** Replace `audioCaptureManager.onSystemAudio` closure. Currently:
```swift
audioCaptureManager.onSystemAudio = { [weak self] sampleBuffer in
    nonisolated(unsafe) let sampleBuffer = sampleBuffer
    writer.writeSystemAudio(sampleBuffer: sampleBuffer)
    Task { @MainActor in
        if self?.liveTranscriptActive == true {
            transcriber.processSampleBuffer(sampleBuffer, speaker: "Remote")
        }
    }
}
```
Replace with:
```swift
audioCaptureManager.onSystemAudio = { [weak self] sampleBuffer in
    nonisolated(unsafe) let sampleBuffer = sampleBuffer
    writer.writeSystemAudio(sampleBuffer: sampleBuffer)
    Task { @MainActor in
        guard let self = self, self.liveTranscriptActive else { return }
        if let pcm = Self.pcmBuffer(from: sampleBuffer) {
            self.liveTranscriber.appendSystem(pcm.buffer, format: pcm.format)
        }
    }
}
```

**k.** Add at the bottom of `AppState` (above the closing brace), a static helper for converting CMSampleBuffer → (AVAudioPCMBuffer, AVAudioFormat):
```swift
private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> (buffer: AVAudioPCMBuffer, format: AVAudioFormat)? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return nil }
    var asbdMutable = asbd
    guard let format = AVAudioFormat(streamDescription: &asbdMutable) else { return nil }

    let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
    buffer.frameLength = frameCount

    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
    var lengthAtOffset: Int = 0
    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let err = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
    guard err == kCMBlockBufferNoErr, let dataPointer else { return nil }

    let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
    let copyBytes = min(totalLength, Int(frameCount) * bytesPerFrame)

    if let floatChannelData = buffer.floatChannelData {
        memcpy(floatChannelData[0], dataPointer, copyBytes)
    } else if let int16ChannelData = buffer.int16ChannelData {
        memcpy(int16ChannelData[0], dataPointer, copyBytes)
    } else {
        return nil
    }
    return (buffer, format)
}
```

Also add at the top of the file (above the `class AppState`):
```swift
import AVFoundation
import CoreMedia
```
(Only add if not already imported.)

**l.** In `doStopRecording()` (lines ~287-364), replace `transcriptionManager.reset()` (line 332) with `liveTranscriber.stop()`. Also delete `liveTranscriptTimer?.invalidate()` and `liveTranscriptTimer = nil` (lines 321-322) — those were already deleted at step (b) but double-check.

**m.** Search the rest of the file for any remaining `transcriptionManager.` references and remove them (there should be none after the above edits).

- [ ] **Step 2: LiveTranscriptPane.swift — point at LiveTranscriber, drop currentSessionText**

Replace the entire file with:
```swift
import SwiftUI

/// Read-only pane that renders the live transcript as a scrolling list of
/// finalized whisper-transcribed chunks. Each chunk is clickable to insert
/// a timestamp into the notes editor.
struct LiveTranscriptPane: View {
    @ObservedObject var liveTranscriber: LiveTranscriber
    let liveTranscriptError: String?
    let onChunkClick: (LiveTranscriptChunk) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 320)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = liveTranscriptError {
            errorView(error)
        } else if liveTranscriber.liveChunks.isEmpty {
            listeningView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(liveTranscriber.liveChunks) { chunk in
                            chunkRow(chunk: chunk).id(chunk.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: liveTranscriber.liveChunks.count) { _, _ in
                    if let last = liveTranscriber.liveChunks.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func chunkRow(chunk: LiveTranscriptChunk) -> some View {
        Button {
            onChunkClick(chunk)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TimestampFormatter.format(chunk.startTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 36, alignment: .trailing)
                if !chunk.speaker.isEmpty {
                    Text(chunk.speaker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chunk.speaker == "Me" ? .blue : .purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill((chunk.speaker == "Me" ? Color.blue : Color.purple).opacity(0.15))
                        )
                }
                Text(chunk.text)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to insert [\(TimestampFormatter.format(chunk.startTime))] into notes")
    }

    private var listeningView: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "ear")
                    .foregroundStyle(.tertiary)
                Text("Listening… whisper transcribes every 5 seconds while you record.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Live transcript unavailable", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Recording continues; full transcript will appear after stop.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
```

- [ ] **Step 3: RecordingWorkspace.swift — pass liveTranscriber instead**

At line 23-25, find:
```swift
LiveTranscriptPane(
    transcriptionManager: appState.transcriptionManager,
    ...
)
```
Replace `transcriptionManager: appState.transcriptionManager,` with `liveTranscriber: appState.liveTranscriber,`.

- [ ] **Step 4: MenuBarView.swift lines 385-386**

Find:
```swift
if !appState.transcriptionManager.liveText.isEmpty {
    Text(appState.transcriptionManager.liveText)
```
Replace with:
```swift
if !appState.liveTranscriber.liveText.isEmpty {
    Text(appState.liveTranscriber.liveText)
```

- [ ] **Step 5: RecordingModeView.swift line 146**

Find:
```swift
let rawTranscript = appState.transcriptionManager.liveText
```
Replace with:
```swift
let rawTranscript = appState.liveTranscriber.liveText
```

- [ ] **Step 6: Build + commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe/apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -10
```
Expected: `Build complete!`. If errors, fix them iteratively before committing.

```bash
cd /Users/scottyang/Developer/meeting-scribe
git add apps/macos/MeetingScribe/Sources/Models/AppState.swift \
        apps/macos/MeetingScribe/Sources/Views/Recording/LiveTranscriptPane.swift \
        apps/macos/MeetingScribe/Sources/Views/Recording/RecordingWorkspace.swift \
        apps/macos/MeetingScribe/Sources/Views/MenuBarView.swift \
        apps/macos/MeetingScribe/Sources/Views/Dashboard/RecordingModeView.swift
git commit -m "feat(live): swap SFSpeechRecognizer for whisper-based LiveTranscriber"
```

---

### Task 4: Remove speech-recognition permission

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/Permissions/PermissionsManager.swift`
- Modify: `apps/macos/MeetingScribe/Sources/Views/Welcome/WelcomeView.swift`
- Modify: `apps/macos/MeetingScribe/Info.plist`

- [ ] **Step 1: PermissionsManager.swift**

Remove these from the enum (line 10) and all switch cases that reference `.speechRecognition`:
- `case speechRecognition` (line 10)
- The `case .speechRecognition: return "Speech Recognition"` in `title` (line 17)
- The `case .speechRecognition: return "Required for live transcript. ..."` in `subtitle` (lines 27-28)
- Update `isRequired` to remove `.speechRecognition` from the `case .speechRecognition, .calendar, .screenRecording: return false` (line 39) → becomes `case .calendar, .screenRecording: return false`
- The `case .speechRecognition: return "text.bubble.fill"` in `symbolName` (line 46)

In `refreshAll()` (lines 83-90), delete:
```swift
next[.speechRecognition] = currentSpeechStatus()
```

In `request(_:)` (lines 92-119), delete the entire `case .speechRecognition:` block (lines 97-104):
```swift
case .speechRecognition:
    let status = await withCheckedContinuation { ... }
    statuses[kind] = mapSpeech(status)
```

Delete `currentSpeechStatus()` (lines 132-134), `mapSpeech(_:)` (lines 159-166).

Remove `import Speech` from line 3 — it's no longer needed.

- [ ] **Step 2: WelcomeView.swift**

In `openSystemSettings(for:)` (around lines 117-129), the switch covers `PermissionKind.allCases`. Remove the `case .speechRecognition:` block. The switch will only have microphone/calendar/screenRecording cases.

If the compiler complains about non-exhaustive switch, that's fine — just delete that case.

- [ ] **Step 3: Info.plist**

Delete these two lines from `apps/macos/MeetingScribe/Info.plist`:
```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>MeetingScribe runs on-device speech recognition for the live preview.</string>
```

- [ ] **Step 4: Build + commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe/apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -5
```

```bash
cd /Users/scottyang/Developer/meeting-scribe
git add apps/macos/MeetingScribe/Sources/Permissions/PermissionsManager.swift \
        apps/macos/MeetingScribe/Sources/Views/Welcome/WelcomeView.swift \
        apps/macos/MeetingScribe/Info.plist
git commit -m "chore(live): drop speech-recognition permission and Speech imports"
```

---

### Task 5: Delete dead code

**Files:**
- Delete: `apps/macos/MeetingScribe/Sources/Transcription/TranscriptionManager.swift`
- Delete: `apps/macos/MeetingScribe/Sources/Transcription/SpeechAuthHelper.swift`

- [ ] **Step 1: Delete + build + commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe
git rm apps/macos/MeetingScribe/Sources/Transcription/TranscriptionManager.swift \
       apps/macos/MeetingScribe/Sources/Transcription/SpeechAuthHelper.swift
cd apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -5
cd /Users/scottyang/Developer/meeting-scribe
git commit -m "chore(live): delete TranscriptionManager and SpeechAuthHelper"
```

If build fails, there's a stray reference somewhere — find and fix before committing.

---

### Task 6: Update SetupView toggle description

**Files:**
- Modify: `apps/macos/MeetingScribe/Sources/Views/Settings/SetupView.swift`

- [ ] **Step 1: Replace toggle description text**

In SetupView.swift, find:
```swift
Toggle(isOn: $liveTranscriptEnabled) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Live transcription during recording")
        Text("Runs Apple's on-device speech recognizer while you record so the live Q&A panel has context. Costs ~1 CPU core. Off by default — whisper-cpp runs when recording stops either way.")
            ...
```
Replace the inner Text content with:
```swift
Text("Live transcription during recording")
Text("Whisper transcribes ~5s slices of mic + system audio while you record. On by default. Costs ~10-20% of one CPU core, intermittently. The final post-recording transcription still runs at stop.")
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/scottyang/Developer/meeting-scribe/apps/macos/MeetingScribe && swift build -c debug 2>&1 | tail -3
cd /Users/scottyang/Developer/meeting-scribe
git add apps/macos/MeetingScribe/Sources/Views/Settings/SetupView.swift
git commit -m "docs(setup): update live-transcript toggle description for whisper"
```

---

### Task 7: Rebuild DMG + manual verification

- [ ] **Step 1: Build release DMG**

```bash
cd /Users/scottyang/Developer/meeting-scribe
rm -f dist/MeetingScribe-*.dmg
VERSION=v0.1.0-rc3 bash scripts/release.sh 2>&1 | tail -10
```

- [ ] **Step 2: Install + smoke test**

Manual steps (subagent reports steps performed but cannot do final UI smoke):
1. `rm -rf /Applications/MeetingScribe.app`
2. `open dist/MeetingScribe-0.1.0-rc3.dmg`
3. Drag to /Applications
4. Right-click → Open
5. Walk Welcome flow (notice: no speech-recognition card)
6. Click "Get Started" / "Continue"
7. Click "Start Session" — record 30s while talking
8. Observe live transcript pane updates every ~5s with chunks
9. Click "Stop"
10. Verify post-recording whisper still produces the full transcript

Manual verification is on the user; the subagent's job is to ensure the DMG builds and ships.

---

## Self-Review

- **Coverage:** Every spec section maps to a task.
- **Build invariant:** Each task ends with `swift build -c debug` clean.
- **Order:** Adds new code first (Tasks 1-2), swaps wiring (Task 3), then cleans up (Tasks 4-6). Build never breaks mid-task.
- **Placeholders:** None.
