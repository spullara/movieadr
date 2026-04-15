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
  downloading: 'Downloading video…',
  extracting_audio: 'Extracting audio…',
  transcribing: 'Transcribing…',
  separating_vocals: 'Separating vocals…',
  generating_waveform: 'Generating waveform…',
  ready: 'Ready',
  error: 'Error',
};

export function ProjectList({ onSelect }: { onSelect: (id: string) => void }) {
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [error, setError] = useState('');
  const [youtubeUrl, setYoutubeUrl] = useState('');
  const [submittingUrl, setSubmittingUrl] = useState(false);

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

  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setUploadProgress(0);
    setError('');

    const formData = new FormData();
    formData.append('video', file);

    try {
      // Use XMLHttpRequest for upload progress
      const result = await new Promise<{ ok: boolean; data: unknown }>((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/api/projects');

        xhr.upload.onprogress = (event) => {
          if (event.lengthComputable) {
            setUploadProgress(Math.round((event.loaded / event.total) * 100));
          }
        };

        xhr.onload = () => {
          try {
            const data = JSON.parse(xhr.responseText);
            resolve({ ok: xhr.status >= 200 && xhr.status < 300, data });
          } catch {
            reject(new Error('Invalid response'));
          }
        };

        xhr.onerror = () => reject(new Error('Upload failed'));
        xhr.send(formData);
      });

      if (!result.ok) {
        setError((result.data as { error?: string })?.error || 'Upload failed');
        return;
      }
      loadProjects();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      setUploadProgress(0);
      // Reset the file input
      e.target.value = '';
    }
  };

  const handleYoutubeSubmit = async () => {
    if (!youtubeUrl.trim()) return;
    setSubmittingUrl(true);
    setError('');

    try {
      const res = await fetch('/api/projects/youtube', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: youtubeUrl.trim() }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || 'Failed to import YouTube video');
        return;
      }
      setYoutubeUrl('');
      loadProjects();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to import YouTube video');
    } finally {
      setSubmittingUrl(false);
    }
  };

  return (
    <div style={{ padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1 style={{ fontSize: '1.8rem', marginBottom: '0.5rem' }}>🎤 Movie Karaoke</h1>
      <p style={{ color: '#999', marginBottom: '2rem' }}>ADR (Automated Dialogue Replacement) Tool</p>

      <div style={{ marginBottom: '2rem' }}>
        <label
          style={{
            display: 'inline-flex', alignItems: 'center', gap: '0.5rem',
            padding: '0.6rem 1.2rem', borderRadius: '6px', border: 'none',
            background: uploading ? '#555' : '#3b82f6', color: '#fff',
            cursor: uploading ? 'default' : 'pointer', fontSize: '0.9rem',
          }}
        >
          <input
            type="file"
            accept="video/*"
            onChange={handleFileSelect}
            disabled={uploading}
            style={{ display: 'none' }}
          />
          {uploading ? `Uploading… ${uploadProgress}%` : '📁 Choose Video File'}
        </label>
        {uploading && (
          <div style={{ marginTop: '0.5rem', background: '#333', borderRadius: '4px', height: '6px', overflow: 'hidden' }}>
            <div style={{ width: `${uploadProgress}%`, height: '100%', background: '#3b82f6', transition: 'width 0.2s' }} />
          </div>
        )}

        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginTop: '0.75rem' }}>
          <span style={{ color: '#888', fontSize: '0.85rem' }}>or</span>
          <input
            type="text"
            placeholder="Paste YouTube URL…"
            value={youtubeUrl}
            onChange={(e) => setYoutubeUrl(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleYoutubeSubmit()}
            disabled={submittingUrl || uploading}
            style={{
              flex: 1, padding: '0.5rem 0.75rem', borderRadius: '6px',
              border: '1px solid #444', background: '#1a1a1a', color: '#fff',
              fontSize: '0.9rem', outline: 'none',
            }}
          />
          <button
            onClick={handleYoutubeSubmit}
            disabled={submittingUrl || uploading || !youtubeUrl.trim()}
            style={{
              padding: '0.5rem 1rem', borderRadius: '6px', border: 'none',
              background: submittingUrl || !youtubeUrl.trim() ? '#555' : '#ef4444',
              color: '#fff', cursor: submittingUrl || !youtubeUrl.trim() ? 'default' : 'pointer',
              fontSize: '0.9rem', whiteSpace: 'nowrap',
            }}
          >
            {submittingUrl ? 'Importing…' : '▶ Import'}
          </button>
        </div>
      </div>
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
              <div style={{ textAlign: 'right', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                {(p.status === 'ready' || p.status === 'error') && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      fetch(`/api/projects/${p.id}/reprocess`, { method: 'POST' })
                        .then(() => loadProjects())
                        .catch(() => {});
                    }}
                    title="Re-run preparation pipeline"
                    style={{
                      padding: '0.3rem 0.6rem', borderRadius: '4px', border: '1px solid #555',
                      background: '#333', color: '#ccc', cursor: 'pointer', fontSize: '0.75rem',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    🔄 Reprocess
                  </button>
                )}
                <div>
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
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
