#!/bin/bash
# MeetingScribe — Record system audio + microphone, then transcribe
#
# Usage:
#   ./record.sh [--title "Meeting Title"] [--type standup] [--summarize]
#
# Press Ctrl+C to stop recording. The script will then:
#   1. Transcribe with whisper.cpp
#   2. Format as markdown
#   3. Upload to the web app
#
# Requirements:
#   - SoX (brew install sox) — for audio recording
#   - whisper-cpp + model
#   - ffmpeg (brew install ffmpeg)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${MEETINGSCRIBE_OUTPUT_DIR:-$HOME/MeetingScribe}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for sox
if ! command -v sox &>/dev/null; then
    echo -e "${RED}Error: sox not found. Install with: brew install sox${NC}"
    exit 1
fi

# Pass through all arguments except we intercept the audio file part
ARGS=("$@")
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RECORDING_FILE="$OUTPUT_DIR/recordings/${TIMESTAMP}-recording.wav"
mkdir -p "$(dirname "$RECORDING_FILE")"

echo -e "${BLUE}MeetingScribe Recorder${NC}"
echo -e "Recording to: $RECORDING_FILE"
echo -e "${GREEN}Recording started. Press Ctrl+C to stop.${NC}"
echo ""

# Record from default microphone
# SoX records from the default input device
# For system audio, you'd need BlackHole or similar virtual audio device
trap '' INT  # Temporarily ignore Ctrl+C for cleanup
sox -d -r 16000 -c 1 -b 16 "$RECORDING_FILE" &
SOX_PID=$!

# Wait for Ctrl+C
trap "kill $SOX_PID 2>/dev/null; wait $SOX_PID 2>/dev/null" INT
wait $SOX_PID 2>/dev/null || true

echo ""
echo -e "${GREEN}Recording stopped.${NC}"

if [[ ! -f "$RECORDING_FILE" ]] || [[ $(stat -f%z "$RECORDING_FILE" 2>/dev/null || stat -c%s "$RECORDING_FILE" 2>/dev/null) -lt 1000 ]]; then
    echo -e "${RED}Recording too short or failed.${NC}"
    exit 1
fi

# Now transcribe
echo ""
exec "$SCRIPT_DIR/transcribe.sh" "$RECORDING_FILE" "${ARGS[@]}"
