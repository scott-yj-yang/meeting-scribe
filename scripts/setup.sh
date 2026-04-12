#!/usr/bin/env bash
# MeetingScribe — One-command setup for a new Mac
#
# Usage:
#   bash scripts/setup.sh
#
# What it does:
#   1. Installs Homebrew (if missing)
#   2. Installs whisper-cpp + ffmpeg via Homebrew
#   3. Downloads the whisper large-v3-turbo model (~1.5 GB)
#   4. Builds the Swift macOS app into a .app bundle
#   5. Optionally installs a summarization provider (Claude CLI or Ollama)
#
# After setup, run:
#   open apps/macos/MeetingScribe/.build/arm64-apple-macosx/debug/MeetingScribe.app

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_STEPS=5
step() { echo -e "\n${BLUE}${BOLD}[$1/$TOTAL_STEPS]${NC} $2"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
info() { echo -e "  ${BLUE}→${NC} $1"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Step 1: Homebrew ─────────────────────────────────────
step 1 "Checking Homebrew"
if command -v brew >/dev/null 2>&1; then
    ok "Homebrew installed"
else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Activate for this session
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# ── Step 2: whisper-cpp + ffmpeg ─────────────────────────
step 2 "Installing whisper-cpp and ffmpeg"
for pkg in whisper-cpp ffmpeg; do
    if brew list "$pkg" >/dev/null 2>&1; then
        ok "$pkg already installed"
    else
        info "Installing $pkg..."
        brew install "$pkg"
        ok "$pkg installed"
    fi
done

# ── Step 3: Whisper model ────────────────────────────────
step 3 "Downloading whisper model"
MODEL_NAME="${WHISPER_MODEL:-ggml-large-v3-turbo.bin}"
# Find the whisper-cpp share directory (works on both Apple Silicon and Intel)
WHISPER_SHARE="$(brew --prefix whisper-cpp)/share/whisper-cpp"
MODEL_PATH="$WHISPER_SHARE/$MODEL_NAME"

if [ -f "$MODEL_PATH" ]; then
    ok "Model already present: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"
else
    info "Downloading $MODEL_NAME (~1.5 GB)..."
    MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"
    curl -L --progress-bar -o "$MODEL_PATH" "$MODEL_URL"
    ok "Model downloaded: $MODEL_PATH"
fi

# Also grab the Silero VAD model for hallucination filtering
VAD_PATH="$WHISPER_SHARE/silero-vad.onnx"
if [ -f "$VAD_PATH" ]; then
    ok "Silero VAD model present"
else
    info "Downloading Silero VAD model..."
    curl -L --progress-bar -o "$VAD_PATH" \
      "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    ok "VAD model downloaded"
fi

# ── Step 4: Build the Swift app ──────────────────────────
step 4 "Building MeetingScribe.app"
cd "$REPO_ROOT/apps/macos/MeetingScribe"
if [ -f build-app.sh ]; then
    chmod +x build-app.sh
    ./build-app.sh debug
    ok "App built"
else
    info "build-app.sh not found, falling back to swift build..."
    swift build
    ok "Swift build complete (run via 'swift run MeetingScribe')"
fi

# ── Step 5: Optional summarization provider ──────────────
step 5 "Summarization provider (optional)"
echo ""
echo "  MeetingScribe can summarize transcripts with either:"
echo ""
echo "    1) Claude CLI  — cloud-based, needs Anthropic API key"
echo "       Install: npm install -g @anthropic-ai/claude-code"
echo ""
echo "    2) Ollama      — fully local, no API key, ~2 GB model download"
echo "       Install: bash $REPO_ROOT/scripts/install-ollama.sh"
echo ""
echo "    3) Skip        — transcription works without summarization"
echo ""

# Auto-detect what's already installed
if command -v claude >/dev/null 2>&1; then
    ok "Claude CLI already installed ($(which claude))"
fi
if command -v ollama >/dev/null 2>&1; then
    ok "Ollama already installed ($(ollama --version 2>/dev/null || echo 'installed'))"
fi

if [ -t 0 ]; then
    # Interactive terminal — ask
    echo -n "  Install now? [1/2/3/skip]: "
    read -r choice
    case "$choice" in
        1)
            if command -v npm >/dev/null 2>&1; then
                npm install -g @anthropic-ai/claude-code
                ok "Claude CLI installed"
            else
                warn "npm not found. Install Node.js first, then: npm install -g @anthropic-ai/claude-code"
            fi
            ;;
        2)
            bash "$REPO_ROOT/scripts/install-ollama.sh"
            ;;
        *)
            info "Skipped — you can install later from Settings (Cmd-,)"
            ;;
    esac
else
    info "Non-interactive — skipping provider install. Run one of the commands above manually."
fi

# ── Done ─────────────────────────────────────────────────
APP_PATH="$(find "$REPO_ROOT/apps/macos/MeetingScribe/.build" -name "MeetingScribe.app" -maxdepth 4 2>/dev/null | head -1)"
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
if [ -n "$APP_PATH" ]; then
    echo -e "  Launch:   ${BOLD}open $APP_PATH${NC}"
else
    echo -e "  Launch:   ${BOLD}cd apps/macos/MeetingScribe && swift run MeetingScribe${NC}"
fi
echo -e "  Settings: ${BOLD}Cmd-,${NC} in the app to pick Claude or Ollama"
echo -e "  CLI:      ${BOLD}cd cli && npm install && npx tsx bin/meetingctl.ts list${NC}"
echo ""
