#!/bin/bash
set -euo pipefail

echo "Building Next.js standalone..."
cd "$(dirname "$0")/.."
npm run build

echo "Copying standalone output for Tauri sidecar..."
SIDECAR_DIR="src-tauri/sidecar"
rm -rf "$SIDECAR_DIR"
mkdir -p "$SIDECAR_DIR"

# Next.js standalone output includes a minimal Node.js server
cp -r .next/standalone/* "$SIDECAR_DIR/"
cp -r .next/static "$SIDECAR_DIR/.next/static"
cp -r public "$SIDECAR_DIR/public" 2>/dev/null || true

echo "Standalone server ready at $SIDECAR_DIR/"
echo "Run: cd $SIDECAR_DIR && node server.js"
