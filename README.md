# movieadr

A desktop ADR (Automated Dialogue Replacement) recording tool. Import a movie clip, and the app transcribes dialogue with word-level timestamps (Whisper), separates vocals from the soundtrack (Demucs), then presents a teleprompter-style overlay where words scroll right-to-left toward a "now" line at 20% from the left edge. Record your voice over the instrumental track, then export a final video with your recording mixed in.

<!-- TODO: add screenshot -->

## How it works

1. **Import** — Drop in a video file (mp4, mkv, etc.)
2. **Prepare** — Whisper extracts word-level timestamps; Demucs isolates the instrumental track by removing vocals
3. **Record** — Watch the teleprompter overlay with a live waveform, speak your lines in sync
4. **Export** — Produces a new video with your vocal recording mixed over the instrumental audio

## Prerequisites

- Python 3.10+
- ffmpeg
- Node.js 18+
- A microphone

## Getting started

```bash
git clone https://github.com/spullara/movieadr.git
cd movieadr
npm run install:all
```

Set up the Python environment:

```bash
python3 -m venv venv
source venv/bin/activate
pip install openai-whisper demucs
```

Start the app:

```bash
./start.sh
```

`start.sh` activates the venv, pre-downloads the Whisper and Demucs models on first run, then starts both the backend (port 3001) and frontend (port 5173) via `concurrently`.

## Architecture

React + Vite frontend communicating with a Node + Express backend. The backend shells out to Python for ML tasks: Whisper for word-level transcription timestamps and Demucs for vocal/instrumental separation. ffmpeg handles all audio and video processing (extraction, mixing, final export).

~1,963 lines of TypeScript across client, server, and shared packages.

## Tech stack

- TypeScript
- React
- Vite
- Express
- Whisper (word-level transcription)
- Demucs (vocal separation)
- ffmpeg (audio/video processing)
