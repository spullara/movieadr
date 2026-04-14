/** Status of a project's preparation pipeline */
export type PreparationStatus =
  | 'pending'
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

/** Health check response */
export interface HealthResponse {
  status: 'ok';
  timestamp: string;
}
