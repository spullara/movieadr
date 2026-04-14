import { Router } from 'express';
import { access, stat } from 'fs/promises';
import { createReadStream } from 'fs';
import path from 'path';
import { createProject, getProject, listProjects, projectEvents } from '../services/projects.js';
import { runPipeline } from '../services/pipeline.js';

export const projectsRouter = Router();

/** POST /api/projects — Create a new project from a video file path */
projectsRouter.post('/projects', async (req, res) => {
  try {
    const { videoPath } = req.body;

    if (!videoPath || typeof videoPath !== 'string') {
      res.status(400).json({ error: 'videoPath is required' });
      return;
    }

    // Verify file exists
    try {
      await access(videoPath);
    } catch {
      res.status(400).json({ error: `Video file not found: ${videoPath}` });
      return;
    }

    const project = await createProject(videoPath);

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
