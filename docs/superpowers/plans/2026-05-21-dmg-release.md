# DMG Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `MeetingScribe.app` as a signed, notarized DMG via GitHub Releases on every `v*` tag push, so end users can download → drag-to-Applications → launch with no Terminal and no Gatekeeper warning.

**Architecture:** Three-layer build. `apps/macos/MeetingScribe/build-app.sh` keeps producing the `.app` (already exists). A new `scripts/release.sh` wraps it: signs with Developer ID, runs `xcrun notarytool submit --wait`, staples the ticket, packages with `create-dmg`. A new `.github/workflows/release.yml` triggers on tag push, runs `release.sh` on a `macos-14` runner, uploads the `.dmg` to the GH Release. Secrets (cert .p12, password, Apple ID, app-specific password, team ID) live in repo secrets.

**Tech Stack:** Swift Package Manager build (existing), `codesign`, `xcrun notarytool`, `xcrun stapler`, `create-dmg` (Homebrew), GitHub Actions, macOS keychain (`security import` in CI).

---

## Prerequisites (NOT code tasks — confirm before executing)

- [ ] Apple Developer Program account active ($99/yr) — owner: user
- [ ] Developer ID Application certificate generated and exported as `.p12` (private key included)
- [ ] App-specific password generated at appleid.apple.com → Sign-In and Security → App-Specific Passwords
- [ ] Apple Team ID captured (10-char string from developer.apple.com → Membership)
- [ ] These five secrets added to GitHub repo settings → Secrets and variables → Actions:
  - `APPLE_CERT_P12_BASE64` (output of `base64 -i cert.p12`)
  - `APPLE_CERT_PASSWORD` (the .p12 export password)
  - `APPLE_ID` (Apple ID email)
  - `APPLE_APP_PASSWORD` (the app-specific password)
  - `APPLE_TEAM_ID` (10-char team ID)
- [ ] `create-dmg` installable via `brew install create-dmg` (runner has brew)

**If any prerequisite is missing, the plan still writes the scripts/workflow, but they will fail at the signing step. The migration story is unblocked because users can run `migrate.sh` standalone.**

---

### Task 1: Add entitlements file for Hardened Runtime + required capabilities

**Files:**
- Create: `apps/macos/MeetingScribe/MeetingScribe.entitlements`

Hardened Runtime is required for notarization. The app needs explicit entitlements for the capabilities it requests at runtime.

- [ ] **Step 1: Create the entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.personal-information.calendars</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

