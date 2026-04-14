import { randomUUID } from 'crypto';
import { mkdir } from 'fs/promises';
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
  return project;
}

export function getProject(id: string): ProjectEntry | undefined {
  return projects.get(id);
}

export function listProjects(): ProjectEntry[] {
  return Array.from(projects.values());
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

  projectEvents.emit('progress', {
    projectId: id,
    status,
    progress,
    error,
  });
}
