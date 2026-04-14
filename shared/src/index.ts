/** Status of a project's preparation pipeline */
export type PreparationStatus =
  | 'pending'
  | 'downloading'
  | 'extracting_audio'
  | 'transcribing'
  | 'separating_vocals'
  | 'generating_waveform'
  | 'ready'
  | 'error';

/** A single word with timing information from Whisper */
export interface TimedWord {
  word: string;
  start: number; // seconds
  end: number;   // seconds
}

/** Project metadata */
export interface Project {
  id: string;
  name: string;
  videoFileName: string;
  status: PreparationStatus;
  createdAt: string;
  error?: string;
}

/** A recorded take for a project */
export interface Take {
  id: string;
  projectId: string;
  filename: string;
  duration: number; // seconds
  createdAt: string;
}

/** Export status */
export type ExportStatus = 'pending' | 'mixing' | 'muxing' | 'done' | 'error';

/** An export of a project with a specific take */
export interface Export {
  id: string;
  projectId: string;
  takeId: string;
  status: ExportStatus;
  progress: number; // 0-100
  fileName?: string;
  error?: string;
  createdAt: string;
}

/** Health check response */
export interface HealthResponse {
  status: 'ok';
  timestamp: string;
}
