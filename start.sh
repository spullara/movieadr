#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kill any existing processes on our ports
lsof -ti:3001 -ti:5173 | xargs kill -9 2>/dev/null || true
sleep 1

# Activate Python venv
source venv/bin/activate

# Install yt-dlp for YouTube video downloads
echo "Ensuring yt-dlp is installed..."
./venv/bin/pip install -q yt-dlp

# Pre-download Whisper model on first run (with SSL fix for macOS)
echo "Checking Whisper model cache..."
python -c "
import ssl
ssl._create_default_https_context = ssl._create_unverified_context
import whisper
whisper.load_model('large-v3')
print('Whisper model ready.')
"

# Pre-download Demucs model on first run (with SSL fix for macOS)
echo "Pre-downloading Demucs model..."
./venv/bin/python -c "
import ssl
ssl._create_default_https_context = ssl._create_unverified_context
from demucs.pretrained import get_model
get_model('htdemucs')
print('Demucs model ready')
" 2>&1 || echo "Warning: Demucs model pre-download failed (will retry at runtime)"

cleanup() {
  echo ""
  echo "Shutting down..."
  echo "Done."
}

trap cleanup SIGINT SIGTERM EXIT

echo "moviekaraoke is running:"
echo "  Frontend: http://localhost:5173"
echo "  Backend:  http://localhost:3001"
echo ""

npx concurrently --kill-others \
  --names "server,client" \
  --prefix-colors "blue,green" \
  "cd server && npx tsx src/index.ts" \
  "cd client && npx vite --port 5173"
