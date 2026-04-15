import { randomUUID } from 'crypto';
import { spawn } from 'child_process';
import { access } from 'fs/promises';
import path from 'path';
import { EventEmitter } from 'events';
import type { ExportStatus } from '@moviekaraoke/shared';
import type { ProjectEntry } from './projects.js';

export interface ExportEntry {
  id: string;
  projectId: string;
  takeId: string;
  status: ExportStatus;
  progress: number;
  fileName?: string;
  filePath?: string;
  error?: string;
  createdAt: string;
}

const exports = new Map<string, ExportEntry>();
export const exportEvents = new EventEmitter();

function run(cmd: string, args: string[]): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args);
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
        reject(err);
      } else {
        resolve(result);
      }
    });
    proc.on('error', reject);
  });
}

function updateExportStatus(id: string, status: ExportStatus, progress: number, error?: string): void {
  const exp = exports.get(id);
  if (!exp) return;
  exp.status = status;
  exp.progress = progress;
  if (error) exp.error = error;
  exportEvents.emit('progress', {
    exportId: id,
    projectId: exp.projectId,
    status,
    progress,
    error,
  });
}

export function getExport(id: string): ExportEntry | undefined {
  return exports.get(id);
}

export function listExports(projectId: string): ExportEntry[] {
  return Array.from(exports.values()).filter((e) => e.projectId === projectId);
}

/** Start an export: mix take audio with instrumental, mux into video */
export async function startExport(project: ProjectEntry, takeId: string): Promise<ExportEntry> {
  const instrumentalPath = path.join(project.projectDir, 'instrumental.wav');
  const takePath = path.join(project.projectDir, 'takes', `${takeId}.wav`);

  // Verify files exist
  await access(instrumentalPath);
  await access(takePath);

  const id = randomUUID();
  const safeName = project.name.replace(/[^a-zA-Z0-9_\- ]/g, '').trim() || 'export';
  const fileName = `${safeName}_export_${id.slice(0, 8)}.mp4`;
  const mixedAudioPath = path.join(project.projectDir, `mixed_${id}.wav`);
  const outputPath = path.join(project.projectDir, fileName);

  const entry: ExportEntry = {
    id,
    projectId: project.id,
    takeId,
    status: 'pending',
    progress: 0,
    fileName,
    filePath: outputPath,
    createdAt: new Date().toISOString(),
  };
  exports.set(id, entry);

  // Run export pipeline in background
  runExportPipeline(entry, project, takePath, instrumentalPath, mixedAudioPath, outputPath).catch(() => {});

  return entry;
}

async function runExportPipeline(
  entry: ExportEntry,
  project: ProjectEntry,
  takePath: string,
  instrumentalPath: string,
  mixedAudioPath: string,
  outputPath: string,
): Promise<void> {
  try {
    // Step 1: Mix take audio with instrumental using ffmpeg amix filter
    updateExportStatus(entry.id, 'mixing', 20);
    await run('ffmpeg', [
      '-i', takePath,
      '-i', instrumentalPath,
      '-filter_complex', '[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0',
      '-acodec', 'pcm_s16le',
      '-y',
      mixedAudioPath,
    ]);

    // Step 2: Mux mixed audio into original video (copy video stream)
    updateExportStatus(entry.id, 'muxing', 60);
    await run('ffmpeg', [
      '-i', project.videoPath,
      '-i', mixedAudioPath,
      '-c:v', 'copy',         // copy video, no re-encode
      '-map', '0:v:0',        // video from original
      '-map', '1:a:0',        // audio from mixed file
      '-shortest',
      '-y',
      outputPath,
    ]);

    entry.filePath = outputPath;
    updateExportStatus(entry.id, 'done', 100);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[export] Pipeline failed for export ${entry.id}:`, message);
    updateExportStatus(entry.id, 'error', entry.progress, message);
  }
}
