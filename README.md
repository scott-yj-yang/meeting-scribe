# MeetingScribe

A self-hosted, privacy-first meeting transcription and summary system for macOS. Records system audio + microphone, transcribes on-device with whisper.cpp, and summarizes with Claude Code or a local LLM. Everything runs locally — no cloud services required.

## Features

### macOS Menu Bar App
- **One-click recording** from the menu bar with system audio + microphone capture
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
│   ffmpeg (stream merging)                    │
│   whisper.cpp (transcription)                │
│   Claude Code / Ollama (summarization)       │
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
1. Click "Start Session" → the meeting folder is claimed and mic + system audio
   stream to separate temp files inside it
2. Take notes while it runs; renaming the meeting renames its folder to match
3. Click "Stop" → ffmpeg merges the audio streams with alignment correction
4. whisper.cpp transcribes the merged audio on-device (with progress bar + ETA)
5. Transcript saved locally as markdown under `~/MeetingScribe/YYYY/MM-Month/DD-slug/`
6. Click "Open in Claude Code" to summarize via `/summarize`, or run Ollama locally for an automatic summary

## Upgrading from the old web-app install

If you installed MeetingScribe before the native rewrite, it set up Postgres,
Next.js, and a tmux session. That version is preserved on the `legacy-main`
branch; the current app replaces all of it with a single `.app`. To migrate
cleanly:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/migrate.sh)"
```

This interactively removes the old web server, app bundle, CLI symlink,
update symlink, and Postgres DB. **Your recordings under
`~/MeetingScribe/` are preserved.**

After migration, install the new app via [GitHub Releases](https://github.com/scott-yj-yang/meeting-scribe/releases/latest)
once the DMG is published.

## Installing the DMG

Once a release is published, download the latest `MeetingScribe-X.Y.Z.dmg`
from [GitHub Releases](https://github.com/scott-yj-yang/meeting-scribe/releases/latest),
double-click to open, and drag **MeetingScribe.app** to your Applications folder.

**First launch (one-time per machine):** macOS will show
*"MeetingScribe.app cannot be opened because the developer cannot be verified."*
This is expected — current builds are ad-hoc signed, not notarized.

To proceed:

1. Right-click `MeetingScribe.app` in `/Applications/` → **Open**
2. Click **Open** in the warning dialog

Or from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/MeetingScribe.app
```

**Requirements:** Apple Silicon Mac (M1 or later), macOS 14 (Sonoma) or later.
Intel Macs are not supported by this build.

## Setup

### Requirements
- macOS 14 (Sonoma) or newer
- whisper.cpp: `brew install whisper-cpp`
- ffmpeg: `brew install ffmpeg` — merges your microphone with the system audio
  from video calls. Without it, recordings capture your voice only.
- A whisper model, e.g. `ggml-base.en.bin`

The app installs whisper.cpp, a model, and ffmpeg for you — open **Settings →
Setup** (`Cmd-,`) and use the install buttons, or run `./scripts/setup.sh`.

### Optional: summarization

Two ways to get a summary:

- **Claude Code (recommended)** — every meeting folder ships with a `CLAUDE.md`
  and a `/summarize` slash command. From the macOS app, click **"Open in Claude
  Code"** on the meeting panel; Terminal opens at the meeting folder and runs
  `claude` automatically. Type `/summarize` and the summary panel reloads as
  soon as Claude writes `summary.md`.

  **One-time setup for Claude Code:** install the `claude` CLI by running this
  in Terminal:

  ```bash
  curl -fsSL https://claude.ai/install.sh | bash
  ```

  Then quit and reopen Terminal so `claude` is on your PATH. Verify with
  `claude --version`. Full docs at <https://claude.com/claude-code>.

  First time you click "Open in Claude Code", macOS asks permission to control
  Terminal — click **OK**. If you denied it, re-grant in System Settings →
  Privacy & Security → Automation → MeetingScribe → Terminal.
- **Ollama (fully local, automatic)**: `./scripts/install-ollama.sh` —
  click "Summarize with Ollama" in the panel for an automatic in-app summary,
  no API key needed.

### Build and run the Swift app
```bash
cd apps/macos/MeetingScribe
./build-app.sh debug
open .build/arm64-apple-macosx/debug/MeetingScribe.app
```

(On Intel Macs the `.app` path uses `x86_64-apple-macosx`.)

Press `Cmd-,` in the app to open Settings and pick your summarization provider.

### Running the tests

```bash
./scripts/test.sh
```

Builds and runs the full Swift test suite, exactly as CI does. It uses an
installed Xcode for that one run (via `DEVELOPER_DIR`) without changing your
global `xcode-select`, because the Command Line Tools ship swift-testing but no
runner — `swift test` under CLT alone exits 0 having executed nothing.

### CLI (optional)
```bash
cd cli
npm install
npx tsx bin/meetingctl.ts list
```

### Permissions

On first launch, macOS will ask for:
- **Microphone** — required, to record your voice
- **Screen & System Audio Recording** — optional, to capture audio from Zoom/Meet/Teams
- **Calendar** — optional, to suggest meeting titles from your calendar events

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
      build-app.sh        # Build MeetingScribe.app
  cli/                    # meetingctl — Node.js CLI (list only)
  prompts/                # Summarization templates
  scripts/
    setup.sh              # Install dependencies and build the app
    install-ollama.sh     # Install local Ollama for summarization
    release.sh            # Build a signed DMG
    migrate.sh            # Remove the old web-app install
    transcribe.sh         # Standalone transcription script
    record.sh             # Record + transcribe from terminal
```

## Usage

### Recording a Meeting
1. Open the app and click the menu bar icon
2. (Optional) Type a meeting title or click "Use" on a calendar event
3. (Optional) Select a meeting type tag
4. Click "Start Session"
5. Take notes while it records — you can name or rename the meeting at any point
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
| App | Swift 6, SwiftUI, MenuBarExtra, ScreenCaptureKit, AVAudioEngine |
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
