#!/bin/bash
# MeetingScribe — Update to latest version
#
# Usage:
#   meetingscribe-update         (if installed globally)
#   bash scripts/update.sh       (from repo root)
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/update.sh)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }

INSTALL_DIR="$HOME/Developer/meeting-scribe"

if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$BREW_PREFIX/opt/postgresql@17/bin:$PATH"

echo ""
echo -e "${BLUE}  MeetingScribe Update${NC}"
echo ""

# Check repo exists
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${RED}  MeetingScribe not found at $INSTALL_DIR${NC}"
    echo "  Run the full setup instead:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh)"'
    exit 1
fi

cd "$INSTALL_DIR"

# 1. Pull latest
echo "  Pulling latest code..."
BEFORE=$(git rev-parse HEAD 2>/dev/null)
git pull --ff-only </dev/null 2>&1
AFTER=$(git rev-parse HEAD 2>/dev/null)

if [[ "$BEFORE" == "$AFTER" ]]; then
    ok "Already up to date"
else
    COMMITS=$(git log --oneline "$BEFORE..$AFTER" 2>/dev/null | wc -l | tr -d ' ')
    ok "Updated ($COMMITS new commits)"
    echo ""
    echo "  Recent changes:"
    git log --oneline "$BEFORE..$AFTER" 2>/dev/null | head -10 | sed 's/^/    /'
    echo ""
fi

# 2. Update web app
echo "  Updating web app..."
cd "$INSTALL_DIR/apps/web"
npm install </dev/null 2>&1 | tail -1

# Re-run prisma generate in case schema changed
DB_CONN_USER=$(whoami)
DB_URL="postgresql://${DB_CONN_USER}@localhost:5432/meetingscribe"
export DATABASE_URL="$DB_URL"

npx prisma generate </dev/null 2>&1 | tail -1
DATABASE_URL="$DB_URL" npx prisma db push --accept-data-loss </dev/null 2>&1 | tail -1
ok "Web app updated"

# 3. Update CLI
echo "  Updating CLI..."
cd "$INSTALL_DIR/cli"
npm install </dev/null 2>&1 | tail -1
npm link </dev/null 2>/dev/null || true
ok "CLI updated"

# 4. Rebuild macOS app
echo "  Rebuilding macOS app..."
cd "$INSTALL_DIR/apps/macos/MeetingScribe"
if swift build -c release </dev/null 2>&1 | tail -1; then
    cd "$INSTALL_DIR"
    bash scripts/build-app.sh </dev/null 2>&1 | tail -3
    if [[ -d ~/Applications/MeetingScribe.app ]]; then
        ok "macOS app rebuilt"
    else
        warn "App bundle failed — run: bash scripts/build-app.sh"
    fi
else
    warn "Swift build failed"
fi

# 5. Update terminal server
echo "  Updating terminal server..."
cd "$INSTALL_DIR/scripts"
if [[ -f package.json ]]; then
    npm install </dev/null 2>&1 | tail -1
    ok "Terminal server updated"
fi

# 6. Restart services
echo "  Restarting services..."
tmux kill-session -t meetingscribe 2>/dev/null || true
sleep 1

cd "$INSTALL_DIR/apps/web"
tmux new-session -d -s meetingscribe -n web -c "$INSTALL_DIR/apps/web" \
    "export DATABASE_URL=\"$DB_URL\"; npm run dev 2>&1 | tee /tmp/meetingscribe-server.log"

if [[ -d "$INSTALL_DIR/scripts/node_modules/node-pty" ]]; then
    tmux new-window -t meetingscribe -n terminal -c "$INSTALL_DIR/scripts" \
        "node terminal-server.js 2>&1 | tee /tmp/meetingscribe-terminal.log"
fi

# Wait for server
for i in $(seq 1 20); do
    if curl -s -o /dev/null -m 2 http://localhost:3000 2>/dev/null; then
        ok "Web server running at http://localhost:3000"
        break
    fi
    sleep 2
    printf "."
done
echo ""

# Relaunch app
if [[ -d ~/Applications/MeetingScribe.app ]]; then
    osascript -e 'quit app "MeetingScribe"' 2>/dev/null || true
    sleep 1
    open ~/Applications/MeetingScribe.app 2>/dev/null
    ok "MeetingScribe.app relaunched"
fi

echo ""
echo -e "${GREEN}  Update complete!${NC}"
echo ""
