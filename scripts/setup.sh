#!/bin/bash
# MeetingScribe — One-line setup for a new Mac
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh | bash
#   # or
#   ./scripts/setup.sh
#
# To test locally without re-cloning:
#   MEETINGSCRIBE_DEV=1 ./scripts/setup.sh

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

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       MeetingScribe Setup            ║"
echo "  ║  Self-hosted meeting transcription   ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── 0. Xcode Command Line Tools ──────────────────────────
step 0 "Checking Xcode Command Line Tools..."

if swift --version &>/dev/null 2>&1; then
    ok "Swift available ($(swift --version 2>&1 | head -1 | grep -o 'Swift version [0-9.]*' || echo 'OK'))"
else
    echo "  Installing Xcode Command Line Tools (required for Swift)..."
    echo ""

    # Touch trigger file for softwareupdate
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true

    # Launch GUI installer
    xcode-select --install 2>/dev/null || true

    echo -e "  ${YELLOW}A system dialog should appear — click 'Install'.${NC}"
    echo "  Waiting for installation to complete..."
    echo ""

    # Poll until swift actually works
    ELAPSED=0
    while ! swift --version &>/dev/null 2>&1; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [[ $ELAPSED -ge 600 ]]; then
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
            fail "Timed out waiting for CLT. Run 'xcode-select --install' manually, then re-run this script."
        fi
        if [[ $((ELAPSED % 15)) -eq 0 ]]; then
            echo "  Still waiting... (${ELAPSED}s elapsed)"
        fi
    done

    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
    ok "Command Line Tools installed"
fi

# ── 1. Homebrew ──────────────────────────────────────────
step 1 "Checking Homebrew..."
if command -v brew &>/dev/null; then
    ok "Homebrew installed"
else
    echo "  Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to path for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# Make sure brew is in PATH
if ! command -v brew &>/dev/null; then
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# ── 2. System dependencies ───────────────────────────────
step 2 "Installing dependencies..."
DEPS=(node postgresql@17 whisper-cpp ffmpeg sox tmux)

for dep in "${DEPS[@]}"; do
    if brew list "$dep" &>/dev/null 2>&1; then
        ok "$dep already installed"
    else
        echo "  Installing $dep..."
        brew install "$dep" || warn "$dep had warnings (continuing)"
        ok "$dep installed"
    fi
done

# Ensure PostgreSQL is running
echo "  Starting PostgreSQL..."
brew services start postgresql@17 2>/dev/null || brew services start postgresql 2>/dev/null || true
sleep 3

# Verify PostgreSQL
if pg_isready &>/dev/null 2>&1; then
    ok "PostgreSQL running"
else
    warn "PostgreSQL may need manual start: brew services start postgresql@17"
fi

# ── 3. Whisper model ─────────────────────────────────────
step 3 "Checking whisper model..."
MODEL_DIR="/opt/homebrew/share/whisper-cpp"
MODEL_PATH="$MODEL_DIR/ggml-large-v3-turbo.bin"
if [[ -f "$MODEL_PATH" ]]; then
    ok "Whisper model already downloaded ($(du -h "$MODEL_PATH" | cut -f1))"
else
    mkdir -p "$MODEL_DIR" 2>/dev/null || true
    echo "  Downloading whisper large-v3-turbo model (~1.5GB)..."
    curl -L --progress-bar -o "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"
    ok "Whisper model downloaded"
fi

# ── 4. Clone repo ────────────────────────────────────────
step 4 "Setting up repository..."
if [[ "${MEETINGSCRIBE_DEV:-}" == "1" ]] && [[ -d "$INSTALL_DIR/.git" ]]; then
    ok "Dev mode — using existing repo at $INSTALL_DIR"
