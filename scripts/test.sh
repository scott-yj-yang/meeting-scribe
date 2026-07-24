#!/usr/bin/env bash
#
# Local CI — builds and runs the full Swift test suite the same way
# .github/workflows/ci.yml does, but on this machine so you don't wait on
# GitHub. Run from anywhere:
#
#   ./scripts/test.sh
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/macos/MeetingScribe"

info() { printf '\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✘ %s\033[0m\n' "$1" >&2; }
ok()   { printf '\033[32m✔ %s\033[0m\n' "$1"; }

# `swift test` needs a real Xcode. The Command Line Tools ship swift-testing but
# no test runner, so under CLT `swift test` exits 0 having executed nothing. Use
# an installed Xcode for this run only, via DEVELOPER_DIR, without touching the
# global `xcode-select` (that would need sudo).
DEV_DIR=""
active="$(xcode-select -p 2>/dev/null || true)"
if [[ "$active" == *".app/Contents/Developer" ]]; then
    DEV_DIR="$active"
else
    for xc in /Applications/Xcode*.app; do
        [[ -d "$xc/Contents/Developer" ]] && { DEV_DIR="$xc/Contents/Developer"; break; }
    done
fi

if [[ -z "$DEV_DIR" ]]; then
    fail "No Xcode found in /Applications — tests can't run under the Command Line Tools alone."
    fail "Install Xcode from the App Store, then re-run this script."
    exit 1
fi

export DEVELOPER_DIR="$DEV_DIR"
xcode_app="${DEV_DIR%/Contents/Developer}"

# One-time license gate — needs sudo, so it can't be done for you.
if swift --version 2>&1 | grep -qi "license"; then
    fail "Xcode's license hasn't been accepted yet. Run these two commands, in this order:"
    echo
    echo "    sudo xcode-select -s \"$xcode_app\""
    echo "    sudo xcodebuild -license accept"
    echo
    fail "Then re-run ./scripts/test.sh"
    exit 1
fi

info "Toolchain: $(swift --version 2>/dev/null | head -1)"
info "Using $xcode_app"
cd "$APP_DIR" || exit 1

info "swift build"
if ! swift build; then
    fail "Build failed."
    exit 1
fi
ok "Build succeeded"

info "swift test"
log="$(mktemp -t meetingscribe-test)"
swift test 2>&1 | tee "$log"
test_rc=${PIPESTATUS[0]}

if [[ $test_rc -ne 0 ]]; then
    fail "Tests failed."
    exit 1
fi
# Belt and suspenders: catch a toolchain that "succeeds" without running anything.
if ! grep -q "Test run with" "$log"; then
    fail "No tests ran — the active toolchain has no test runner. Check your Xcode selection."
    exit 1
fi
ok "All tests passed"
