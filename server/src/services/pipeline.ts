import { spawn } from 'child_process';
import path from 'path';
import { writeFile } from 'fs/promises';
import type { ProjectEntry } from './projects.js';
import { updateProjectStatus } from './projects.js';

function run(cmd: string, args: string[], cwd?: string): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { cwd });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    proc.stdout.on('data', (d) => stdout.push(d));
    proc.stderr.on('data', (d) => stderr.push(d));
    proc.on('close', (code) => {
      const result = {
        stdout: Buffer.concat(stdout).toString(),
        stderr: Buffer.concat(stderr).toString(),
      };
      if (code !== 0) {
        const err = new Error(`${cmd} exited with code ${code}: ${result.stderr}`);
        (err as any).stdout = result.stdout;
        (err as any).stderr = result.stderr;
        reject(err);
      } else {
        resolve(result);
      }
    });
    proc.on('error', reject);
  });
}

/** Step 1: Extract audio from video using ffmpeg */
async function extractAudio(project: ProjectEntry): Promise<string> {
  const outputPath = path.join(project.projectDir, 'audio.wav');
  await run('ffmpeg', [
    '-i', project.videoPath,
    '-vn',                    // no video
    '-acodec', 'pcm_s16le',  // 16-bit PCM
    '-ar', '16000',           // 16kHz for Whisper compatibility
    '-ac', '1',               // mono
    '-y',                     // overwrite
    outputPath,
  ]);
  return outputPath;
}

/** Step 2: Run Whisper for word-level timestamps */
async function runWhisper(project: ProjectEntry, audioPath: string): Promise<void> {
  const outputPath = path.join(project.projectDir, 'word_timestamps.json');
  const scriptPath = path.join(project.projectDir, '_whisper_script.py');

  // Write a small Python script that runs Whisper and outputs JSON
  const script = `
import json, sys
import whisper

model = whisper.load_model("base")
result = model.transcribe(sys.argv[1], word_timestamps=True)

words = []
for segment in result["segments"]:
    for w in segment.get("words", []):
        words.append({"word": w["word"].strip(), "start": round(w["start"], 3), "end": round(w["end"], 3)})

with open(sys.argv[2], "w") as f:
    json.dump({"words": words}, f, indent=2)
`;

  await writeFile(scriptPath, script);
  await run('python3', [scriptPath, audioPath, outputPath]);
}

/** Step 3: Run Demucs for vocal separation, produce instrumental mix */
async function runDemucs(project: ProjectEntry): Promise<void> {
  const audioPath = path.join(project.projectDir, 'audio.wav');
  // Need full-quality audio for Demucs (44.1kHz stereo), re-extract
  const fullAudioPath = path.join(project.projectDir, 'audio_full.wav');
  await run('ffmpeg', [
    '-i', project.videoPath,
    '-vn', '-acodec', 'pcm_s16le', '-ar', '44100', '-ac', '2', '-y',
    fullAudioPath,
  ]);

  // Run Demucs
  await run('python3', [
    '-m', 'demucs',
    '--two-stems', 'vocals',   // only separate vocals vs rest
    '-n', 'htdemucs',
    '-o', project.projectDir,
    fullAudioPath,
  ]);

  // Demucs outputs to <projectDir>/htdemucs/audio_full/no_vocals.wav
  const demucsOutput = path.join(project.projectDir, 'htdemucs', 'audio_full', 'no_vocals.wav');
  const instrumentalPath = path.join(project.projectDir, 'instrumental.wav');

  // Copy demucs output to our expected location
  await run('cp', [demucsOutput, instrumentalPath]);
}

/** Step 4: Generate waveform peaks using ffmpeg */
async function generateWaveformPeaks(project: ProjectEntry): Promise<void> {
  const audioPath = path.join(project.projectDir, 'audio.wav');
  const outputPath = path.join(project.projectDir, 'waveform_peaks.json');

  // Use a Python script to read WAV and compute peaks
  const scriptPath = path.join(project.projectDir, '_waveform_script.py');
  const script = `
import json, struct, sys

audio_path = sys.argv[1]
output_path = sys.argv[2]
samples_per_peak = 800  # ~50 peaks per second at 16kHz

with open(audio_path, "rb") as f:
    # Skip WAV header (44 bytes)
    header = f.read(44)
    data = f.read()

samples = struct.unpack(f"<{len(data)//2}h", data)
peaks = []
for i in range(0, len(samples), samples_per_peak):
    chunk = samples[i:i+samples_per_peak]
    if chunk:
        peak = max(abs(s) for s in chunk) / 32768.0
        peaks.append(round(peak, 4))

with open(output_path, "w") as f:
    json.dump({"peaks": peaks, "sampleRate": 16000, "samplesPerPeak": samples_per_peak}, f)
`;

  await writeFile(scriptPath, script);
  await run('python3', [scriptPath, audioPath, outputPath]);
}

/** Run the full preparation pipeline for a project */
export async function runPipeline(project: ProjectEntry): Promise<void> {
  try {
    // Step 1: Extract audio
    updateProjectStatus(project.id, 'extracting_audio', 10);
    const audioPath = await extractAudio(project);
    updateProjectStatus(project.id, 'extracting_audio', 25);

    // Step 2: Whisper transcription
    updateProjectStatus(project.id, 'transcribing', 30);
    await runWhisper(project, audioPath);
    updateProjectStatus(project.id, 'transcribing', 50);

    // Step 3: Demucs vocal separation
    updateProjectStatus(project.id, 'separating_vocals', 55);
    await runDemucs(project);
    updateProjectStatus(project.id, 'separating_vocals', 80);

    // Step 4: Waveform peaks
    updateProjectStatus(project.id, 'generating_waveform', 85);
    await generateWaveformPeaks(project);
    updateProjectStatus(project.id, 'generating_waveform', 95);

    // Done
    updateProjectStatus(project.id, 'ready', 100);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    updateProjectStatus(project.id, 'error', project.progress, message);
  }
}
