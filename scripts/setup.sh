#!/bin/bash
# MeetingScribe — One-line setup for a new Mac
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh | bash
#   # or
#   ./scripts/setup.sh
#
# What this does:
#   1. Installs Homebrew (if missing)
#   2. Installs dependencies: node, postgresql, whisper-cpp, ffmpeg, sox, tmux
#   3. Downloads whisper model
#   4. Clones the repo
#   5. Sets up the web app (npm install, database, migrations)
#   6. Sets up the CLI (npm install, npm link)
#   7. Builds the macOS app
#   8. Starts the web server in a tmux session
#   9. Launches MeetingScribe.app

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${BLUE}[$1/10]${NC} $2"; }
ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

REPO_URL="https://github.com/scott-yj-yang/meeting-scribe.git"
INSTALL_DIR="$HOME/Developer/meeting-scribe"
DB_NAME="meetingscribe"
DB_USER="postgres"
DB_PASS="postgres"

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       MeetingScribe Setup            ║"
echo "  ║  Self-hosted meeting transcription   ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. Homebrew ──────────────────────────────────────────
step 1 "Checking Homebrew..."
if command -v brew &>/dev/null; then
    ok "Homebrew installed"
else
    echo "  Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to path for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# ── 2. System dependencies ───────────────────────────────
step 2 "Installing dependencies..."
DEPS=(node postgresql@17 whisper-cpp ffmpeg sox tmux)
for dep in "${DEPS[@]}"; do
    if brew list "$dep" &>/dev/null; then
        ok "$dep already installed"
    else
        echo "  Installing $dep..."
        brew install "$dep" 2>/dev/null
        ok "$dep installed"
    fi
done

# Ensure PostgreSQL is running
if ! brew services list | grep -q "postgresql.*started"; then
    brew services start postgresql@17 2>/dev/null || brew services start postgresql 2>/dev/null || true
    sleep 2
    ok "PostgreSQL started"
else
    ok "PostgreSQL already running"
fi

# ── 3. Whisper model ─────────────────────────────────────
step 3 "Checking whisper model..."
MODEL_PATH="/opt/homebrew/share/whisper-cpp/ggml-large-v3-turbo.bin"
if [[ -f "$MODEL_PATH" ]]; then
    ok "Whisper model already downloaded ($(du -h "$MODEL_PATH" | cut -f1))"
else
    echo "  Downloading whisper large-v3-turbo model (~1.5GB)..."
    curl -L -o "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true" 2>&1 | tail -1
    ok "Whisper model downloaded"
fi

# ── 4. Clone repo ────────────────────────────────────────
step 4 "Setting up repository..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Updating existing repo..."
    cd "$INSTALL_DIR" && git pull --ff-only 2>/dev/null || true
    ok "Repository updated at $INSTALL_DIR"
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
    ok "Cloned to $INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── 5. Web app setup ─────────────────────────────────────
step 5 "Setting up web app..."
cd "$INSTALL_DIR/apps/web"
npm install --silent 2>/dev/null
ok "npm packages installed"

# Create .env.local if missing
if [[ ! -f .env.local ]]; then
    cat > .env.local << EOF
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
MEETINGSCRIBE_API_KEY=""
EOF
    ok "Created .env.local"
fi

# Create database if it doesn't exist
if ! psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    # Create user if needed
    psql postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null | grep -q 1 || \
        createuser -s "$DB_USER" 2>/dev/null || true
    # Set password
    psql postgres -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    createdb -U "$DB_USER" "$DB_NAME" 2>/dev/null || createdb "$DB_NAME" 2>/dev/null || true
    ok "Database created"
else
    ok "Database already exists"
fi

# Run migrations
npx prisma migrate deploy 2>/dev/null || npx prisma migrate dev --name init 2>/dev/null || true
npx prisma generate 2>/dev/null
ok "Database migrated"

# ── 6. CLI setup ─────────────────────────────────────────
step 6 "Setting up CLI..."
cd "$INSTALL_DIR/cli"
npm install --silent 2>/dev/null
npm link 2>/dev/null || true
ok "meetingctl CLI installed"

# ── 7. Build macOS app ───────────────────────────────────
step 7 "Building macOS app..."
cd "$INSTALL_DIR/apps/macos/MeetingScribe"

# Check if Xcode or command line tools are available
if ! xcodebuild -version &>/dev/null 2>&1; then
    warn "Xcode not found. Installing command line tools..."
    xcode-select --install 2>/dev/null || true
    warn "Run this script again after Xcode tools finish installing"
else
    swift build -c release 2>/dev/null
    ok "macOS app built"

    # Create .app bundle
    cd "$INSTALL_DIR"
    if [[ -f scripts/build-app.sh ]]; then
        bash scripts/build-app.sh 2>/dev/null | grep -E "(Built:|Icon)" || true
        ok "MeetingScribe.app installed to ~/Applications/"
    fi
fi

# ── 8. Create output directory ───────────────────────────
step 8 "Creating output directories..."
mkdir -p ~/MeetingScribe
ok "~/MeetingScribe/ ready"

# ── 9. Start web server in tmux ──────────────────────────
step 9 "Starting web server..."
cd "$INSTALL_DIR/apps/web"

# Kill any existing session
tmux kill-session -t meetingscribe 2>/dev/null || true

# Start new tmux session with the web server
tmux new-session -d -s meetingscribe -c "$INSTALL_DIR/apps/web" "npm run dev"
ok "Web server running in tmux session 'meetingscribe'"
echo "  → View logs: tmux attach -t meetingscribe"
echo "  → Stop:      tmux kill-session -t meetingscribe"

# ── 10. Done! ────────────────────────────────────────────
step 10 "Setup complete!"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  MeetingScribe is ready!                                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Quick start:"
echo "    • Web dashboard:  http://localhost:3000"
echo "    • macOS app:      Click the menu bar icon (doc + magnifier)"
echo "    • CLI:            meetingctl --help"
echo ""
echo "  Useful commands:"
echo "    tmux attach -t meetingscribe     # View web server logs"
echo "    meetingctl list                  # List meetings"
echo "    meetingctl summarize <id>        # Summarize with Claude"
echo "    meetingctl chat <id>             # Chat about a meeting"
echo ""
echo "  Files:"
echo "    Recordings:  ~/MeetingScribe/"
echo "    Source:      $INSTALL_DIR/"
echo "    App:         ~/Applications/MeetingScribe.app"
echo ""

# Launch the app if it exists
if [[ -d ~/Applications/MeetingScribe.app ]]; then
    open ~/Applications/MeetingScribe.app
    ok "MeetingScribe.app launched"
fi
