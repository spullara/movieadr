import { Router } from 'express';
import { stat } from 'fs/promises';
import { createReadStream } from 'fs';
import { getProject, projectEvents } from '../services/projects.js';
import { startExport, getExport, listExports, exportEvents } from '../services/export.js';

export const exportsRouter = Router();

/** POST /api/projects/:id/export — Start an export with a selected take */
exportsRouter.post('/projects/:id/export', async (req, res) => {
  try {
    const project = getProject(req.params.id);
    if (!project) {
      res.status(404).json({ error: 'Project not found' });
      return;
    }

    if (project.status !== 'ready') {
      res.status(400).json({ error: 'Project is not ready for export' });
      return;
    }

    const { takeId } = req.body;
    if (!takeId || typeof takeId !== 'string') {
      res.status(400).json({ error: 'takeId is required' });
      return;
    }

    const exportEntry = await startExport(project, takeId);
    res.status(201).json({
      id: exportEntry.id,
      projectId: exportEntry.projectId,
      takeId: exportEntry.takeId,
      status: exportEntry.status,
      progress: exportEntry.progress,
      fileName: exportEntry.fileName,
      createdAt: exportEntry.createdAt,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('ENOENT') || message.includes('no such file')) {
      res.status(400).json({ error: 'Take or instrumental file not found' });
      return;
    }
    res.status(500).json({ error: message });
  }
});

/** GET /api/projects/:id/exports — List all exports for a project */
exportsRouter.get('/projects/:id/exports', (req, res) => {
  const project = getProject(req.params.id);
  if (!project) {
    res.status(404).json({ error: 'Project not found' });
    return;
  }

  const projectExports = listExports(project.id).map((e) => ({
    id: e.id,
    projectId: e.projectId,
    takeId: e.takeId,
    status: e.status,
    progress: e.progress,
    fileName: e.fileName,
    error: e.error,
    createdAt: e.createdAt,
  }));
  res.json(projectExports);
});

/** GET /api/projects/:id/exports/:exportId — Get export status or download */
exportsRouter.get('/projects/:id/exports/:exportId', async (req, res) => {
  const exp = getExport(req.params.exportId);
  if (!exp || exp.projectId !== req.params.id) {
    res.status(404).json({ error: 'Export not found' });
    return;
  }

  // If requesting download (Accept header or query param)
  if (req.query.download === 'true' && exp.status === 'done' && exp.filePath) {
    try {
      const fileStat = await stat(exp.filePath);
      res.writeHead(200, {
        'Content-Type': 'video/mp4',
        'Content-Length': fileStat.size,
        'Content-Disposition': `attachment; filename="${exp.fileName}"`,
      });
      createReadStream(exp.filePath).pipe(res);
      return;
    } catch {
      res.status(500).json({ error: 'Export file not found on disk' });
      return;
    }
  }

  // Otherwise return status
  res.json({
    id: exp.id,
    projectId: exp.projectId,
    takeId: exp.takeId,
    status: exp.status,
    progress: exp.progress,
    fileName: exp.fileName,
    error: exp.error,
    createdAt: exp.createdAt,
  });
});

/** GET /api/projects/:id/exports/:exportId/events — SSE for export progress */
exportsRouter.get('/projects/:id/exports/:exportId/events', (req, res) => {
  const exp = getExport(req.params.exportId);
  if (!exp || exp.projectId !== req.params.id) {
    res.status(404).json({ error: 'Export not found' });
    return;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });

  // Send current status
  res.write(`data: ${JSON.stringify({
    exportId: exp.id,
    status: exp.status,
    progress: exp.progress,
    error: exp.error,
  })}\n\n`);

  const onProgress = (data: { exportId: string; status: string; progress: number; error?: string }) => {
    if (data.exportId !== req.params.exportId) return;
    res.write(`data: ${JSON.stringify(data)}\n\n`);
    if (data.status === 'done' || data.status === 'error') {
      res.end();
    }
  };

  exportEvents.on('progress', onProgress);
  req.on('close', () => {
    exportEvents.off('progress', onProgress);
  });
});