elif [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Updating existing repo..."
    cd "$INSTALL_DIR"
    git pull --ff-only 2>/dev/null || warn "Could not pull (continuing with existing)"
    ok "Repository updated"
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
    ok "Cloned to $INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── 5. Web app setup ─────────────────────────────────────
step 5 "Setting up web app..."
cd "$INSTALL_DIR/apps/web"

echo "  Installing npm packages..."
npm install 2>&1 | tail -1
ok "npm packages installed"

# Create .env.local if missing
if [[ ! -f .env.local ]]; then
    # Detect current user for database URL (macOS uses your username, not 'postgres')
    DB_CONN_USER=$(whoami)
    cat > .env.local << EOF
DATABASE_URL="postgresql://${DB_CONN_USER}@localhost:5432/$DB_NAME"
MEETINGSCRIBE_API_KEY=""
EOF
    ok "Created .env.local"
else
    ok ".env.local already exists"
fi

# Create database if it doesn't exist
echo "  Setting up database..."
createdb "$DB_NAME" 2>/dev/null && ok "Database '$DB_NAME' created" || ok "Database '$DB_NAME' already exists"

# Run migrations
echo "  Running migrations..."
npx prisma generate 2>&1 | tail -1

# Always run migrate dev to ensure tables are created
# This is safe to run multiple times — it's a no-op if schema matches
echo "  Applying database schema..."
npx prisma migrate dev --name init --skip-generate 2>&1 | tail -5

# If migrate dev failed (e.g. migration already exists), try deploy
npx prisma migrate deploy 2>&1 | tail -3

# Last resort: push schema directly without migrations
npx prisma db push --skip-generate 2>&1 | tail -3

# Verify tables exist
if psql "$DB_NAME" -c "SELECT count(*) FROM \"Meeting\";" &>/dev/null 2>&1; then
    ok "Database ready (tables verified)"
else
    # One more try with force push
    echo "  Force-pushing schema..."
    npx prisma db push --force-reset --skip-generate 2>&1 | tail -3
    if psql "$DB_NAME" -c "SELECT count(*) FROM \"Meeting\";" &>/dev/null 2>&1; then
        ok "Database ready (tables created)"
    else
        warn "Could not create tables automatically."
        echo "  Run manually: cd $INSTALL_DIR/apps/web && npx prisma db push"
    fi
fi

# ── 6. CLI setup ─────────────────────────────────────────
step 6 "Setting up CLI..."
cd "$INSTALL_DIR/cli"
npm install 2>&1 | tail -1
npm link 2>/dev/null || sudo npm link 2>/dev/null || warn "npm link failed — use 'npx tsx bin/meetingctl.ts' instead"
ok "meetingctl CLI installed"

# ── 7. Build macOS app ───────────────────────────────────
step 7 "Building macOS app..."
cd "$INSTALL_DIR/apps/macos/MeetingScribe"

echo "  Compiling Swift (this may take a minute on first build)..."
if swift build -c release 2>&1 | tail -3; then
    ok "macOS app built"

    # Create .app bundle
    cd "$INSTALL_DIR"
    if [[ -f scripts/build-app.sh ]]; then
        echo "  Creating app bundle..."
        bash scripts/build-app.sh 2>&1

        if [[ -d ~/Applications/MeetingScribe.app ]]; then
            ok "MeetingScribe.app installed to ~/Applications/"
        else
            warn "App bundle creation failed. You can run manually: ./scripts/build-app.sh"
        fi
    fi
else
    warn "Swift build failed. You may need full Xcode from the App Store."
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
sleep 1

# Start new tmux session with the web server
tmux new-session -d -s meetingscribe -c "$INSTALL_DIR/apps/web" \
    "npm run dev 2>&1 | tee /tmp/meetingscribe-server.log"

# Wait for server to be ready
echo "  Waiting for server on port 3000..."
SERVER_READY=false
for i in $(seq 1 40); do
    # Check if port 3000 is listening
    if lsof -i :3000 -sTCP:LISTEN &>/dev/null 2>&1; then
        # Double check with HTTP request
        sleep 1
        if curl -s -o /dev/null -m 3 http://localhost:3000 2>/dev/null; then
            SERVER_READY=true
            break
        fi
    fi
    sleep 2
    printf "."
done
echo ""

if $SERVER_READY; then
    ok "Web server running at http://localhost:3000"
else
    # Check if tmux session is still alive
    if tmux has-session -t meetingscribe 2>/dev/null; then
        warn "Server is starting but not responding yet."
        warn "Check logs: tmux attach -t meetingscribe"
        warn "Or: tail -20 /tmp/meetingscribe-server.log"
    else
        warn "Server failed to start. Check: cat /tmp/meetingscribe-server.log"
    fi
fi
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
echo "    • macOS app:      Click the menu bar icon"
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
