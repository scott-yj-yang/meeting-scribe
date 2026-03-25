#!/bin/bash
# MeetingScribe — Transcribe a recording with whisper.cpp and upload to web app
#
# Usage:
#   ./transcribe.sh <audio-file> [--title "Meeting Title"] [--type standup] [--summarize]
#
# Examples:
#   ./transcribe.sh ~/recording.m4a
#   ./transcribe.sh ~/recording.wav --title "Sprint Planning" --type planning --summarize
#   ./transcribe.sh ~/recording.m4a --summarize
#
# Requirements:
#   - whisper-cli (brew install whisper-cli)
#   - whisper model downloaded (whisper-cli-download-ggml-model large-v3-turbo)
#   - ffmpeg (brew install ffmpeg) — for audio format conversion
#   - Web server running at localhost:3000 (cd apps/web && npm run dev)

set -euo pipefail

# --- Configuration ---
API_URL="${MEETINGSCRIBE_API_URL:-http://localhost:3000}"
API_KEY="${MEETINGSCRIBE_API_KEY:-}"
MODEL_PATH="${WHISPER_MODEL:-$(find ~/.local/share/whisper-cli /opt/homebrew/share/whisper-cli 2>/dev/null -name "ggml-large-v3-turbo.bin" -print -quit 2>/dev/null || echo "")}"
OUTPUT_DIR="${MEETINGSCRIBE_OUTPUT_DIR:-$HOME/MeetingScribe}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Parse arguments ---
AUDIO_FILE=""
TITLE=""
MEETING_TYPE=""
DO_SUMMARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="$2"; shift 2 ;;
        --type) MEETING_TYPE="$2"; shift 2 ;;
        --summarize) DO_SUMMARIZE=true; shift ;;
        --help|-h)
            echo "Usage: $0 <audio-file> [--title \"Title\"] [--type type] [--summarize]"
            echo ""
            echo "Options:"
            echo "  --title     Meeting title (default: derived from filename)"
            echo "  --type      Meeting type: standup, 1on1, planning, retro, sales"
            echo "  --summarize Run Claude Code summarization after upload"
            exit 0
            ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *) AUDIO_FILE="$1"; shift ;;
    esac
done

if [[ -z "$AUDIO_FILE" ]]; then
    echo -e "${RED}Error: No audio file provided${NC}"
    echo "Usage: $0 <audio-file> [--title \"Title\"] [--type type] [--summarize]"
    exit 1
fi

if [[ ! -f "$AUDIO_FILE" ]]; then
    echo -e "${RED}Error: File not found: $AUDIO_FILE${NC}"
    exit 1
fi

# Default title from filename
if [[ -z "$TITLE" ]]; then
    TITLE="$(basename "$AUDIO_FILE" | sed 's/\.[^.]*$//' | tr '_-' '  ')"
fi

# --- Check dependencies ---
if ! command -v whisper-cli &>/dev/null; then
    echo -e "${RED}Error: whisper-cli not found. Install with: brew install whisper-cli${NC}"
    exit 1
fi

if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
    echo -e "${RED}Error: Whisper model not found.${NC}"
    echo "Download with: whisper-cli-download-ggml-model large-v3-turbo"
    exit 1
fi

# --- Step 1: Convert audio to WAV (16kHz mono, required by whisper.cpp) ---
echo -e "${BLUE}[1/4] Converting audio to WAV...${NC}"
TMPDIR_WORK=$(mktemp -d)
WAV_FILE="$TMPDIR_WORK/input.wav"

if command -v ffmpeg &>/dev/null; then
    ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y -loglevel error
else
    echo -e "${YELLOW}Warning: ffmpeg not found. Trying raw file (may fail if not WAV 16kHz).${NC}"
    echo "Install ffmpeg with: brew install ffmpeg"
    cp "$AUDIO_FILE" "$WAV_FILE"
fi

# Get audio duration
DURATION_SECS=0
if command -v ffprobe &>/dev/null; then
    DURATION_SECS=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$AUDIO_FILE" | cut -d. -f1)
fi

# --- Step 2: Transcribe with whisper.cpp ---
echo -e "${BLUE}[2/4] Transcribing with whisper.cpp (this may take a few minutes)...${NC}"
TRANSCRIPT_FILE="$TMPDIR_WORK/transcript"

whisper-cli \
    -m "$MODEL_PATH" \
    -f "$WAV_FILE" \
    -otxt \
    -of "$TRANSCRIPT_FILE" \
    --no-timestamps false \
    -l auto \
    2>/dev/null

if [[ ! -f "$TRANSCRIPT_FILE.txt" ]]; then
    echo -e "${RED}Error: Transcription failed.${NC}"
    rm -rf "$TMPDIR_WORK"
    exit 1