(ScreenCaptureKit + SFSpeechRecognizer don't require explicit entitlements; the usage strings in Info.plist drive the TCC prompts.)

- [ ] **Step 2: Commit**

```bash
git add apps/macos/MeetingScribe/MeetingScribe.entitlements
git commit -m "feat(release): add Hardened Runtime entitlements for notarization"
```

---

### Task 2: Extend build-app.sh to support Developer ID signing

**Files:**
- Modify: `apps/macos/MeetingScribe/build-app.sh:36` (the existing `codesign` line)

- [ ] **Step 1: Replace the ad-hoc codesign line with a conditional Developer ID branch**

Current line 36:
```bash
codesign --force --deep --sign - "$APP_DIR" >/dev/null
```

Replace with:
```bash
SIGN_IDENTITY="${MEETINGSCRIBE_SIGN_IDENTITY:--}"
ENTITLEMENTS="$(pwd)/MeetingScribe.entitlements"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
    echo "Built $APP_DIR (ad-hoc signed)"
else
    codesign --force --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$APP_DIR"
    echo "Built $APP_DIR (signed with: $SIGN_IDENTITY)"
fi
```

- [ ] **Step 2: Test the ad-hoc path still works (no Developer ID needed)**

```bash
cd apps/macos/MeetingScribe
./build-app.sh debug
codesign -dvvv .build/arm64-apple-macosx/debug/MeetingScribe.app 2>&1 | grep "Signature"
```
Expected: `Signature=adhoc`.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/MeetingScribe/build-app.sh
git commit -m "feat(release): support Developer ID signing via MEETINGSCRIBE_SIGN_IDENTITY env"
```

---

### Task 3: Write scripts/release.sh

**Files:**
- Create: `scripts/release.sh`

- [ ] **Step 1: Create the script**

```bash
#!/bin/bash
# MeetingScribe — Build, sign, notarize, and package a release DMG.
#
# Required env vars:
#   MEETINGSCRIBE_SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID                      Apple ID email
#   APPLE_APP_PASSWORD            App-specific password from appleid.apple.com
#   APPLE_TEAM_ID                 10-char team ID
#
# Output: dist/MeetingScribe-<version>.dmg

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"
DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/MeetingScribe-$VERSION.dmg"
APP_DIR="$REPO_ROOT/apps/macos/MeetingScribe"

for var in MEETINGSCRIBE_SIGN_IDENTITY APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var is not set" >&2
        exit 1
    fi
done

echo "[1/5] Building app (release config, Developer ID signed)..."
cd "$APP_DIR"
MEETINGSCRIBE_SIGN_IDENTITY="$MEETINGSCRIBE_SIGN_IDENTITY" ./build-app.sh release

BUILT_APP="$(swift build -c release --show-bin-path)/MeetingScribe.app"
[[ -d "$BUILT_APP" ]] || { echo "ERROR: $BUILT_APP not found"; exit 1; }

echo "[2/5] Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

echo "[3/5] Submitting for notarization (this can take 1–10 minutes)..."
ZIP_PATH="$(mktemp -d)/MeetingScribe.zip"
ditto -c -k --keepParent "$BUILT_APP" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

echo "[4/5] Stapling notarization ticket..."
xcrun stapler staple "$BUILT_APP"
xcrun stapler validate "$BUILT_APP"

echo "[5/5] Building DMG..."
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
    "$DMG_PATH" \
    "$BUILT_APP"

echo "Signing DMG..."
codesign --sign "$MEETINGSCRIBE_SIGN_IDENTITY" --timestamp "$DMG_PATH"

echo "Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
xcrun stapler staple "$DMG_PATH"

echo ""
echo "✓ Done: $DMG_PATH"
echo "  $(du -h "$DMG_PATH" | cut -f1) — ready to upload to GitHub Release"
```

- [ ] **Step 2: Make executable, shellcheck-clean**

```bash
chmod +x scripts/release.sh
git update-index --chmod=+x scripts/release.sh
shellcheck scripts/release.sh    # `brew install shellcheck` if missing
```

- [ ] **Step 3: Commit**

```bash
git add scripts/release.sh
git commit -m "feat(release): release.sh builds signed/notarized DMG"
```

---

### Task 4: Add GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Install create-dmg
        run: brew install create-dmg

      - name: Import Developer ID certificate
        env:
          P12_BASE64: ${{ secrets.APPLE_CERT_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.APPLE_CERT_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ github.run_id }}
        run: |
          CERT_PATH=$RUNNER_TEMP/cert.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/build.keychain
          echo "$P12_BASE64" | base64 -d > "$CERT_PATH"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security list-keychain -d user -s "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

      - name: Resolve signing identity
        id: identity
        run: |
          IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
          echo "identity=$IDENTITY" >> "$GITHUB_OUTPUT"
          echo "Using: $IDENTITY"

      - name: Build, sign, notarize, package
        env:
          MEETINGSCRIBE_SIGN_IDENTITY: ${{ steps.identity.outputs.identity }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          VERSION: ${{ github.ref_name }}
        run: bash scripts/release.sh

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: dist/*.dmg
          draft: false
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(release): GH Actions workflow on v* tag push"
```

---

### Task 5: Document the release process

**Files:**
- Create: `docs/release.md`

- [ ] **Step 1: Write a brief operator-facing doc**

```markdown
# Releasing MeetingScribe

## One-time setup
See `docs/superpowers/plans/2026-05-21-dmg-release.md` § Prerequisites
for the exact secrets and certificate exports required.

## Cutting a release
```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions builds, signs, notarizes, packages, and uploads the DMG
to a new GitHub Release. Total runtime: ~10–15 minutes (notarization is
the slow part).

## Verifying locally before pushing the tag
```bash
export MEETINGSCRIBE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="ABCDEFG123"
VERSION=v0.1.0 bash scripts/release.sh
open dist/MeetingScribe-0.1.0.dmg
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/release.md
git commit -m "docs(release): document release cutting and verification"
```

---

## Self-Review Checklist (done)

- **Coverage:** entitlements ✓, signing ✓, notarization ✓, stapling ✓, DMG packaging ✓, CI workflow ✓, docs ✓.
- **Placeholders:** None. Every command and env var is concrete.
- **Blocker callout:** Prerequisites section explicitly lists what the user must do outside this plan (Apple Developer ID, secrets). Plan is still writeable today; only execution of release.sh/workflow requires those secrets.
- **Naming consistency:** `MEETINGSCRIBE_SIGN_IDENTITY` env var used identically in build-app.sh, release.sh, and the workflow.
