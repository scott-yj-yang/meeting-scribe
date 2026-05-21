# Whisper-based Live Transcript — Design

## Problem

The current live transcript uses `SFSpeechRecognizer`. It is unreliable (locale-limited, glitchy mid-session, opaque failures), hardcoded to disable after 60s to keep its CPU cost bounded, and a meaningfully worse experience than the post-recording whisper transcription. Users have a whisper install path baked into the Welcome flow now — we should use whisper for the live preview too.

## Goal

Replace `SFSpeechRecognizer`-driven live transcript with periodic chunked calls to `whisper-cli --vad --vad-model silero-vad.onnx`. Keep the existing `LiveTranscriptChunk` model and `LiveTranscriptPane` UI; replace only the source.

## Non-goals

- Sub-second latency. Cadence is 5s tick.
- In-flight partial results. Whisper outputs are atomic; we only render finalized segments.
- Embedding `whisper.cpp` as a Swift library. We continue to shell out.
- Replacing the post-recording whisper pass. That stays as-is.

## Approach

**Periodic in-memory audio slicing → `whisper-cli --vad` per slice.**

Audio is already captured to disk via `AudioFileWriter` during recording. In parallel, a new `LiveTranscriber` accumulates the same PCM buffers in two in-memory rings (mic + system). Every 5 seconds, each ring is flushed to a small temp `.wav`, queued, and dispatched to `whisper-cli`. The resulting JSON segments become `LiveTranscriptChunk`s labeled `"Me"` (mic) or `"Others"` (system) with timestamps offset by slice start.

## Architecture

```
                 ┌──────────────────────────┐
                 │  AudioCaptureManager     │  (existing)
                 │   onMicAudio    ─┐       │
                 │   onSystemAudio ─┐       │
                 └───────┬──────────┴─┬─────┘
                         │            │
                         ├─→  AudioFileWriter (existing, unchanged)
                         │            │
                         ▼            ▼
                 ┌──────────────────────────┐
                 │  LiveTranscriber          │  ← @MainActor ObservableObject
                 │                           │
                 │  ringBufferMic: [PCMBuf]  │
                 │  ringBufferSys: [PCMBuf]  │
                 │                           │
                 │  tickTask (every 5s)     │
                 │   → write WAV slices     │
                 │   → enqueue WhisperJob   │
                 │                           │
                 │  jobQueue (single Task)  │
                 │   → run whisper-cli      │
                 │   → parse segments       │
                 │   → append liveChunks    │
                 │                           │
                 │  @Published var          │
                 │    liveChunks            │
                 └──────────────────────────┘
                              │
                              ▼
                 ┌──────────────────────────┐
                 │  LiveTranscriptPane      │  (existing — minor UI tweak)
                 └──────────────────────────┘
```

## Components

| Type | File | Responsibility |
|---|---|---|
| `LiveTranscriberError` | `Sources/Transcription/LiveTranscriberError.swift` | Typed errors: `whisperMissing`, `vadModelMissing`, `processFailed(stderr)`, `jsonParseFailed` |
| `WhisperLiveJob` | `Sources/Transcription/WhisperLiveJob.swift` | Pure async function: takes slice path + format + speaker + slice-start-offset, runs `whisper-cli`, parses JSON segments, returns `[LiveTranscriptChunk]`. Caller responsible for serializing invocations. |
| `LiveTranscriber` | `Sources/Transcription/LiveTranscriber.swift` | `@MainActor` `ObservableObject`. Owns ring buffers, tick timer, FIFO queue with bounded backlog, and the `@Published var liveChunks: [LiveTranscriptChunk]`. |
| `LiveTranscriptChunk` | (existing) | Add `speaker: String` field (default `""`). |
| (deleted) `TranscriptionManager.swift` | | SFSpeechRecognizer wrapper |
| (deleted) `SpeechAuthHelper.swift` | | Permission helper |

## Data flow

1. Recording starts → `AppState.doStartRecording` calls `liveTranscriber.start(captureMode:)`. Start time captured.
2. `audioCaptureManager.onMicAudio(buffer, time)` → `liveTranscriber.appendMic(buffer)`. (Audio file write unchanged.)
3. `audioCaptureManager.onSystemAudio(sampleBuffer)` → convert to PCMBuffer → `liveTranscriber.appendSystem(buffer)`.
4. Every 5s, `LiveTranscriber.tick()`:
   - Atomically swap ring buffers with empty replacements.
   - For each non-empty buffer: write to `NSTemporaryDirectory()/live-<uuid>.wav` via `AVAudioFile`, enqueue `WhisperJob(path, speaker, sliceStartOffset)`.
   - Trim per-speaker pending jobs to max 2 (drop oldest).
