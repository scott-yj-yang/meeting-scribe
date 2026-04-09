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
    -ojf \
    -of "$TRANSCRIPT_FILE" \
    --no-timestamps false \
    -l auto \
    -ml 40 \
    -bo 5 \
    -bs 5 \
    -et 2.4 \
    -lpt -0.5 \
    -sns \
    -noc \
    2>/dev/null

if [[ ! -f "$TRANSCRIPT_FILE.json" ]]; then
    echo -e "${RED}Error: Transcription failed.${NC}"
    rm -rf "$TMPDIR_WORK"
    exit 1
fi

# --- Post-process: confidence filtering + hallucination removal + repetition collapse ---
echo -e "${BLUE}[2.5/4] Filtering hallucinations...${NC}"

RAW_WORD_COUNT=$(python3 -c "
import json
with open('$TRANSCRIPT_FILE.json') as f:
    data = json.load(f)
print(sum(len(s['text'].split()) for s in data.get('segments',[])))
")

TRANSCRIPT_TEXT=$(python3 -c "
import json, sys, re

# --- Confidence-based segment filtering ---
with open('$TRANSCRIPT_FILE.json') as f:
    data = json.load(f)

segments = data.get('segments', [])
total = len(segments)
confident = []
for seg in segments:
    comp = seg.get('compression_ratio', 0)
    no_speech = seg.get('no_speech_prob', 0)
    logprob = seg.get('avg_logprob', 0)
    if comp <= 2.4 and no_speech <= 0.6 and logprob >= -1.0:
        confident.append(seg)

filtered = total - len(confident)
if filtered > 0:
    print(f'Filtered {filtered}/{total} low-confidence segments', file=sys.stderr)

text = ' '.join(seg['text'].strip() for seg in confident)

# --- Known hallucination phrase removal ---
HALLUCINATIONS = [
    'thank you for watching', 'thanks for watching',
    'thanks for listening', 'thank you for listening',
    'subscribe to my channel', 'please subscribe',
    'like and subscribe', 'please like and subscribe',
    'don.t forget to subscribe', 'hit the bell icon',
    'see you in the next video', 'see you next time',
    'leave a comment below', 'check out my other videos',
    'turn on notifications', 'subtitles by',
    'subtitles created by', 'translated by', 'amara org',
]
removed = 0
for phrase in HALLUCINATIONS:
    pattern = re.compile(r'\b' + re.escape(phrase) + r'\b[.!?,;]*', re.IGNORECASE)
    text, n = pattern.subn('', text)
    removed += n
if removed > 0:
    print(f'Removed {removed} known hallucination phrases', file=sys.stderr)
text = re.sub(r'\s{2,}', ' ', text).strip()

# --- Sentence-level dedup ---
sentences = re.split(r'(?<=[.!?])\s+', text)
if len(sentences) > 1:
    deduped = [sentences[0]]
    for i in range(1, len(sentences)):
        prev_norm = re.sub(r'[^\w\s]', '', sentences[i-1].lower()).strip()
        curr_norm = re.sub(r'[^\w\s]', '', sentences[i].lower()).strip()
        if curr_norm != prev_norm:
            deduped.append(sentences[i])
    text = ' '.join(deduped)

# --- Word-level n-gram collapse (normalized) ---
def norm(w):
    return re.sub(r'[^\w]', '', w.lower())

def collapse(words):
    result = []
    i = 0
    while i < len(words):
        bl = bc = 0
        for pl in range(min(25, (len(words)-i)//2), 0, -1):
            if i+pl*2 > len(words): continue
            ph = [norm(w) for w in words[i:i+pl]]
            c = 1
            j = i+pl
            while j+pl <= len(words) and [norm(w) for w in words[j:j+pl]] == ph:
                c += 1; j += pl
            if c >= 3 and pl*c > bl*bc:
                bl, bc = pl, c
        if bl > 0 and bc >= 3:
            result.extend(words[i:i+bl]); i += bl*bc
        else:
            result.append(words[i]); i += 1
    return result

words = text.split()
for _ in range(5):
    prev = words
    words = collapse(words)
    if words == prev: break
print(' '.join(words))
")

CLEAN_WORD_COUNT=$(echo "$TRANSCRIPT_TEXT" | wc -w | tr -d ' ')
echo -e "${GREEN}Transcription complete ($RAW_WORD_COUNT words → $CLEAN_WORD_COUNT after filtering)${NC}"

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

# Build timestamp-aligned markdown from whisper JSON segments
TRANSCRIPT_MD=$(python3 -c "
import json, re

with open('$TRANSCRIPT_FILE.json') as f:
    data = json.load(f)

segments = [s for s in data.get('segments',[]) if s.get('compression_ratio',0)<=2.4 and s.get('no_speech_prob',0)<=0.6 and s.get('avg_logprob',0)>=-1.0]

for s in segments:
    text = s['text'].strip()
    if not text: continue
    secs = int(s.get('start', 0))
    h, rem = divmod(secs, 3600)
    m, sec = divmod(rem, 60)
    ts = f'[{h:02d}:{m:02d}:{sec:02d}]'
    print(f'{ts} **Speaker**: {text}')
    print()
")

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

$TRANSCRIPT_MD

## --- END TRANSCRIPT ---
MDEOF

echo -e "${GREEN}Saved to: $MD_FILE${NC}"

# --- Step 4: Upload to web app ---
echo -e "${BLUE}[4/4] Uploading to web app...${NC}"

# Build JSON payload
SEGMENTS_JSON=$(python3 -c "
import json
with open('$TRANSCRIPT_FILE.json') as f:
    data = json.load(f)
segments = [s for s in data.get('segments',[]) if s.get('compression_ratio',0)<=2.4 and s.get('no_speech_prob',0)<=0.6 and s.get('avg_logprob',0)>=-1.0]
out = [{'speaker':'Speaker','text':s['text'].strip(),'startTime':s.get('start',0),'endTime':s.get('end',0)} for s in segments if s['text'].strip()]
print(json.dumps(out))
")

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
