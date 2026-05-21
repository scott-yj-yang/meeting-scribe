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

# Generate AppIcon.icns from the appiconset PNGs and place into Contents/Resources/
ICONSET_SRC="$(pwd)/Sources/Resources/AppIcon.appiconset"
if [ -d "$ICONSET_SRC" ]; then
    ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET_TMP"
    # iconutil requires these exact filenames (point sizes, not pixel sizes).
    # Mapping: pixel size → iconutil-required name.
    cp "$ICONSET_SRC/icon_16x16.png"     "$ICONSET_TMP/icon_16x16.png"        # 16px
    cp "$ICONSET_SRC/icon_32x32.png"     "$ICONSET_TMP/icon_16x16@2x.png"     # 32px
    cp "$ICONSET_SRC/icon_32x32.png"     "$ICONSET_TMP/icon_32x32.png"        # 32px
    cp "$ICONSET_SRC/icon_64x64.png"     "$ICONSET_TMP/icon_32x32@2x.png"     # 64px
    cp "$ICONSET_SRC/icon_128x128.png"   "$ICONSET_TMP/icon_128x128.png"      # 128px
    cp "$ICONSET_SRC/icon_256x256.png"   "$ICONSET_TMP/icon_128x128@2x.png"   # 256px
    cp "$ICONSET_SRC/icon_256x256.png"   "$ICONSET_TMP/icon_256x256.png"      # 256px
    cp "$ICONSET_SRC/icon_512x512.png"   "$ICONSET_TMP/icon_256x256@2x.png"   # 512px
    cp "$ICONSET_SRC/icon_512x512.png"   "$ICONSET_TMP/icon_512x512.png"      # 512px
    cp "$ICONSET_SRC/icon_1024x1024.png" "$ICONSET_TMP/icon_512x512@2x.png"   # 1024px
    iconutil --convert icns "$ICONSET_TMP" --output "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_TMP")"
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
