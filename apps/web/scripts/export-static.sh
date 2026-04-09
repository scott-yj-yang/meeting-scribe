#!/bin/bash
set -euo pipefail

echo "Building Next.js static export for desktop embedding..."
cd "$(dirname "$0")/.."

# Build as static export (no server needed)
NEXT_EXPORT=1 npm run build

# The static files are in 'out/' directory
if [[ -d out ]]; then
    echo "Static export ready at apps/web/out/"
    echo "Files: $(find out -type f | wc -l | tr -d ' ')"
    echo "Size: $(du -sh out | cut -f1)"
else
    echo "Error: out/ directory not created. Check build output."
    exit 1
fi
