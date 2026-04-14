import { useState, useEffect, useCallback } from 'react';

interface ProjectSummary {
  id: string;
  name: string;
  videoFileName: string;
  status: string;
  progress: number;
  createdAt: string;
  error?: string;
}

const STATUS_LABELS: Record<string, string> = {
  pending: 'Pending',
  extracting_audio: 'Extracting audio…',
  transcribing: 'Transcribing…',
  separating_vocals: 'Separating vocals…',
  generating_waveform: 'Generating waveform…',
  ready: 'Ready',
  error: 'Error',
};

export function ProjectList({ onSelect }: { onSelect: (id: string) => void }) {
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [videoPath, setVideoPath] = useState('');
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState('');

  const loadProjects = useCallback(async () => {
    try {
      const res = await fetch('/api/projects');
      const data = await res.json();
      setProjects(data);
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    loadProjects();
    const interval = setInterval(loadProjects, 3000);
    return () => clearInterval(interval);
  }, [loadProjects]);

  const handleImport = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!videoPath.trim()) return;
    setImporting(true);
    setError('');
    try {
      const res = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ videoPath: videoPath.trim() }),
      });
      if (!res.ok) {
        const data = await res.json();
        setError(data.error || 'Import failed');
        return;
      }
      setVideoPath('');
      loadProjects();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Import failed');
    } finally {
      setImporting(false);
    }
  };

  return (
    <div style={{ padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1 style={{ fontSize: '1.8rem', marginBottom: '0.5rem' }}>🎤 Movie Karaoke</h1>
      <p style={{ color: '#999', marginBottom: '2rem' }}>ADR (Automated Dialogue Replacement) Tool</p>

      <form onSubmit={handleImport} style={{ display: 'flex', gap: '0.5rem', marginBottom: '2rem' }}>
        <input
          type="text"
          value={videoPath}
          onChange={(e) => setVideoPath(e.target.value)}
          placeholder="Paste full path to a video file…"
          style={{
            flex: 1, padding: '0.6rem 0.8rem', borderRadius: '6px',
            border: '1px solid #444', background: '#2a2a2a', color: '#fff',
            fontSize: '0.9rem',
          }}
        />
        <button
          type="submit"
          disabled={importing || !videoPath.trim()}
          style={{
            padding: '0.6rem 1.2rem', borderRadius: '6px', border: 'none',
            background: '#3b82f6', color: '#fff', cursor: 'pointer',
            fontSize: '0.9rem', opacity: importing ? 0.6 : 1,
          }}
        >
          {importing ? 'Importing…' : 'Import'}
        </button>
      </form>
      {error && <p style={{ color: '#ef4444', marginBottom: '1rem' }}>{error}</p>}

      {projects.length === 0 ? (
        <p style={{ color: '#666', textAlign: 'center', marginTop: '3rem' }}>
          No projects yet. Import a video to get started.
        </p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
          {projects.map((p) => (
            <div
              key={p.id}
              onClick={() => p.status === 'ready' && onSelect(p.id)}
              style={{
                padding: '1rem', borderRadius: '8px', border: '1px solid #333',
                background: '#252525', cursor: p.status === 'ready' ? 'pointer' : 'default',
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              }}
            >
              <div>
                <div style={{ fontWeight: 600 }}>{p.name}</div>
                <div style={{ color: '#888', fontSize: '0.8rem' }}>{p.videoFileName}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{
                  fontSize: '0.8rem', fontWeight: 500,
                  color: p.status === 'ready' ? '#22c55e' : p.status === 'error' ? '#ef4444' : '#f59e0b',
                }}>
                  {STATUS_LABELS[p.status] || p.status}
                </div>
                {p.status !== 'ready' && p.status !== 'error' && (
                  <div style={{ fontSize: '0.75rem', color: '#666' }}>{p.progress}%</div>
                )}
                {p.error && <div style={{ fontSize: '0.75rem', color: '#ef4444' }}>{p.error}</div>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
