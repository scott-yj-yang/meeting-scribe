#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

# Build via build-app.sh so bundle assembly stays in one place
./build-app.sh "$CONFIG"

BIN_DIR="$(swift build --configuration "$CONFIG" --show-bin-path)"
SRC_APP="$BIN_DIR/MeetingScribe.app"
DEST_APP="/Applications/MeetingScribe.app"

if [ ! -d "$SRC_APP" ]; then
    echo "Error: built app not found at $SRC_APP" >&2
    exit 1
fi

# Quit the app if it's running so we don't clobber a live process
if pgrep -x "MeetingScribe" >/dev/null; then
    echo "Quitting running MeetingScribe..."
    osascript -e 'tell application "MeetingScribe" to quit' 2>/dev/null || pkill -x MeetingScribe || true
    sleep 1
fi

# Replace any existing install
if [ -d "$DEST_APP" ]; then
    rm -rf "$DEST_APP"
fi

# ditto preserves .app bundle metadata, symlinks, and extended attributes
ditto "$SRC_APP" "$DEST_APP"

echo "Installed $DEST_APP"
