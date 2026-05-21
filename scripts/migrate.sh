#!/bin/bash
# MeetingScribe — Migration from main (full-stack) to feat/native-overhaul
#
# What this removes:
#   - tmux session 'meetingscribe' (old web server)
#   - ~/Applications/MeetingScribe.app and /Applications/MeetingScribe.app (old build)
#   - npm-linked `meetingctl` global symlink
#   - $BREW_PREFIX/bin/meetingscribe-update symlink (points at stale update.sh)
#   - Postgres database `meetingscribe`
#   - ~/Developer/meeting-scribe repo (the source tree from the old install)
#
# What this preserves:
#   - ~/MeetingScribe/        (user recordings — never touched)
#   - whisper-cpp + ffmpeg    (new app still uses them)
#   - node, postgresql@17     (user may use these for other projects)
#   - ~/.zshrc brew shellenv  (harmless to leave)
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/feat/native-overhaul/scripts/migrate.sh)"
#   # or locally:
#   bash scripts/migrate.sh
#   bash scripts/migrate.sh --all    # non-interactive, removes everything migratable

set -u

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
skip() { echo -e "  ${BLUE}-${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
step() { echo -e "\n${BLUE}${BOLD}[$1]${NC} $2"; }

OLD_INSTALL_DIR="$HOME/Developer/meeting-scribe"
DB_NAME="meetingscribe"

if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

ALL=false
if [[ "${1:-}" == "--all" ]]; then ALL=true; fi

confirm() {
    if $ALL; then return 0; fi
    if [[ ! -t 0 ]]; then
        warn "Non-interactive shell — skipping: $1"
        return 1
    fi
    read -p "  $1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

echo -e "${YELLOW}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  MeetingScribe Migration                          ║"
echo "  ║  main (Postgres + Next.js) → native-overhaul     ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ ! -d "$OLD_INSTALL_DIR/apps/web" ]] && \
   ! command -v meetingscribe-update &>/dev/null && \
   ! tmux has-session -t meetingscribe 2>/dev/null; then
    echo "  No old MeetingScribe install detected. Nothing to migrate."
    echo "  Proceed directly to the new native install."
    exit 0
fi

echo "  Detected old install. Recordings at ~/MeetingScribe/ will NOT be touched."
echo ""

step "1/6" "Stopping old web server..."
if tmux has-session -t meetingscribe 2>/dev/null; then
    tmux kill-session -t meetingscribe
    ok "Killed tmux session 'meetingscribe'"
else
    skip "No tmux session running"
fi

for port in 3000 3001; do
    PIDS=$(lsof -ti :"$port" 2>/dev/null || true)
    if [[ -n "$PIDS" ]]; then
        PNAMES=$(ps -p "$(echo "$PIDS" | tr '\n' ',' | sed 's/,$//')" -o comm= 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if confirm "Port $port held by [$PNAMES] (PIDs: $(echo "$PIDS" | tr '\n' ' ')). Kill?"; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
            ok "Freed port $port"
        else
            skip "Left port $port alone"
        fi
    fi
done

step "2/6" "Removing old MeetingScribe.app..."

osascript -e 'tell application "MeetingScribe" to quit' 2>/dev/null || true
sleep 1

REMOVED_APP=false
for APP_PATH in "$HOME/Applications/MeetingScribe.app" "/Applications/MeetingScribe.app"; do
    if [[ -d "$APP_PATH" ]]; then
        if confirm "Remove $APP_PATH?"; then
            rm -rf "$APP_PATH"
            ok "Removed $APP_PATH"
            REMOVED_APP=true
        else
            skip "Kept $APP_PATH"
        fi
    fi
done
if ! $REMOVED_APP && [[ ! -d "$HOME/Applications/MeetingScribe.app" ]] && [[ ! -d "/Applications/MeetingScribe.app" ]]; then
    skip "No MeetingScribe.app installed"
fi
