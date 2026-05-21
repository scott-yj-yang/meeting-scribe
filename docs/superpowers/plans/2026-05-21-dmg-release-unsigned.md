# Unsigned DMG Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an ad-hoc-signed DMG of `MeetingScribe.app` on every `v*` tag push and upload it to GitHub Releases — without Apple Developer ID, without notarization. Users get a downloadable DMG with documented first-launch quarantine workaround.

**Architecture:** `scripts/release.sh` wraps the existing `build-app.sh release` (already ad-hoc signs) and packages the result with `create-dmg`. `.github/workflows/release.yml` triggers on tag push, runs `release.sh` on a `macos-14` runner, uploads to GH Release. No secrets needed. Apple Silicon only (CI runner is `arm64`); Intel users not supported in v1 — explicitly documented.

**Tech Stack:** Swift Package Manager (existing), `codesign` ad-hoc (existing), `create-dmg` (Homebrew), GitHub Actions, `softprops/action-gh-release@v2`.

**Supersedes (partially):** `docs/superpowers/plans/2026-05-21-dmg-release.md` while no Developer ID is available. When Developer ID is added, that plan replaces this one (notarization layers on top of what's here).

---

### Task 1: Write scripts/release.sh

**Files:**
- Create: `scripts/release.sh`

- [ ] **Step 1: Create the script**

```bash
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
```

- [ ] **Step 2: Make executable + syntax check**

```bash
chmod +x scripts/release.sh
git update-index --chmod=+x scripts/release.sh
bash -n scripts/release.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/release.sh
git commit -m "feat(release): scripts/release.sh builds ad-hoc-signed DMG"
```

---

### Task 2: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-dmg:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Build, sign (ad-hoc), package DMG
        env:
          VERSION: ${{ github.ref_name }}
        run: bash scripts/release.sh

      - name: Upload DMG to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: dist/*.dmg
          draft: false
          generate_release_notes: true
          body: |
            ## Installation

            Download `MeetingScribe-<version>.dmg`, double-click to open, then drag
            **MeetingScribe.app** into your Applications folder.

            **First launch (one-time, per machine):** macOS will show
            *"MeetingScribe.app cannot be opened because the developer cannot
            be verified."* This is expected — this build is ad-hoc signed,
            not notarized.

            To proceed:
            1. Right-click `MeetingScribe.app` in `/Applications/` → **Open**
            2. Click **Open** in the warning dialog

            Or from Terminal:
            ```
            xattr -dr com.apple.quarantine /Applications/MeetingScribe.app
            ```

            **Requirements:** Apple Silicon Mac (M1 or later), macOS 14 (Sonoma) or later.
            Intel Macs are not supported by this build.
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(release): GH Actions workflow on v* tag push (unsigned DMG)"
```

---

### Task 3: README — add Installation section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Insert new section AFTER the existing "Upgrading from the old (main branch) install" section and BEFORE "## Setup"**

```markdown
## Installing the DMG

Once a release is published, download the latest `MeetingScribe-X.Y.Z.dmg`
from [GitHub Releases](https://github.com/scott-yj-yang/meeting-scribe/releases/latest),
double-click to open, and drag **MeetingScribe.app** to your Applications folder.

**First launch (one-time per machine):** macOS will show
*"MeetingScribe.app cannot be opened because the developer cannot be verified."*
This is expected — current builds are ad-hoc signed, not notarized.

To proceed:

1. Right-click `MeetingScribe.app` in `/Applications/` → **Open**
2. Click **Open** in the warning dialog

Or from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/MeetingScribe.app
```

**Requirements:** Apple Silicon Mac (M1 or later), macOS 14 (Sonoma) or later.
Intel Macs are not supported by this build.
```

- [ ] **Step 2: Verify section ordering**

```bash
grep -n "^## " README.md
```
Expected order (first three sections): `Features`, `Upgrading from the old (main branch) install`, `Installing the DMG`, `Setup`.

(Section order may vary based on the existing README; just confirm the new section sits between the upgrade section and `## Setup`.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(release): install instructions for unsigned DMG"
```

---

### Task 4: End-to-end smoke test (manual, requires create-dmg)

This task is OPTIONAL on the user's machine if they don't want to install `create-dmg` locally. The CI workflow will catch real issues. Skip if local testing is not possible.

- [ ] **Step 1: If create-dmg is available locally**

```bash
brew install create-dmg    # if not already installed
VERSION=v0.1.0-test bash scripts/release.sh
ls -lh dist/
open dist/MeetingScribe-0.1.0-test.dmg
```

Expected:
- `dist/MeetingScribe-0.1.0-test.dmg` exists (≈10–50 MB)
- DMG mounts and shows MeetingScribe.app + an Applications shortcut

- [ ] **Step 2: Clean up test artifacts (don't commit dist/)**

```bash
git status    # confirm dist/ is not staged — it's already in .gitignore? if not, add it
echo "dist/" >> .gitignore    # only if `dist/` not already ignored
git status --short | grep -v "^??" | grep dist && echo "ERROR: dist/ is tracked" || echo "OK"
```

- [ ] **Step 3: If you added dist/ to .gitignore, commit**

```bash
git add .gitignore
git commit -m "chore: ignore dist/"
```

---

## Self-Review Checklist (done)

- **Coverage:** release.sh ✓, GH Actions workflow ✓, README install instructions ✓, .gitignore for dist/ ✓ (conditional).
- **No Developer ID assumed:** release.sh checks for `create-dmg` but no signing identity. No `notarytool` / `stapler` calls. No secrets in the workflow.
- **Apple Silicon only:** documented in script comment, README, and release body.
- **Placeholders:** None. Every command and YAML key is concrete.
