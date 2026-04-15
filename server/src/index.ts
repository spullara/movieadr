import express from 'express';
import cors from 'cors';
import path from 'path';
import { healthRouter } from './routes/health.js';
import { projectsRouter } from './routes/projects.js';
import { takesRouter } from './routes/takes.js';
import { exportsRouter } from './routes/exports.js';
import { loadProjects } from './services/projects.js';

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

// Request logging
app.use((req, _res, next) => {
  console.log(`${req.method} ${req.url}`);
  next();
});

// Serve project files (audio, timestamps, waveform data)
app.use('/projects', express.static(path.resolve('projects')));

// Routes
app.use('/api', healthRouter);
app.use('/api', projectsRouter);
app.use('/api', takesRouter);
app.use('/api', exportsRouter);

// Load existing projects from disk before starting
loadProjects().then(() => {
  const server = app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });

  server.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`\nError: Port ${PORT} is already in use.`);
      console.error(`Fix it by running: lsof -ti:${PORT} | xargs kill`);
    } else {
      console.error('Server error:', err);
    }
    process.exit(1);
  });
}).catch((err) => {
  console.error('Failed to load projects:', err);
  process.exit(1);
});

