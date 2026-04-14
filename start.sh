#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate Python venv
source venv/bin/activate

cleanup() {
  echo ""
  echo "Shutting down..."
  # Kill child processes
  [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
  [[ -n "${CLIENT_PID:-}" ]] && kill "$CLIENT_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  wait "$CLIENT_PID" 2>/dev/null || true
  echo "Done."
}

trap cleanup SIGINT SIGTERM EXIT

# Start backend
echo "Starting server on port 3001..."
cd server && npx tsx src/index.ts &
SERVER_PID=$!
cd "$SCRIPT_DIR"

# Start frontend
echo "Starting client on port 5173..."
cd client && npx vite --port 5173 &
CLIENT_PID=$!
cd "$SCRIPT_DIR"

echo ""
echo "moviekaraoke is running:"
echo "  Frontend: http://localhost:5173"
echo "  Backend:  http://localhost:3001"
echo ""
echo "Press Ctrl+C to stop."

# Wait for either to exit
wait -n "$SERVER_PID" "$CLIENT_PID" 2>/dev/null || true
