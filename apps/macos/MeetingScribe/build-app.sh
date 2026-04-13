#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift package clean
swift build --configuration "$CONFIG"

BIN_DIR="$(swift build --configuration "$CONFIG" --show-bin-path)"
APP_DIR="$BIN_DIR/MeetingScribe.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/MeetingScribe" "$APP_DIR/Contents/MacOS/MeetingScribe"
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Copy any bundled resources the Swift package emits
if [ -d "$BIN_DIR/MeetingScribe_MeetingScribe.bundle" ]; then
    cp -R "$BIN_DIR/MeetingScribe_MeetingScribe.bundle" "$APP_DIR/Contents/Resources/"
fi

echo "Built $APP_DIR"
