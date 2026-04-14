import express from 'express';
import cors from 'cors';
import path from 'path';
import { healthRouter } from './routes/health.js';
import { projectsRouter } from './routes/projects.js';
import { takesRouter } from './routes/takes.js';
import { exportsRouter } from './routes/exports.js';

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

// Serve project files (audio, timestamps, waveform data)
app.use('/projects', express.static(path.resolve('projects')));

// Routes
app.use('/api', healthRouter);
app.use('/api', projectsRouter);
app.use('/api', takesRouter);
app.use('/api', exportsRouter);

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
