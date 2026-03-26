#!/bin/bash
# MeetingScribe — Clean teardown
#
# Usage:
#   ./scripts/teardown.sh          # Interactive — asks what to remove
#   ./scripts/teardown.sh --all    # Remove everything without prompting

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
skip() { echo -e "  ${BLUE}-${NC} $1"; }

INSTALL_DIR="$HOME/Developer/meeting-scribe"
ALL=false
if [[ "${1:-}" == "--all" ]]; then ALL=true; fi

confirm() {
    if $ALL; then return 0; fi
    read -p "  $1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

echo -e "${RED}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║     MeetingScribe Teardown           ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# 1. Stop web server
echo -e "${BLUE}[1/7]${NC} Stopping web server..."
if tmux has-session -t meetingscribe 2>/dev/null; then
    tmux kill-session -t meetingscribe
    ok "Stopped tmux session 'meetingscribe'"
else
    skip "No tmux session running"
fi

# 2. Remove macOS app
echo -e "${BLUE}[2/7]${NC} macOS app..."
if [[ -d ~/Applications/MeetingScribe.app ]]; then
    # Quit the app first
    osascript -e 'quit app "MeetingScribe"' 2>/dev/null || true
    sleep 1
    if confirm "Remove ~/Applications/MeetingScribe.app?"; then
        rm -rf ~/Applications/MeetingScribe.app
        ok "Removed MeetingScribe.app"
    else
        skip "Kept MeetingScribe.app"
    fi
else
    skip "App not installed"
fi

# 3. Unlink CLI
echo -e "${BLUE}[3/7]${NC} CLI tool..."
if command -v meetingctl &>/dev/null; then
    if confirm "Unlink meetingctl CLI?"; then
        cd "$INSTALL_DIR/cli" 2>/dev/null && npm unlink 2>/dev/null || true
        # Also try removing the symlink directly
        rm -f "$(which meetingctl)" 2>/dev/null || true
        ok "Unlinked meetingctl"
    else
        skip "Kept meetingctl"
    fi
else
    skip "meetingctl not installed"
fi

# 4. Drop database
echo -e "${BLUE}[4/7]${NC} Database..."
if psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw meetingscribe; then
    if confirm "Drop PostgreSQL database 'meetingscribe'? (all meeting data on server will be lost)"; then
        dropdb meetingscribe 2>/dev/null
        ok "Dropped database 'meetingscribe'"
    else
        skip "Kept database"
    fi
else
    skip "Database doesn't exist"
fi

# 5. Remove recordings
echo -e "${BLUE}[5/7]${NC} Local recordings..."
if [[ -d ~/MeetingScribe ]]; then
    SIZE=$(du -sh ~/MeetingScribe 2>/dev/null | cut -f1)
    if confirm "Remove ~/MeetingScribe/ ($SIZE of recordings, transcripts, audio)?"; then
        rm -rf ~/MeetingScribe
        ok "Removed ~/MeetingScribe/"
    else
        skip "Kept recordings at ~/MeetingScribe/"
    fi
else
    skip "No recordings directory"
fi

# 6. Remove source code
echo -e "${BLUE}[6/7]${NC} Source code..."
if [[ -d "$INSTALL_DIR" ]]; then
    if confirm "Remove source code at $INSTALL_DIR?"; then
        rm -rf "$INSTALL_DIR"
        ok "Removed $INSTALL_DIR"
    else
        skip "Kept source code"
    fi
else
    skip "Source not found"
fi

# 7. Optionally remove brew dependencies
echo -e "${BLUE}[7/7]${NC} Homebrew dependencies..."
if confirm "Uninstall whisper-cpp, sox? (keeps node, postgresql, ffmpeg, tmux as they're commonly used)"; then
    brew uninstall whisper-cpp 2>/dev/null && ok "Removed whisper-cpp" || skip "whisper-cpp not found"
    brew uninstall sox 2>/dev/null && ok "Removed sox" || skip "sox not found"
    # Remove whisper model
    rm -f /opt/homebrew/share/whisper-cpp/ggml-large-v3-turbo.bin 2>/dev/null && ok "Removed whisper model (1.5GB)" || true
else
    skip "Kept brew packages"
fi

echo ""
echo -e "${GREEN}Teardown complete.${NC}"
echo ""
