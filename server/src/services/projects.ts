import { randomUUID } from 'crypto';
import { mkdir, readdir, readFile, writeFile, access } from 'fs/promises';
import path from 'path';
import { EventEmitter } from 'events';
import type { Project, PreparationStatus } from '@moviekaraoke/shared';

const PROJECTS_DIR = path.resolve('projects');

export interface ProjectEntry extends Project {
  videoPath: string;
  projectDir: string;
  progress: number; // 0-100
}

const projects = new Map<string, ProjectEntry>();
export const projectEvents = new EventEmitter();

export async function createProjectDir(): Promise<{ id: string; projectDir: string }> {
  const id = randomUUID();
  const projectDir = path.join(PROJECTS_DIR, id);
  await mkdir(projectDir, { recursive: true });
  return { id, projectDir };
}

export function registerProject(id: string, projectDir: string, videoPath: string, videoFileName: string): ProjectEntry {
  const project: ProjectEntry = {
    id,
    name: videoFileName.replace(/\.[^.]+$/, ''),
    videoFileName,
    videoPath,
    projectDir,
    status: 'pending',
    progress: 0,
    createdAt: new Date().toISOString(),
  };

  projects.set(id, project);
  saveProjectMetadata(project);
  return project;
}

export function getProject(id: string): ProjectEntry | undefined {
  return projects.get(id);
}

export function listProjects(): ProjectEntry[] {
  return Array.from(projects.values());
}

export function deleteProject(id: string): boolean {
  return projects.delete(id);
}

export function updateProjectStatus(
  id: string,
  status: PreparationStatus,
  progress: number,
  error?: string,
): void {
  const project = projects.get(id);
  if (!project) return;

  project.status = status;
  project.progress = progress;
  if (error) project.error = error;

  saveProjectMetadata(project);

  projectEvents.emit('progress', {
    projectId: id,
    status,
    progress,
    error,
  });
}

interface ProjectMetadata {
  id: string;
  name: string;
  videoFileName: string;
  status: PreparationStatus;
  createdAt: string;
  error?: string;
}

function saveProjectMetadata(project: ProjectEntry): void {
  const metadata: ProjectMetadata = {
    id: project.id,
    name: project.name,
    videoFileName: project.videoFileName,
    status: project.status,
    createdAt: project.createdAt,
    error: project.error,
  };
  const filePath = path.join(project.projectDir, 'project.json');
  writeFile(filePath, JSON.stringify(metadata, null, 2)).catch((err) => {
    console.error(`Failed to save project metadata for ${project.id}:`, err);
  });
}

const READY_FILES = ['word_timestamps.json', 'instrumental.wav', 'waveform_peaks.json'];

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

export async function loadProjects(): Promise<void> {
  try {
    await mkdir(PROJECTS_DIR, { recursive: true });
    const entries = await readdir(PROJECTS_DIR, { withFileTypes: true });

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;

      const projectDir = path.join(PROJECTS_DIR, entry.name);
      const metadataPath = path.join(projectDir, 'project.json');

      // Find the input video file
      let videoFileName: string | undefined;
      let videoPath: string | undefined;
      try {
        const files = await readdir(projectDir);
        const inputFile = files.find((f) => f.startsWith('input.'));
        if (inputFile) {
          videoPath = path.join(projectDir, inputFile);
          videoFileName = inputFile;
        }
      } catch {
        continue;
      }

      // Try to load metadata
      let metadata: ProjectMetadata | undefined;
      try {
        const raw = await readFile(metadataPath, 'utf-8');
        metadata = JSON.parse(raw) as ProjectMetadata;
      } catch {
        // No metadata file — skip if no video file either
      }

      if (!metadata && !videoFileName) {
        // Not a project directory
        continue;
      }

      // Determine status from files on disk
      const readyFileChecks = await Promise.all(
        READY_FILES.map((f) => fileExists(path.join(projectDir, f))),
      );
      const allReady = readyFileChecks.every(Boolean);
      const someReady = readyFileChecks.some(Boolean);

      let status: PreparationStatus;
      let error: string | undefined;

      if (allReady) {
        status = 'ready';
      } else if (metadata?.status === 'ready') {
        // Metadata says ready but files are missing
        status = 'error';
        error = 'Preparation interrupted — reimport video';
      } else if (someReady || (metadata && metadata.status !== 'error' && metadata.status !== 'pending')) {
        status = 'error';
        error = 'Preparation interrupted — reimport video';
      } else if (metadata?.status === 'error') {
        status = 'error';
        error = metadata.error;
      } else {
        status = 'error';
        error = 'Preparation interrupted — reimport video';
      }

      const id = metadata?.id ?? entry.name;
      const project: ProjectEntry = {
        id,
        name: metadata?.name ?? (videoFileName ? videoFileName.replace(/\.[^.]+$/, '') : entry.name),
        videoFileName: metadata?.videoFileName ?? videoFileName ?? 'unknown',
        videoPath: videoPath ?? path.join(projectDir, 'input.mp4'),
        projectDir,
        status,
        progress: status === 'ready' ? 100 : 0,
        createdAt: metadata?.createdAt ?? new Date().toISOString(),
        error,
      };

      projects.set(id, project);
      console.log(`Loaded project ${id} (${project.name}) — status: ${status}`);
    }

    console.log(`Loaded ${projects.size} project(s) from disk`);
  } catch (err) {
    console.error('Failed to load projects from disk:', err);
  }
}
