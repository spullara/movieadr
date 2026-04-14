#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kill any existing processes on our ports
lsof -ti:3001 -ti:5173 | xargs kill -9 2>/dev/null || true
sleep 1

# Activate Python venv
source venv/bin/activate

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