5. Single consumer task: pops next `WhisperJob`, runs `whisper-cli --vad --vad-model <silero> -oj -np -f <slice>`, parses JSON segments, maps each to `LiveTranscriptChunk` with corrected timestamps, appends to `@Published liveChunks` on `@MainActor`. Deletes the temp `.wav`.
6. Recording stops → `liveTranscriber.stop()`. Cancels tickTask, terminates in-flight process, drains queue, removes temp files.

## Audio format

Mic + system buffers come in at the device's native format (typically 48kHz). We write the slice WAVs at the buffer's native format via `AVAudioFile`. `whisper-cli` resamples internally to 16kHz mono. We do not pre-resample in-app.

## Bounded backlog

- Per-speaker queue depth ≤ 2. On enqueue, if `pendingJobs.filter { $0.speaker == newJob.speaker }.count >= 2`, drop the oldest matching pending job (do not interrupt in-flight).
- A single whisper Process at a time across BOTH sources. The pending queue is shared FIFO. The consumer task processes one job to completion before the next.

## Defaults & settings

- `@AppStorage("liveTranscriptEnabled")` — **default flips from `false` to `true`**. Whisper has no SFSpeechRecognizer-style CPU burn, so we enable by default.
- Tick interval is a hardcoded constant `5.0` (TimeInterval). No setting in v1.
- The `SetupView` toggle's description updates from SFSpeechRecognizer-focused copy to whisper-focused copy.

## Failure modes

| Symptom | Behavior |
|---|---|
| `whisper-cli` not on PATH at recording start | `start()` throws `.whisperMissing`. AppState catches, sets `liveTranscriptError = "Install whisper-cpp from Settings → Setup"`. Recording proceeds (audio capture + post-recording whisper still work). |
| `silero-vad.onnx` not at any known path | `WhisperLiveJob` falls back to `whisper-cli` without `--vad`. Logs the fallback once per session. |
| `whisper-cli` exits non-zero on a slice | Log stderr, skip the slice. Live transcript loses that chunk but the run continues. |
| User stops recording mid-job | `stop()` calls `process.terminate()`, drains queue, removes temp files. |
| Ring buffer overflows during a tick lag | Memory bound is ~640KB per source for one tick worth; >2 tick lags = ~2MB. Hard cap at 30 seconds of audio per source — older buffers dropped silently. |
| `LiveTranscriptPane` opened before recording starts | Pane shows existing empty state. No change. |

## Permission removal

- Drop `PermissionKind.speechRecognition` from the enum.
- Remove the speech-recognition card from `WelcomeView`.
- Remove the corresponding switch case in `openSystemSettings(for:)`.
- `Info.plist` `NSSpeechRecognitionUsageDescription` can stay (harmless) or be removed (cleaner). Remove it.

## UI changes

- `LiveTranscriptPane` consumes `appState.liveTranscriber.liveChunks` instead of `appState.transcriptionManager.liveChunks`.
- Remove the "in-flight" trailing chunk rendering (`currentSessionText`) — whisper outputs are atomic.
- Optional: render speaker label next to each chunk (e.g., a small "Me"/"Others" badge). Out of scope for v1; the field is populated but UI rendering of it is deferred.

## Testing

- **Unit:** `WhisperLiveJob.parseSegments(jsonData:)` — feed sample whisper-cli JSON output (canned fixture), verify `[LiveTranscriptChunk]` includes correct text + start/end times + speaker.
- **Unit:** `LiveTranscriber` backlog policy — synthetic enqueue calls, verify drop-oldest behavior at threshold.
- **Manual:** Record a 60-second meeting with mic + system audio active (e.g., play a podcast through speakers, talk over it). Verify live transcript pane updates every ~5s with both `"Me"` and `"Others"` chunks accumulating. Verify no 60s timeout — recording at 90s still produces chunks. Stop recording — verify no leaked temp files in `NSTemporaryDirectory()`.
- **Manual:** Disable whisper-cli (`mv /opt/homebrew/bin/whisper-cli /tmp/`). Start recording. Verify graceful error in pane, recording still completes, post-recording whisper fails but cleanly.

## What we explicitly are NOT doing

- Not using `/opt/homebrew/bin/whisper-stream` (uncertain integration, marginal benefit).
- Not embedding `whisper.cpp` as a Swift library (huge effort).
- Not showing in-flight partial results.
- Not pre-resampling audio in-app (whisper resamples).
- Not adding a user-configurable tick interval setting (hardcoded 5s; can add later if requested).

## Open risk

`whisper-cli` start-up overhead (~200-500ms for model load on cold start, faster after FS cache) compounds every tick. On M1 we expect 5s slice → ~0.5s whisper time including load, leaving 4s headroom. On older Macs (M1 Air, etc.) it may approach the tick interval. **Mitigation if needed (NOT in v1):** keep a long-running `whisper-cli` process via `whisper-server` or `whisper-stream`. Defer until/unless we see real backlog.
