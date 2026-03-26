#!/bin/bash
# Build MeetingScribe.app — a proper macOS .app bundle
#
# Usage: ./scripts/build-app.sh
# Output: ~/Applications/MeetingScribe.app
#
# After building, you can:
#   1. Double-click MeetingScribe.app in ~/Applications to launch
#   2. Drag it to Login Items (System Settings > General > Login Items) to auto-start
#   3. Right-click > Show in Finder to find it

# No set -e — we handle errors manually

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_DIR="$PROJECT_DIR/apps/macos/MeetingScribe"
APP_DIR="$HOME/Applications/MeetingScribe.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo -e "${BLUE}Building MeetingScribe...${NC}"
cd "$SWIFT_DIR"
swift build -c release 2>&1 | tail -3

BINARY="$SWIFT_DIR/.build/release/MeetingScribe"
if [ ! -f "$BINARY" ]; then
    echo "Build failed — binary not found"
    exit 1
fi

echo -e "${BLUE}Creating app bundle...${NC}"
mkdir -p "$MACOS_DIR" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS_DIR/MeetingScribe"

# Copy app icon
ICON_SRC="$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_512x512.png"
if [ -f "$ICON_SRC" ]; then
    # Convert PNG to ICNS
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
    cp "$SWIFT_DIR/Sources/Resources/AppIcon.appiconset/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns" 2>/dev/null || echo "  (icon generation skipped)"
    echo -e "${GREEN}Icon added${NC}"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MeetingScribe</string>
    <key>CFBundleDisplayName</key>
    <string>MeetingScribe</string>
    <key>CFBundleIdentifier</key>
    <string>com.meetingscribe.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MeetingScribe</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetingScribe needs microphone access to record your voice during meetings.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingScribe needs screen capture access to record system audio from meeting calls.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>MeetingScribe uses speech recognition for live transcription during meetings.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>MeetingScribe checks your calendar to suggest meeting titles and link recordings to events.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>MeetingScribe checks your calendar to suggest meeting titles and link recordings to events.</string>
</dict>
</plist>
PLIST

# LSUIElement=true makes it a menu bar-only app (no Dock icon)

echo -e "${GREEN}Built: $APP_DIR${NC}"
echo ""
echo "To launch:  open ~/Applications/MeetingScribe.app"
echo "To auto-start: System Settings > General > Login Items > add MeetingScribe"
echo ""
echo -e "${BLUE}Launching...${NC}"
open "$APP_DIR"
