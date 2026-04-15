import { Router } from 'express';
import { stat, readdir, readFile, rm } from 'fs/promises';
import { createReadStream, existsSync } from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import multer from 'multer';
import { createProjectDir, registerProject, getProject, listProjects, projectEvents, updateProjectStatus } from '../services/projects.js';
import { runPipeline } from '../services/pipeline.js';

export const projectsRouter = Router();

// Configure multer to upload directly into the project directory
const upload = multer({
  storage: multer.diskStorage({
    destination: async (_req, _file, cb) => {
      try {
        const { id, projectDir } = await createProjectDir();
        // Attach to request so we can use later
        (_req as any)._projectId = id;
        (_req as any)._projectDir = projectDir;
        cb(null, projectDir);
      } catch (err) {
        cb(err as Error, '');
      }
    },
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.mp4';
      cb(null, `input${ext}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 * 1024 }, // 10 GB
});

/** POST /api/projects — Create a new project from an uploaded video file */
projectsRouter.post('/projects', upload.single('video'), async (req, res) => {
  try {
    const file = req.file;
    if (!file) {
      res.status(400).json({ error: 'No video file uploaded' });
      return;
    }

    const projectId = (req as any)._projectId as string;
    const projectDir = (req as any)._projectDir as string;
    const videoPath = file.path;
    const videoFileName = file.originalname;

    const project = registerProject(projectId, projectDir, videoPath, videoFileName);

    // Start pipeline in background (don't await)
    runPipeline(project);

    res.status(201).json({
      id: project.id,
      name: project.name,
      videoFileName: project.videoFileName,
      status: project.status,
      progress: project.progress,
      createdAt: project.createdAt,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(500).json({ error: message });
  }
});

/** POST /api/projects/youtube — Create a new project from a YouTube URL */
projectsRouter.post('/projects/youtube', async (req, res) => {
  try {
    const { url } = req.body;
    if (!url || typeof url !== 'string') {
      res.status(400).json({ error: 'Missing or invalid "url" field' });
      return;
    }

    const { id, projectDir } = await createProjectDir();
    const outputPath = path.join(projectDir, 'input.mp4');

    // Register project immediately with a placeholder name
    const project = registerProject(id, projectDir, outputPath, 'youtube-video.mp4');
    updateProjectStatus(id, 'downloading', 5);

    // Respond immediately so the client can start polling
    res.status(201).json({
      id: project.id,
      name: project.name,
      videoFileName: project.videoFileName,
      status: 'downloading',
      progress: 5,
      createdAt: project.createdAt,
    });

    // Download in background
    const pythonPath = path.resolve('..', 'venv', 'bin', 'python');
    const titleFilePath = path.join(projectDir, '_title.txt');
    const ytDlpArgs = [
      '-m', 'yt_dlp',
      '--no-check-certificates',
      '--remote-components', 'ejs:github',
      '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
      '--merge-output-format', 'mp4',
      '--print-to-file', 'after_filter:%(title)s', titleFilePath,
      '-o', outputPath,
      url,
    ];

    const proc = spawn(pythonPath, ytDlpArgs, {
      env: { ...process.env },
    });

    let stderrOutput = '';

    proc.stdout.on('data', (data: Buffer) => {
      console.log('[youtube]', data.toString().trim());
    });

    proc.stderr.on('data', (data: Buffer) => {
      console.error('[youtube]', data.toString());
      stderrOutput += data.toString();
    });

    proc.on('close', async (code) => {
      if (code !== 0) {
        console.error(`[youtube] yt-dlp failed with code ${code}: ${stderrOutput}`);
        updateProjectStatus(id, 'error', 0, `yt-dlp failed: ${stderrOutput.slice(0, 500)}`);
        return;
      }

      // Verify the file actually exists
      if (!existsSync(outputPath)) {
        const files = await readdir(projectDir);
        console.error(`[youtube] input.mp4 not found after download. Files in project dir:`, files);

        // Check if yt-dlp saved with a different name/extension
        const videoFile = files.find(f => /\.(mp4|mkv|webm|mov|avi)$/i.test(f));
        if (!videoFile) {
          updateProjectStatus(id, 'error', 0, `yt-dlp exited 0 but no video file found. Files: ${files.join(', ')}`);
          return;
        }
        console.log(`[youtube] Found video file with different name: ${videoFile}`);
      }

      // Update project name from video title
      try {
        const titleFromYtDlp = (await readFile(titleFilePath, 'utf-8')).trim();
        if (titleFromYtDlp) {
          project.name = titleFromYtDlp;
          project.videoFileName = `${titleFromYtDlp}.mp4`;
        }
      } catch {
        console.warn('[youtube] Could not read title file, using default name');
      }

      // Start the normal pipeline
      runPipeline(project);
    });

    proc.on('error', (err) => {
      console.error('[youtube] Failed to start yt-dlp:', err.message);
      updateProjectStatus(id, 'error', 0, `Failed to start yt-dlp: ${err.message}`);
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(500).json({ error: message });
  }
});

/** GET /api/projects — List all projects */
projectsRouter.get('/projects', (_req, res) => {
  const projects = listProjects().map((p) => ({
    id: p.id,
    name: p.name,
    videoFileName: p.videoFileName,
    status: p.status,
    progress: p.progress,
    createdAt: p.createdAt,
    error: p.error,
  }));
  res.json(projects);
});

/** GET /api/projects/:id — Get project status */
projectsRouter.get('/projects/:id', (req, res) => {
  const project = getProject(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }
  res.json({
    id: project.id,
    name: project.name,
    videoFileName: project.videoFileName,
    status: project.status,
    progress: project.progress,
    createdAt: project.createdAt,
    error: project.error,
  });
});

/** GET /api/projects/:id/events — SSE endpoint for preparation progress */
projectsRouter.get('/projects/:id/events', (req, res) => {
  const project = getProject(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });

  // Send current status immediately
  res.write(`data: ${JSON.stringify({
    projectId: project.id,
    status: project.status,
    progress: project.progress,
    error: project.error,
  })}\n\n`);

  const onProgress = (data: { projectId: string; status: string; progress: number; error?: string }) => {
    if (data.projectId !== req.params.id) return;
    res.write(`data: ${JSON.stringify(data)}\n\n`);

    // Close connection when done or errored
    if (data.status === 'ready' || data.status === 'error') {
      res.end();
    }
  };

  projectEvents.on('progress', onProgress);

  req.on('close', () => {
    projectEvents.off('progress', onProgress);
  });
});

/** POST /api/projects/:id/reprocess — Re-run preparation pipeline on an existing project */
projectsRouter.post('/projects/:id/reprocess', async (req, res) => {
  try {
    const project = getProject(req.params.id);
    if (!project) {
      res.status(404).json({ error: 'Project not found' });
      return;
    }

    // Don't allow reprocessing if already in progress
    if (project.status !== 'ready' && project.status !== 'error' && project.status !== 'pending') {
      res.status(409).json({ error: 'Project is currently being processed' });
      return;
    }

    // Verify input video still exists
    if (!existsSync(project.videoPath)) {
      res.status(400).json({ error: 'Input video file no longer exists' });
      return;
    }

    // Reset status
    updateProjectStatus(project.id, 'pending', 0);
    project.error = undefined;

    // Delete old preparation output files (keep input video and takes)
    const filesToDelete = [
      'audio.wav',
      'audio_full.wav',
      'word_timestamps.json',
      'instrumental.wav',
      'waveform_peaks.json',
      '_whisper_script.py',
      '_waveform_script.py',
    ];

    const dirsToDelete = ['htdemucs'];

    await Promise.allSettled([
      ...filesToDelete.map(f =>
        rm(path.join(project.projectDir, f), { force: true })
      ),
      ...dirsToDelete.map(d =>
        rm(path.join(project.projectDir, d), { recursive: true, force: true })
      ),
    ]);

    // Re-run pipeline in background
    runPipeline(project);

    res.json({ id: project.id, status: 'pending', progress: 0 });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(500).json({ error: message });
  }
});

/** GET /api/projects/:id/video — Stream the original video file with range support */
projectsRouter.get('/projects/:id/video', async (req, res) => {
  const project = getProject(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }

  try {
    const fileStat = await stat(project.videoPath);
    const fileSize = fileStat.size;
    const ext = path.extname(project.videoPath).toLowerCase();
    const mimeTypes: Record<string, string> = {
      '.mp4': 'video/mp4',
      '.mkv': 'video/x-matroska',
      '.mov': 'video/quicktime',
      '.webm': 'video/webm',
    };
    const contentType = mimeTypes[ext] || 'video/mp4';

    const range = req.headers.range;
    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
      const chunkSize = end - start + 1;

      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${fileSize}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': chunkSize,
        'Content-Type': contentType,
      });
      createReadStream(project.videoPath, { start, end }).pipe(res);
    } else {
      res.writeHead(200, {
        'Content-Length': fileSize,
        'Content-Type': contentType,
        'Accept-Ranges': 'bytes',
      });
      createReadStream(project.videoPath).pipe(res);
    }
  } catch {
    res.status(500).json({ error: 'Failed to stream video' });
  }
});
