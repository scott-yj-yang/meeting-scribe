#!/usr/bin/env bash
set -euo pipefail

echo "MeetingScribe Ollama installer"
echo "==============================="

# 1. Check if Ollama is installed
if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama not found. Installing via Homebrew..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "Error: Homebrew is required. Install from https://brew.sh first."
        exit 1
    fi
    brew install ollama
else
    echo "Ollama already installed: $(ollama --version 2>/dev/null || true)"
fi

# 2. Start the Ollama server if not running
if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Starting Ollama server in background..."
    # macOS: use launchd via brew services if available
    if command -v brew >/dev/null 2>&1 && brew services list | grep -q ollama; then
        brew services start ollama || true
    else
        nohup ollama serve >/tmp/ollama.log 2>&1 &
        sleep 2
    fi
fi

# Wait for server
for i in 1 2 3 4 5; do
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "Ollama server reachable."
        break
    fi
    echo "Waiting for Ollama server... ($i/5)"
    sleep 1
done

if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Error: Ollama server not reachable at http://localhost:11434"
    exit 1
fi

# 3. Pull a default model
DEFAULT_MODEL="${OLLAMA_MODEL:-llama3.2}"
echo "Pulling default model: $DEFAULT_MODEL (this may take a while)..."
ollama pull "$DEFAULT_MODEL"

echo ""
echo "Done. In MeetingScribe, open Settings (Cmd-,), pick 'Ollama (local)',"
echo "endpoint http://localhost:11434, model $DEFAULT_MODEL."
