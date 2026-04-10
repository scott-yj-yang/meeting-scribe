# MeetingScribe

A self-hosted, privacy-first meeting transcription and summary system for macOS. Records system audio + microphone, transcribes on-device with whisper.cpp, and summarizes with Claude Code or a local LLM. Everything runs locally — no cloud services required.

## Features

### macOS Menu Bar App
- **One-click recording** from the menu bar with system audio + microphone capture
- **Live transcription preview** (first 60 seconds) to confirm audio is working
- **Calendar integration** — auto-suggests meeting titles from your calendar events
- **Meeting type tags** — 1:1, Subgroup, Lab Meeting, Casual, Standup
- **Notes** — jot down notes before/during meetings, saved alongside the transcript
- **On-device transcription** via whisper.cpp — fully offline
- **Organized file storage** — `~/MeetingScribe/2026/03-March/25-sprint-planning/`
- **Post-recording panel** — open files in Finder, view summary, delete, start new session
- **Summarization** — Claude Code CLI (default) or local Ollama, selectable in Settings
- **Configurable** — mic selection, output directory, summarization provider

### CLI (`meetingctl`)
- `meetingctl list` — list all meetings from `~/MeetingScribe`

## Architecture

```
┌──────────────────────────────────────────────┐
│   macOS App (MenuBarExtra + Window)          │
│   Swift 6 / SwiftUI                          │
│                                              │
│   ScreenCaptureKit (system audio)            │
│   AVAudioEngine (mic)                        │
│   SFSpeechRecognizer (live preview)          │
│   whisper.cpp (final transcription)          │
│   Claude Code CLI / Ollama (summarization)   │
└──────────────────────────────────────────────┘
                      │
                      ▼
            ~/MeetingScribe/
            (local markdown + audio + metadata)
                      │
                      ▼
              meetingctl list
              (optional CLI)
```

**Recording flow:**
1. Click "Start Session" → captures mic + system audio to separate temp files
2. Live transcript shows in the app (SFSpeechRecognizer, auto-disables after 60s)
3. Click "Stop" → ffmpeg merges audio streams with alignment correction
4. whisper.cpp transcribes the merged audio on-device (with progress bar + ETA)
5. Transcript saved locally as markdown under `~/MeetingScribe/YYYY/MM-Month/DD-slug/`
6. Summarize with Claude Code or Ollama, right from the meeting panel

## Setup

### Requirements
- macOS 15 (Sequoia) or newer
- whisper.cpp: `brew install whisper-cpp`
- A whisper model, e.g. `ggml-base.en.bin` (see `scripts/download-model.sh`)

### Optional: summarization
Choose one:

- **Claude CLI** (default): `npm install -g @anthropic-ai/claude-code`
- **Ollama** (local, no API key): `./scripts/install-ollama.sh`

### Build and run the Swift app
```bash
cd apps/macos/MeetingScribe
./build-app.sh debug
open .build/arm64-apple-macosx/debug/MeetingScribe.app
```

(On Intel Macs the `.app` path uses `x86_64-apple-macosx`.)

Press `Cmd-,` in the app to open Settings and pick your summarization provider.

### CLI (optional)
```bash
cd cli
npm install
npx tsx bin/meetingctl.ts list
```

### Permissions

On first launch, macOS will ask for:
- **Microphone** — to record your voice
- **Screen & System Audio Recording** — to capture audio from Zoom/Meet/Teams
- **Speech Recognition** — for live transcript preview
- **Calendar** — to suggest meeting titles from your calendar events

## Configuration

### App Settings
Press `Cmd-,` in the app to open Settings:
- **Summarization provider** — Claude Code CLI or Ollama
- **Output Directory** — where files are saved (default: `~/MeetingScribe`)
- **Microphone** — select which mic to use
- **Save raw audio** — keep `.wav` files for re-transcription

### Prompt Templates
Customize how meetings are summarized by editing files in `prompts/`:
- `summarize.md` — main summary template (executive summary, action items, decisions)
- `action-items.md` — action item extraction only
- `custom/` — add your own templates

## File Structure

### Local Storage
Meetings are organized by date:
```
~/MeetingScribe/
  2026/
    03-March/
      25-sprint-planning/
        audio.wav         # Merged mic + system audio
        transcript.md     # Whisper transcription
        metadata.json     # Title, date, duration
        notes.md          # Your meeting notes
        summary.md        # Claude / Ollama summary (if generated)
```

### Project Structure
```
meeting-scribe/
  apps/
    macos/MeetingScribe/  # Swift Package — menu bar + window app
  cli/                    # meetingctl — Node.js CLI (list only)
  prompts/                # Summarization templates
  scripts/
    install-ollama.sh     # Install local Ollama for summarization
    build-app.sh          # Build MeetingScribe.app
    transcribe.sh         # Standalone transcription script
    record.sh             # Record + transcribe from terminal
```

## Usage

### Recording a Meeting
1. Open the app and click the menu bar icon
2. (Optional) Type a meeting title or click "Use" on a calendar event
3. (Optional) Select a meeting type tag
4. Click "Start Session"
5. The live transcript shows for 60 seconds to confirm audio works
6. When done, click "Stop" — whisper.cpp transcribes with a progress bar
7. Review the transcript, open files in Finder, or summarize with one click

### Managing Meetings
- **App window**: browse recent recordings and open their summary panels
- **CLI**: `meetingctl list` — view all meetings from the terminal
- **Finder**: everything lives under `~/MeetingScribe/`

### Summarizing
- From the meeting panel, click "Summarize" — uses your configured provider (Claude CLI or Ollama)
- Customize templates in `prompts/` to focus on decisions, action items, or your own format

## Tech Stack

| Component | Technology |
|-----------|-----------|
| App | Swift 6, SwiftUI, MenuBarExtra, ScreenCaptureKit, AVAudioEngine, SFSpeechRecognizer |
| Transcription | whisper.cpp (on-device) |
| Summarization | Claude Code CLI or local Ollama |
| CLI | Node.js, Commander, TypeScript |
| Audio Processing | ffmpeg (stream merging, normalization) |

## Privacy

- All audio recording and transcription happens **on-device**
- No audio is sent to any cloud service
- Meetings are stored locally under `~/MeetingScribe/`
- With Ollama, summarization is fully local too
- With Claude CLI, only the transcript text is sent to Anthropic via your own API key

## License

MIT
