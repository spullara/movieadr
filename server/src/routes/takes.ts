import { Router } from 'express';
import multer from 'multer';
import { randomUUID } from 'crypto';
import { readdir, stat, writeFile, readFile } from 'fs/promises';
import { createReadStream } from 'fs';
import path from 'path';
import { getProject } from '../services/projects.js';
import type { Take } from '@moviekaraoke/shared';

export const takesRouter = Router();

function takesDir(projectDir: string) {
  return path.join(projectDir, 'takes');
}

const upload = multer({ storage: multer.memoryStorage() });

/** POST /api/projects/:id/takes — Upload a recorded take (WAV) */
takesRouter.post('/projects/:id/takes', upload.single('audio'), async (req, res) => {
  try {
    const project = getProject(req.params.id as string);
    if (!project) {
      res.status(404).json({ error: 'Project not found' });
      return;
    }

    if (!req.file) {
      res.status(400).json({ error: 'No audio file provided' });
      return;
    }

    const dir = takesDir(project.projectDir);
    const { mkdir } = await import('fs/promises');
    await mkdir(dir, { recursive: true });

    const takeId = randomUUID();
    const filename = `${takeId}.wav`;
    const filePath = path.join(dir, filename);

    await writeFile(filePath, req.file.buffer);

    // Parse WAV header to get duration
    const buffer = req.file.buffer;
    let duration = 0;
    if (buffer.length > 44) {
      const dataSize = buffer.readUInt32LE(40);
      const sampleRate = buffer.readUInt32LE(24);
      const numChannels = buffer.readUInt16LE(22);
      const bitsPerSample = buffer.readUInt16LE(34);
      if (sampleRate > 0 && numChannels > 0 && bitsPerSample > 0) {
        const bytesPerSample = (bitsPerSample / 8) * numChannels;
        duration = dataSize / (sampleRate * bytesPerSample);
      }
    }

    const take: Take = {
      id: takeId,
      projectId: project.id,
      filename,
      duration,
      createdAt: new Date().toISOString(),
    };

    // Save metadata
    const metaPath = path.join(dir, `${takeId}.json`);
    await writeFile(metaPath, JSON.stringify(take, null, 2));

    res.status(201).json(take);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(500).json({ error: message });
  }
});

/** GET /api/projects/:id/takes — List all takes for a project */
takesRouter.get('/projects/:id/takes', async (req, res) => {
  try {
    const project = getProject(req.params.id);
    if (!project) {
      res.status(404).json({ error: 'Project not found' });
      return;
    }

    const dir = takesDir(project.projectDir);
    let files: string[];
    try {
      files = await readdir(dir);
    } catch {
      res.json([]);
      return;
    }

    const takes: Take[] = [];
    for (const f of files) {
      if (!f.endsWith('.json')) continue;
      try {
        const data = await readFile(path.join(dir, f), 'utf-8');
        takes.push(JSON.parse(data));
      } catch {
        // skip corrupt metadata
      }
    }

    takes.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    res.json(takes);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(500).json({ error: message });
  }
});

/** GET /api/projects/:id/takes/:takeId/audio — Stream take audio */
takesRouter.get('/projects/:id/takes/:takeId/audio', async (req, res) => {
  try {
    const project = getProject(req.params.id);
    if (!project) {
      res.status(404).json({ error: 'Project not found' });
      return;
    }

    const filePath = path.join(takesDir(project.projectDir), `${req.params.takeId}.wav`);
    const fileStat = await stat(filePath);

    res.writeHead(200, {
      'Content-Length': fileStat.size,
      'Content-Type': 'audio/wav',
      'Accept-Ranges': 'bytes',
    });
    createReadStream(filePath).pipe(res);
  } catch {
    res.status(404).json({ error: 'Take audio not found' });
  }
});