fi

TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE.txt")
echo -e "${GREEN}Transcription complete ($(wc -w < "$TRANSCRIPT_FILE.txt") words)${NC}"

# --- Step 3: Format as MeetingScribe markdown ---
echo -e "${BLUE}[3/4] Formatting transcript...${NC}"

DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_HUMAN=$(date +"%B %d, %Y %I:%M %p")

# Format duration
format_duration() {
    local secs=$1
    local h=$((secs / 3600))
    local m=$(((secs % 3600) / 60))
    local s=$((secs % 60))
    local parts=""
    [[ $h -gt 0 ]] && parts="${h} hour$( [[ $h -ne 1 ]] && echo 's') "
    [[ $m -gt 0 ]] && parts="${parts}${m} minute$( [[ $m -ne 1 ]] && echo 's') "
    [[ $s -gt 0 || -z "$parts" ]] && parts="${parts}${s} second$( [[ $s -ne 1 ]] && echo 's')"
    echo "$parts"
}

DURATION_HUMAN=$(format_duration "$DURATION_SECS")

# Create markdown
MD_FILE="$OUTPUT_DIR/$(date +%Y-%m-%d-%H-%M)-$(echo "$TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]').md"
mkdir -p "$OUTPUT_DIR"

cat > "$MD_FILE" << MDEOF
---
title: "$TITLE"
date: $DATE_ISO
duration: $DURATION_SECS
meeting_type: ${MEETING_TYPE:+"\"$MEETING_TYPE\""}${MEETING_TYPE:-null}
audio_sources: ["microphone"]
participants: ["Speaker"]
---

# Meeting Transcript: $TITLE
**Date**: $DATE_HUMAN
**Duration**: $DURATION_HUMAN

## Transcript

$TRANSCRIPT_TEXT

## --- END TRANSCRIPT ---
MDEOF

echo -e "${GREEN}Saved to: $MD_FILE${NC}"

# --- Step 4: Upload to web app ---
echo -e "${BLUE}[4/4] Uploading to web app...${NC}"

# Build JSON payload
SEGMENTS_JSON=$(echo "$TRANSCRIPT_TEXT" | awk '
BEGIN { printf "["; first=1 }
NF > 0 {
    gsub(/"/, "\\\"")
    if (!first) printf ","
    printf "{\"speaker\":\"Speaker\",\"text\":\"%s\",\"startTime\":0,\"endTime\":0}", $0
    first=0
}
END { printf "]" }
')

AUTH_HEADER=""
if [[ -n "$API_KEY" ]]; then
    AUTH_HEADER="-H \"Authorization: Bearer $API_KEY\""
fi

RAW_MD=$(cat "$MD_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/meetings" \
    -H "Content-Type: application/json" \
    ${API_KEY:+-H "Authorization: Bearer $API_KEY"} \
    -d "{
        \"title\": $(echo "$TITLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
        \"date\": \"$DATE_ISO\",
        \"duration\": $DURATION_SECS,
        \"audioSources\": [\"microphone\"],
        \"meetingType\": $(if [[ -n "$MEETING_TYPE" ]]; then echo "\"$MEETING_TYPE\""; else echo "null"; fi),
        \"rawMarkdown\": $RAW_MD,
        \"segments\": $SEGMENTS_JSON
    }" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "201" ]]; then
    MEETING_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['id'])" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}Uploaded! Meeting ID: $MEETING_ID${NC}"
    echo -e "${GREEN}View at: $API_URL/meetings/$MEETING_ID${NC}"

    # --- Optional: Summarize ---
    if $DO_SUMMARIZE; then
        echo -e "${BLUE}Running Claude Code summarization...${NC}"
        PROMPTS_DIR="${MEETINGSCRIBE_PROMPTS_DIR:-$(dirname "$SCRIPT_DIR")/prompts}"
        if [[ -f "$PROMPTS_DIR/summarize.md" ]]; then
            claude --allowedTools "Read" -p "$(cat "$PROMPTS_DIR/summarize.md")" "$MD_FILE"
        else
            echo -e "${YELLOW}Prompt template not found at $PROMPTS_DIR/summarize.md${NC}"
            echo "Run manually: meetingctl summarize $MEETING_ID"
        fi
    fi
else
    echo -e "${YELLOW}Upload failed (HTTP $HTTP_CODE). Transcript saved locally at: $MD_FILE${NC}"
    if [[ "$HTTP_CODE" == "000" ]]; then
        echo -e "${YELLOW}Is the web server running? Start with: cd apps/web && npm run dev${NC}"
    fi
fi

# Cleanup
rm -rf "$TMPDIR_WORK"

echo -e "${GREEN}Done!${NC}"
