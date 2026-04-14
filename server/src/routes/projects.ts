import { Router } from 'express';
import { access } from 'fs/promises';
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
