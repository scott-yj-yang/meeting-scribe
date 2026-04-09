#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MACOS_DIR="$PROJECT_DIR/apps/macos/MeetingScribe"

echo "=== MeetingScribe Unified App Build ==="
echo ""

# Step 1: Build Swift app (dev mode — loads from localhost:3000)
echo "[1/1] Building Swift app..."
cd "$MACOS_DIR"
swift build 2>&1 | tail -5

BINARY="$MACOS_DIR/.build/debug/MeetingScribe"
if [[ -f "$BINARY" ]]; then
    echo ""
    echo "=== Build complete! ==="
    echo "Run: $BINARY"
    echo ""
    echo "Note: Start the web dev server first:"
    echo "  cd $PROJECT_DIR/apps/web && npm run dev"
    echo "Then launch the app — it will load localhost:3000 in the dashboard window."
else
    echo "Build failed — binary not found"
    exit 1
fi
