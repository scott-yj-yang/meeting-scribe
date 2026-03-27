#!/bin/bash
# MeetingScribe — One-line setup for a new Mac
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/main/scripts/setup.sh)"
#   # or locally:
#   MEETINGSCRIBE_DEV=1 bash scripts/setup.sh
#
# Tested on: macOS Sequoia 15.x, macOS Tahoe 26.x (Apple Silicon + Intel)

# ── Helpers ──────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_STEPS=10
step() { echo -e "\n${BLUE}${BOLD}[$1/$TOTAL_STEPS]${NC} $2"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "  ${BLUE}→${NC} $1"; }

REPO_URL="https://github.com/scott-yj-yang/meeting-scribe.git"
INSTALL_DIR="$HOME/Developer/meeting-scribe"
DB_NAME="meetingscribe"

# Detect architecture for Homebrew paths
if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║       MeetingScribe Setup            ║"
echo "  ║  Self-hosted meeting transcription   ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo "  Architecture: $(uname -m) | macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
echo ""

# ── 0. Xcode Command Line Tools ─────────────────────────
step 0 "Checking Xcode Command Line Tools..."

if swift --version &>/dev/null 2>&1; then
    ok "Swift available"
else
    echo "  Xcode Command Line Tools required for Swift compilation."
    echo ""

    # Trigger install
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
    xcode-select --install 2>/dev/null || true

    echo -e "  ${YELLOW}${BOLD}ACTION REQUIRED:${NC} A system dialog should appear."
    echo -e "  ${YELLOW}Click 'Install' and wait for it to finish.${NC}"
    echo ""

    ELAPSED=0
    while ! swift --version &>/dev/null 2>&1; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [[ $ELAPSED -ge 900 ]]; then
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
            fail "Timed out (15 min). Run 'xcode-select --install' manually, then re-run this script."
        fi
        if [[ $((ELAPSED % 30)) -eq 0 ]]; then
            echo "  Waiting for CLT installation... (${ELAPSED}s)"
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
    echo "  Installing Homebrew (may ask for your password)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null || fail "Homebrew installation failed"
    ok "Homebrew installed"
fi

# Ensure brew is in PATH for this session (critical after fresh install)
if ! command -v brew &>/dev/null; then
    if [[ -f "$BREW_PREFIX/bin/brew" ]]; then
        eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    else
        fail "Homebrew installed but not found in PATH. Close and reopen Terminal, then re-run."
    fi
fi

# Also ensure brew packages are in PATH
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"

# ── 2. System dependencies ───────────────────────────────
step 2 "Installing dependencies..."
DEPS=(node postgresql@17 whisper-cpp ffmpeg sox tmux git)

for dep in "${DEPS[@]}"; do
    if brew list "$dep" &>/dev/null 2>&1; then
        ok "$dep already installed"
    else
        echo "  Installing $dep..."
        brew install "$dep" </dev/null || true
        # Verify it actually installed
        if brew list "$dep" &>/dev/null 2>&1; then
            ok "$dep installed"
        else
            warn "$dep may not have installed correctly (continuing)"
        fi
    fi
done

# Ensure node/npm are in PATH (nvm or brew)
if ! command -v node &>/dev/null; then
    # Try brew's node
    export PATH="$BREW_PREFIX/opt/node/bin:$PATH"
    if ! command -v node &>/dev/null; then
        fail "Node.js not found in PATH after install. Try: brew link node"
    fi
fi
ok "Node $(node --version) | npm $(npm --version)"

# Ensure PostgreSQL binaries are in PATH
export PATH="$BREW_PREFIX/opt/postgresql@17/bin:$PATH"

# Start PostgreSQL
echo "  Starting PostgreSQL..."
brew services start postgresql@17 2>/dev/null || brew services start postgresql 2>/dev/null || true
sleep 3

