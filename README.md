# MeetingScribe

A self-hosted, privacy-first meeting transcription and summary system for macOS. Records system audio + microphone, transcribes on-device with whisper.cpp, and summarizes with Claude Code. Everything runs locally — no cloud APIs needed for recording or transcription.

## Quick Start

One command to install everything on a Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh | bash
```

This installs all dependencies, sets up the database, builds the macOS app, and starts the web server. See [Setup](#setup) for details.

## Features

### macOS Menu Bar App
- **One-click recording** from the menu bar with system audio + microphone capture
- **Live transcription preview** (first 60 seconds) to confirm audio is working
- **Calendar integration** — auto-suggests meeting titles from your calendar events
- **Meeting type tags** — 1:1, Subgroup, Lab Meeting, Casual, Standup
- **Notes** — jot down notes before/during meetings, saved alongside the transcript
- **On-device transcription** via whisper.cpp (large-v3-turbo model) — fully offline
- **Organized file storage** — `~/MeetingScribe/2026/03-March/25-sprint-planning/`
- **Post-recording panel** — open files in Finder, push to server, delete, start new session
- **Configurable** — mic selection, auto-sync toggle, output directory

### Web Dashboard (Next.js)
- **Notion-style interface** — clean, minimal, dark mode support
- **Meeting list** grouped by day with search, type filters, and batch delete
- **Meeting detail** with tabs: Summary, Transcript, Raw Markdown
- **Chat with Claude** — web-based chat interface that streams Claude Code responses with your transcript as context
- **Summarize with Claude** — one-click summarization with customizable prompts
- **Resummarize** — provide custom instructions to focus on specific topics
- **Auto-summarize** — configurable in settings to trigger automatically
- **Notion sync** — push summaries to a Notion database with one click
- **Calendar data** — shows linked calendar event, organizer, attendees
- **Export** — download any meeting as a `.md` file

### CLI (`meetingctl`)
- `meetingctl list` — list all meetings
- `meetingctl summarize <id>` — summarize with Claude Code
- `meetingctl chat <id>` — interactive Claude session with transcript context
- `meetingctl export <id>` — export as markdown

## Architecture

```
┌─────────────────────────────┐       REST API       ┌──────────────────────────┐
│   macOS Menu Bar App        │ ────────────────────▶ │   Next.js Web App        │
│   (Swift/SwiftUI)           │                       │   (localhost:3000)       │
│                             │                       │                          │
│  ScreenCaptureKit (system)  │                       │  Dashboard + Detail      │
│  AVAudioEngine (mic)        │                       │  Claude Chat (streaming) │
│  SFSpeechRecognizer (live)  │                       │  Notion Sync             │
│  whisper.cpp (final)        │                       │  Prisma + PostgreSQL     │
└─────────────────────────────┘                       └──────────────────────────┘
                                                                │
                                                      ┌────────┴────────┐
                                                      │  meetingctl CLI │
                                                      │  Claude Code    │
                                                      └─────────────────┘
```

**Recording flow:**
1. Click "Start Session" → captures mic + system audio to separate temp files
2. Live transcript shows in the menu bar (SFSpeechRecognizer, auto-disables after 60s)
3. Click "Stop" → ffmpeg merges audio streams with alignment correction
4. whisper.cpp transcribes the merged audio on-device (with progress bar + ETA)
5. Transcript saved locally as markdown + uploaded to web server
6. Summarize via Claude Code, sync to Notion, or chat about it

## Setup

### Prerequisites
- macOS 26+ (Tahoe)
- Xcode Command Line Tools

### Automated Setup

```bash
curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh | bash
```

The script installs:
- **Homebrew** (if missing)
- **Node.js** — for the web app and CLI
- **PostgreSQL 17** — meeting database
- **whisper-cpp** — on-device transcription
- **ffmpeg** — audio processing and stream merging
- **sox** — audio recording utilities
- **tmux** — runs the web server in the background
- **Whisper model** — large-v3-turbo (~1.5GB download)

Then it:
- Clones the repo to `~/Developer/meeting-scribe`
- Sets up the database and runs migrations
- Installs the `meetingctl` CLI globally
- Builds `MeetingScribe.app` → `~/Applications/`
- Starts the web server in a tmux session

### Manual Setup

```bash
# 1. Clone
git clone https://github.com/scott-yj-yang/meeting-scribe.git
cd meeting-scribe

# 2. Install dependencies
brew install node postgresql@17 whisper-cpp ffmpeg sox tmux

# 3. Download whisper model
curl -L -o /opt/homebrew/share/whisper-cpp/ggml-large-v3-turbo.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"

