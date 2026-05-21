#!/bin/bash
# MeetingScribe — Build an ad-hoc-signed DMG (no Developer ID).
#
# Usage:
#   VERSION=v0.1.0 bash scripts/release.sh
#   # or, with a tag already pushed:
#   bash scripts/release.sh    # version is read from `git describe`
#
# Output:
#   dist/MeetingScribe-<version>.dmg
#
# Caveats:
#   - Ad-hoc signed only. Users will hit Gatekeeper on first launch.
#     See README "Installing the DMG" for the right-click → Open or
#     `xattr -dr com.apple.quarantine ...` workaround.
#   - Apple Silicon only. The output runs natively on M-series Macs.
#     Intel Macs are not supported by this build.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW_VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo dev)}"
VERSION="${RAW_VERSION#v}"
DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/MeetingScribe-$VERSION.dmg"
APP_DIR="$REPO_ROOT/apps/macos/MeetingScribe"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "ERROR: create-dmg not found. Install with: brew install create-dmg" >&2
    exit 1
fi

echo "[1/3] Building app (release, ad-hoc signed)..."
cd "$APP_DIR"
./build-app.sh release

BUILT_APP="$(swift build -c release --show-bin-path)/MeetingScribe.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "ERROR: $BUILT_APP not found" >&2
    exit 1
fi

echo "[2/3] Verifying ad-hoc signature..."
codesign -dvvv "$BUILT_APP" 2>&1 | grep -E "Signature|Identifier" || true

echo "[3/3] Packaging DMG..."
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
create-dmg \
    --volname "MeetingScribe $VERSION" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "MeetingScribe.app" 175 190 \
    --app-drop-link 425 190 \
    --hide-extension "MeetingScribe.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$BUILT_APP"

echo ""
echo "✓ Built $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo "  Users: right-click → Open on first launch to bypass Gatekeeper"