# Wait for PostgreSQL to be ready (it can take a moment after first install)
PG_READY=false
for i in $(seq 1 10); do
    if pg_isready &>/dev/null 2>&1; then
        PG_READY=true
        break
    fi
    sleep 2
done

if $PG_READY; then
    ok "PostgreSQL running"
else
    warn "PostgreSQL not responding. Trying to initialize..."
    # On fresh install, the database cluster might not exist
    initdb "$BREW_PREFIX/var/postgresql@17" 2>/dev/null || true
    brew services restart postgresql@17 2>/dev/null || true
    sleep 3
    if pg_isready &>/dev/null 2>&1; then
        ok "PostgreSQL running (after init)"
    else
        warn "PostgreSQL still not running. You may need to start it manually:"
        info "brew services start postgresql@17"
    fi
fi

# ── 3. Whisper model ─────────────────────────────────────
step 3 "Checking whisper model..."
MODEL_DIR="$BREW_PREFIX/share/whisper-cpp"
MODEL_PATH="$MODEL_DIR/ggml-large-v3-turbo.bin"

if [[ -f "$MODEL_PATH" ]]; then
    FILE_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null || echo "0")
    if [[ "$FILE_SIZE" -gt 1000000000 ]]; then
        ok "Whisper model ready ($(du -h "$MODEL_PATH" | cut -f1))"
    else
        warn "Model file seems truncated (${FILE_SIZE} bytes). Re-downloading..."
        rm -f "$MODEL_PATH"
    fi
fi

if [[ ! -f "$MODEL_PATH" ]]; then
    mkdir -p "$MODEL_DIR" 2>/dev/null || sudo mkdir -p "$MODEL_DIR" && sudo chown "$(whoami)" "$MODEL_DIR"
    echo "  Downloading whisper large-v3-turbo model (~1.5GB)..."
    echo "  This may take a few minutes depending on your connection."
    if curl -L --progress-bar --retry 3 --retry-delay 5 -o "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"; then
        # Verify download
        FILE_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || echo "0")
        if [[ "$FILE_SIZE" -gt 1000000000 ]]; then
            ok "Whisper model downloaded"
        else
            rm -f "$MODEL_PATH"
            warn "Download seems incomplete. Re-run setup or download manually."
        fi
    else
        warn "Download failed. You can download later:"
        info "curl -L -o $MODEL_PATH 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin'"
    fi
fi

# ── 4. Clone repo ────────────────────────────────────────
step 4 "Setting up repository..."

if [[ "${MEETINGSCRIBE_DEV:-}" == "1" ]] && [[ -d "$INSTALL_DIR/.git" ]]; then
    ok "Dev mode — using existing repo"