# 4. Set up web app
cd apps/web
npm install
cp .env.local.example .env.local  # Edit DATABASE_URL if needed
createdb meetingscribe
npx prisma migrate dev --name init
npx prisma generate

# 5. Set up CLI
cd ../../cli
npm install && npm link

# 6. Build macOS app
cd ../apps/macos/MeetingScribe
swift build -c release
cd ../../..
./scripts/build-app.sh

# 7. Start web server
cd apps/web && npm run dev
```

### Permissions

On first launch, macOS will ask for:
- **Microphone** — to record your voice
- **Screen & System Audio Recording** — to capture audio from Zoom/Meet/Teams
- **Speech Recognition** — for live transcript preview
- **Calendar** — to suggest meeting titles from your calendar

## Configuration

### macOS App Settings
Click the menu bar icon → Settings:
- **Server URL** — web app address (default: `http://localhost:3000`)
- **Output Directory** — where files are saved (default: `~/MeetingScribe`)
- **Microphone** — select which mic to use
- **Auto-sync** — automatically upload to server after recording
- **Save raw audio** — keep `.wav` files for re-transcription

### Web App Settings
Visit `http://localhost:3000/settings`:
- **Auto-summarize** — automatically trigger Claude summarization on new meetings
- **Dark/light mode** — toggle in the nav bar

### Notion Integration
1. Create a Notion integration at https://www.notion.so/my-integrations
2. Create a meeting database in Notion with properties: Title, Date, Duration, Type, Status
3. Add your integration to the database (... menu → Connections)
4. Set environment variables in `apps/web/.env.local`:
```
NOTION_API_KEY="ntn_..."
NOTION_DATABASE_ID="abc123..."
```

### Prompt Templates
Customize how Claude summarizes meetings by editing files in `prompts/`:
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
        metadata.json     # Title, date, duration, server ID
        notes.md          # Your meeting notes
```

### Project Structure
```
meeting-scribe/
  apps/
    macos/MeetingScribe/  # Swift Package — menu bar app
    web/                  # Next.js 15 + Prisma + PostgreSQL
  cli/                    # meetingctl — Node.js CLI
  prompts/                # Claude summarization templates
  scripts/
    setup.sh              # One-line installation
    build-app.sh          # Build MeetingScribe.app
    transcribe.sh         # Standalone transcription script
    record.sh             # Record + transcribe from terminal
  docker-compose.yml      # Deploy web app + PostgreSQL
```

## Usage

### Recording a Meeting
1. Click the menu bar icon
2. (Optional) Type a meeting title or click "Use" on a calendar event
3. (Optional) Select a meeting type tag
4. Click "Start Session"
5. The live transcript shows for 60 seconds to confirm audio works
6. When done, click "Stop" — whisper.cpp transcribes with a progress bar
7. Review the transcript snippet, open files in Finder, or view in the web dashboard

### Managing Meetings
- **Web dashboard**: `http://localhost:3000` — search, filter, batch delete
- **CLI**: `meetingctl list` — view all meetings from the terminal
- **macOS app**: Click recent recordings to see their summary panel

### Summarizing
- **Web UI**: Click "Summarize with Claude" on any meeting detail page
- **CLI**: `meetingctl summarize <id>`
- **Custom focus**: Click "Resummarize" and provide specific instructions
- **Batch**: `meetingctl summarize --all-pending`

### Chatting About a Meeting
- **Web UI**: Click "Chat with Claude" → ask questions about the transcript
- **CLI**: `meetingctl chat <id>` → interactive Claude session in terminal

## Deployment

### Docker Compose (for a server)
```bash
docker compose up -d
```
Runs PostgreSQL + Next.js. Set `MEETINGSCRIBE_API_KEY` for authentication.

### Web Server Management
```bash
# Start (tmux background)
tmux new-session -d -s meetingscribe -c apps/web "npm run dev"

# View logs
tmux attach -t meetingscribe

# Stop
tmux kill-session -t meetingscribe
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| macOS App | Swift 6, SwiftUI, ScreenCaptureKit, AVAudioEngine, SFSpeechRecognizer |
| Transcription | whisper.cpp (large-v3-turbo, on-device) |
| Web App | Next.js 15, TypeScript, Tailwind CSS, React |
| Database | PostgreSQL + Prisma ORM |
| CLI | Node.js, Commander, TypeScript |
| Summarization | Claude Code CLI |
| Audio Processing | ffmpeg (stream merging, normalization) |
| Notion Sync | Notion API (markdown → Notion blocks) |

## Privacy

- All audio recording and transcription happens **on-device**
- No audio is sent to any cloud service
- The web app runs on **localhost** by default
- Summarization uses Claude Code locally (your API key, direct connection)
- Notion sync is optional and only sends the summary text

## License

MIT
