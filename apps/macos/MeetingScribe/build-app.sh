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

# Re-sign the bundle so the Info.plist is bound to the code signature.
# SwiftPM ad-hoc-signs the bare executable at link time, but that signature
# seals only the Mach-O binary — it does NOT cover the Contents/Info.plist
# we copied in above. On macOS 15+, an unbound Info.plist is ignored by
# ATS: codesign reports "Info.plist=not bound" and NSAllowsArbitraryLoads
# has no effect, so plain-HTTP requests to LAN/CGNAT IPs get blocked even
# though the plist allows them.
#
# `codesign --force --deep --sign -` re-signs the whole bundle ad-hoc and
# seals the Info.plist into the code directory. Verify with
# `codesign -dvvv <app> | grep Info.plist` — should say "Info.plist entries=N"
# (bound), not "Info.plist=not bound".
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