elif [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Updating existing repo..."
    cd "$INSTALL_DIR"
    git pull --ff-only 2>/dev/null || warn "Could not pull (continuing with existing)"
    ok "Repository updated"
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    if git clone "$REPO_URL" "$INSTALL_DIR" </dev/null; then
        ok "Cloned to $INSTALL_DIR"
    else
        fail "Failed to clone repository. Check your internet connection."
    fi
fi
cd "$INSTALL_DIR"

# ── 5. Web app setup ─────────────────────────────────────
step 5 "Setting up web app..."
cd "$INSTALL_DIR/apps/web"

echo "  Installing npm packages..."
npm install </dev/null 2>&1 | tail -3
ok "npm packages installed"

# Create env files — detect database connection
DB_CONN_USER=$(whoami)
DB_URL="postgresql://${DB_CONN_USER}@localhost:5432/$DB_NAME"

# Test if PostgreSQL needs a password or different connection
if ! psql -U "$DB_CONN_USER" -d postgres -c "SELECT 1" &>/dev/null 2>&1; then
    # Try without specifying user
    if psql -d postgres -c "SELECT 1" &>/dev/null 2>&1; then
        DB_URL="postgresql://localhost:5432/$DB_NAME"
    else
        warn "Cannot connect to PostgreSQL. Using default connection string."
    fi
fi

if [[ ! -f .env ]]; then
    echo "DATABASE_URL=\"$DB_URL\"" > .env
    ok "Created .env"
fi
if [[ ! -f .env.local ]]; then
    cat > .env.local << EOF
DATABASE_URL="$DB_URL"
MEETINGSCRIBE_API_KEY=""
EOF
    ok "Created .env.local"
else
    ok ".env.local already exists"
fi

# Create database
echo "  Setting up database..."
createdb "$DB_NAME" 2>/dev/null && ok "Database created" || ok "Database already exists"

# Run migrations
export DATABASE_URL="$DB_URL"

echo "  Running Prisma generate..."
npx prisma generate </dev/null 2>&1 | tail -1

echo "  Applying database schema..."
DATABASE_URL="$DB_URL" npx prisma db push --accept-data-loss </dev/null 2>&1 | tail -3
PUSH_EXIT=${PIPESTATUS[0]}

if [[ "$PUSH_EXIT" -ne 0 ]]; then
    echo "  Trying migrate dev..."
    DATABASE_URL="$DB_URL" npx prisma migrate dev --name init --skip-generate </dev/null 2>&1 | tail -5
fi

# Verify — try querying the table
if psql "$DB_NAME" -c "SELECT count(*) FROM \"Meeting\";" &>/dev/null 2>&1; then
    ok "Database ready (tables verified)"
elif psql -U "$DB_CONN_USER" "$DB_NAME" -c "SELECT count(*) FROM \"Meeting\";" &>/dev/null 2>&1; then
    ok "Database ready (tables verified)"
else
    warn "Could not verify tables. If the web app shows errors, run:"
    info "cd $INSTALL_DIR/apps/web && DATABASE_URL=\"$DB_URL\" npx prisma db push"
fi

# ── 6. CLI setup ─────────────────────────────────────────
step 6 "Setting up CLI..."
cd "$INSTALL_DIR/cli"

echo "  Installing CLI packages..."
npm install </dev/null 2>&1 | tail -1

# npm link can fail in various ways
if npm link 2>/dev/null; then
    ok "meetingctl CLI linked globally"
elif sudo npm link 2>/dev/null; then
    ok "meetingctl CLI linked globally (with sudo)"
else
    warn "npm link failed. Use this instead:"
    info "cd $INSTALL_DIR/cli && npx tsx bin/meetingctl.ts"
fi

# ── 7. Build macOS app ───────────────────────────────────
step 7 "Building macOS app..."
cd "$INSTALL_DIR/apps/macos/MeetingScribe"

echo "  Compiling Swift (first build takes 1-2 minutes)..."

# Capture both stdout and exit code
BUILD_OUTPUT=$(swift build -c release </dev/null 2>&1)
BUILD_EXIT=$?

if [[ $BUILD_EXIT -eq 0 ]]; then
    ok "macOS app compiled"

    # Create .app bundle
    cd "$INSTALL_DIR"
    mkdir -p ~/Applications
    echo "  Creating app bundle..."

    if bash scripts/build-app.sh 2>&1 | tail -5; then
        if [[ -d ~/Applications/MeetingScribe.app ]]; then
            ok "MeetingScribe.app → ~/Applications/"
        else
            warn "App bundle not created. Run manually: bash scripts/build-app.sh"
        fi
    else
        warn "App bundle creation failed. The CLI and web app still work."
    fi
else
    echo "$BUILD_OUTPUT" | tail -10
    warn "Swift build failed. The web app and CLI still work without the macOS app."
    warn "To retry: cd $INSTALL_DIR/apps/macos/MeetingScribe && swift build -c release"
fi

# ── 8. Create output directory ───────────────────────────
step 8 "Creating output directories..."
mkdir -p ~/MeetingScribe
mkdir -p ~/Applications 2>/dev/null || true
ok "~/MeetingScribe/ ready"

# ── 9. Start services ────────────────────────────────────
step 9 "Starting services..."

# Install terminal server deps (node-pty may fail on some systems — that's OK)
echo "  Installing terminal server dependencies..."
cd "$INSTALL_DIR/scripts"
if [[ -f package.json ]]; then
    npm install </dev/null 2>&1 | tail -1
    if [[ -d node_modules/node-pty ]]; then
        ok "Terminal server dependencies ready"
    else
        warn "node-pty failed to install (web terminal won't work, everything else will)"
    fi
fi

# Kill anything on our ports
lsof -ti :3000 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti :3001 2>/dev/null | xargs kill -9 2>/dev/null || true

# Kill old tmux session
tmux kill-session -t meetingscribe 2>/dev/null || true
sleep 1

# Start Next.js web server
cd "$INSTALL_DIR/apps/web"
tmux new-session -d -s meetingscribe -n web -c "$INSTALL_DIR/apps/web" \
    "export DATABASE_URL=\"$DB_URL\"; npm run dev 2>&1 | tee /tmp/meetingscribe-server.log"

# Start terminal WebSocket server (only if node-pty installed)
if [[ -d "$INSTALL_DIR/scripts/node_modules/node-pty" ]]; then
    tmux new-window -t meetingscribe -n terminal -c "$INSTALL_DIR/scripts" \
        "node terminal-server.js 2>&1 | tee /tmp/meetingscribe-terminal.log"
    ok "Terminal server starting on ws://localhost:3001"
fi

# Wait for web server
echo "  Waiting for web server..."
SERVER_READY=false
for i in $(seq 1 45); do
    if curl -s -o /dev/null -m 2 http://localhost:3000 2>/dev/null; then
        SERVER_READY=true
        break
    fi
    sleep 2
    printf "."
done
echo ""

if $SERVER_READY; then
    ok "Web server running at http://localhost:3000"
else
    if tmux has-session -t meetingscribe 2>/dev/null; then
        warn "Server still starting. Give it another minute, then check:"
        info "tmux attach -t meetingscribe"
        info "cat /tmp/meetingscribe-server.log"
    else
        warn "Server failed to start."
        info "Try manually: cd $INSTALL_DIR/apps/web && npm run dev"
    fi
fi

# ── 10. Done! ────────────────────────────────────────────
step 10 "Setup complete!"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  MeetingScribe is ready!                                ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Quick start:"
echo "    • Web dashboard:  http://localhost:3000"
if [[ -d ~/Applications/MeetingScribe.app ]]; then
echo "    • macOS app:      Click the menu bar icon"
fi
echo "    • CLI:            meetingctl --help"
echo ""
echo "  Services:"
echo "    tmux attach -t meetingscribe     # View server logs"
echo "    tmux kill-session -t meetingscribe  # Stop everything"
echo ""
echo "  Files:"
echo "    Recordings:  ~/MeetingScribe/"
echo "    Source:      $INSTALL_DIR/"
if [[ -d ~/Applications/MeetingScribe.app ]]; then
echo "    App:         ~/Applications/MeetingScribe.app"
fi
echo ""

# Add brew to shell profile if not already there (for future terminals)
SHELL_RC="$HOME/.zshrc"
if [[ -f "$HOME/.bashrc" ]] && [[ ! -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
fi
if [[ -f "$SHELL_RC" ]] && ! grep -q "brew shellenv" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Homebrew (added by MeetingScribe setup)" >> "$SHELL_RC"
    echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >> "$SHELL_RC"
    ok "Added Homebrew to $SHELL_RC for future terminals"
fi

# Launch app + open browser
if $SERVER_READY; then
    open http://localhost:3000 2>/dev/null || true
fi
if [[ -d ~/Applications/MeetingScribe.app ]]; then
    open ~/Applications/MeetingScribe.app 2>/dev/null || true
    ok "MeetingScribe.app launched"
fi
