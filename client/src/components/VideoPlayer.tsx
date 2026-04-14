import { useRef, useEffect, useState, useCallback } from 'react';
import { useAudioRecorder } from '../hooks/useAudioRecorder';

interface TimedWord {
  word: string;
  start: number;
  end: number;
}

interface WaveformData {
  peaks: number[];
  sampleRate: number;
  samplesPerPeak: number;
}

interface VideoPlayerProps {
  projectId: string;
  onBack: () => void;
}

interface TakeInfo {
  id: string;
  projectId: string;
  filename: string;
  duration: number;
  createdAt: string;
}

interface ExportInfo {
  id: string;
  projectId: string;
  takeId: string;
  status: string;
  progress: number;
  fileName?: string;
  error?: string;
  createdAt: string;
}

const NOW_LINE_RATIO = 0.2;

const btnStyle: React.CSSProperties = {
  padding: '0.4rem 0.8rem',
  borderRadius: '4px',
  border: '1px solid #444',
  background: '#2a2a2a',
  color: '#fff',
  cursor: 'pointer',
  fontSize: '0.85rem',
};

function drawTeleprompter(
  ctx: CanvasRenderingContext2D,
  words: TimedWord[],
  currentTime: number,
  W: number,
  H: number,
  nowX: number,
) {
  const fontSize = Math.max(14, Math.min(22, H * 0.035));
  ctx.font = `bold ${fontSize}px system-ui, sans-serif`;
  ctx.textBaseline = 'middle';
  const pxPerSec = W * 0.15;
  const baseY = H * 0.85; // same vertical center as waveform
  const wordGap = fontSize * 0.5; // horizontal padding between words
  const visibleLeft = currentTime - (nowX / pxPerSec) - 2;
  const visibleRight = currentTime + ((W - nowX) / pxPerSec) + 2;

  // Group words into lines based on timing gaps (>0.3s gap = new line)
  const lines: TimedWord[][] = [];
  let currentLine: TimedWord[] = [];
  for (let i = 0; i < words.length; i++) {
    if (currentLine.length > 0) {
      const prevEnd = currentLine[currentLine.length - 1].end;
      if (words[i].start - prevEnd > 0.3) {
        lines.push(currentLine);
        currentLine = [];
      }
    }
    currentLine.push(words[i]);
  }
  if (currentLine.length > 0) lines.push(currentLine);

  // Set up text outline for readability
  ctx.lineWidth = 3;
  ctx.lineJoin = 'round';
  ctx.strokeStyle = '#000000';

  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    // Skip lines entirely outside visible range
    if (line[line.length - 1].start < visibleLeft || line[0].start > visibleRight) continue;

    // Alternate lines vertically: even lines above center, odd lines below
    const lineOffset = (li % 2 === 0) ? -fontSize * 0.8 : fontSize * 0.8;
    const y = baseY + lineOffset;

    // Compute cumulative x offsets so words don't overlap
    // First word anchors at its timestamp position; subsequent words are offset
    // by the measured width of previous words + gap, or by their own timestamp,
    // whichever places them further right.
    let nextMinX = -Infinity;
    for (const w of line) {
      if (w.start < visibleLeft || w.start > visibleRight) {
        // still accumulate width for off-screen words so spacing stays correct
        const tsX = nowX + (w.start - currentTime) * pxPerSec;
        const textW = ctx.measureText(w.word).width;
        nextMinX = Math.max(tsX, nextMinX) + textW + wordGap;
        continue;
      }

      const tsX = nowX + (w.start - currentTime) * pxPerSec;
      const x = Math.max(tsX, nextMinX);
      const textW = ctx.measureText(w.word).width;
      nextMinX = x + textW + wordGap;

      if (currentTime >= w.start && currentTime <= w.end) {
        ctx.fillStyle = 'rgba(255, 100, 100, 0.35)';
        ctx.fillRect(x - 2, y - fontSize * 0.6, textW + 4, fontSize * 1.2);
        ctx.fillStyle = '#ffffff';
      } else if (currentTime > w.end) {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
      } else {
        ctx.fillStyle = '#ffffff';
      }
      ctx.strokeText(w.word, x, y); // black outline first
      ctx.fillText(w.word, x, y);   // then fill on top
    }
  }
}

function drawWaveform(
  ctx: CanvasRenderingContext2D,
  waveform: WaveformData,
  currentTime: number,
  W: number,
  H: number,
  nowX: number,
) {
  const { peaks, sampleRate, samplesPerPeak } = waveform;
  const peakDuration = samplesPerPeak / sampleRate;
  const waveH = H * 0.15;
  const waveY = H * 0.85;
  const barW = 2;
  const step = barW + 1;
  const centerPeakIdx = currentTime / peakDuration;

  for (let px = 0; px < W; px += step) {
    const peakIdx = Math.floor(centerPeakIdx + (px - nowX) / step);
    if (peakIdx < 0 || peakIdx >= peaks.length) continue;
    const barH = peaks[peakIdx] * waveH;

    if (px < nowX) {
      ctx.fillStyle = 'rgba(100, 150, 255, 0.3)';
    } else if (Math.abs(px - nowX) < step) {
      ctx.fillStyle = 'rgba(255, 100, 100, 0.9)';
    } else {
      ctx.fillStyle = 'rgba(100, 150, 255, 0.6)';
    }
    ctx.fillRect(px, waveY - barH / 2, barW, barH);
  }
}

export function VideoPlayer({ projectId, onBack }: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const animFrameRef = useRef<number>(0);
  const instrumentalRef = useRef<HTMLAudioElement | null>(null);
  const syncIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [words, setWords] = useState<TimedWord[]>([]);
  const [waveform, setWaveform] = useState<WaveformData | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [takes, setTakes] = useState<TakeInfo[]>([]);
  const [playingTakeId, setPlayingTakeId] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const takeAudioRef = useRef<HTMLAudioElement | null>(null);
  const [exports, setExports] = useState<ExportInfo[]>([]);
  const [exporting, setExporting] = useState(false);

  const { isRecording, audioLevel, startRecording, stopRecording } = useAudioRecorder();

  // Initialize instrumental audio element and sync with video
  useEffect(() => {
    const audio = new Audio(`/projects/${projectId}/instrumental.wav`);
    audio.preload = 'auto';
    instrumentalRef.current = audio;

    const video = videoRef.current;
    if (!video) return;

    // Mute video so original vocals don't play
    video.muted = true;

    const onPlay = () => {
      audio.currentTime = video.currentTime;
      audio.play().catch(() => {});
      // Start drift correction
      syncIntervalRef.current = setInterval(() => {
        if (video.paused || audio.paused) return;
        const drift = Math.abs(video.currentTime - audio.currentTime);
        if (drift > 0.05) {
          audio.currentTime = video.currentTime;
        }
      }, 200);
    };

    const onPause = () => {
      audio.pause();
      if (syncIntervalRef.current) {
        clearInterval(syncIntervalRef.current);
        syncIntervalRef.current = null;
      }
    };

    const onSeeked = () => {
      audio.currentTime = video.currentTime;
    };

    const onEnded = () => {
      audio.pause();
      audio.currentTime = 0;
      if (syncIntervalRef.current) {
        clearInterval(syncIntervalRef.current);
        syncIntervalRef.current = null;
      }
    };

    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    video.addEventListener('seeked', onSeeked);
    video.addEventListener('ended', onEnded);

    return () => {
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
      video.removeEventListener('seeked', onSeeked);
      video.removeEventListener('ended', onEnded);
      audio.pause();
      audio.src = '';
      instrumentalRef.current = null;
      if (syncIntervalRef.current) {
        clearInterval(syncIntervalRef.current);
        syncIntervalRef.current = null;
      }
    };
  }, [projectId]);

  // Fetch takes list
  const fetchTakes = useCallback(async () => {
    try {
      const res = await fetch(`/api/projects/${projectId}/takes`);
      if (res.ok) setTakes(await res.json());
    } catch { /* ignore */ }
  }, [projectId]);

  const fetchExports = useCallback(async () => {
    try {
      const res = await fetch(`/api/projects/${projectId}/exports`);
      if (res.ok) setExports(await res.json());
    } catch { /* ignore */ }
  }, [projectId]);

  const handleExport = useCallback(async (takeId: string) => {
    setExporting(true);
    try {
      const res = await fetch(`/api/projects/${projectId}/export`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ takeId }),
      });
      if (!res.ok) {
        const data = await res.json();
        console.error('Export failed:', data.error);
        return;
      }
      const exportData = await res.json();
      // Poll for progress via SSE
      const evtSource = new EventSource(
        `/api/projects/${projectId}/exports/${exportData.id}/events`
      );
      evtSource.onmessage = (event) => {
        const data = JSON.parse(event.data);
        setExports((prev) => {
          const idx = prev.findIndex((e) => e.id === exportData.id);
          const updated = { ...exportData, ...data };
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = updated;
            return next;
          }
          return [...prev, updated];
        });
        if (data.status === 'done' || data.status === 'error') {
          evtSource.close();
          setExporting(false);
          fetchExports();
        }
      };
      evtSource.onerror = () => {
        evtSource.close();
        setExporting(false);
        fetchExports();
      };
    } catch (err) {
      console.error('Export failed:', err);
      setExporting(false);
    }
  }, [projectId, fetchExports]);

  useEffect(() => { fetchTakes(); fetchExports(); }, [fetchTakes, fetchExports]);

  useEffect(() => {
    Promise.all([
      fetch(`/projects/${projectId}/word_timestamps.json`).then((r) => r.json()),
      fetch(`/projects/${projectId}/waveform_peaks.json`).then((r) => r.json()),
    ]).then(([ts, wf]) => {
      setWords(ts.words || []);
      setWaveform(wf);
    }).catch(console.error);
  }, [projectId]);

  const togglePlay = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) video.play();
    else video.pause();
  }, []);

  const handleRecordPlay = useCallback(async () => {
    const video = videoRef.current;
    if (!video) return;

    if (isRecording) {
      // Stop recording and video
      video.pause();
      const blob = stopRecording();
      if (blob) {
        setUploading(true);
        try {
          const formData = new FormData();
          formData.append('audio', blob, 'take.wav');
          const res = await fetch(`/api/projects/${projectId}/takes`, {
            method: 'POST',
            body: formData,
          });
          if (res.ok) await fetchTakes();
        } catch (err) {
          console.error('Upload failed:', err);
        } finally {
          setUploading(false);
        }
      }
    } else {
      // Start recording and play video from beginning
      video.currentTime = 0;
      await startRecording();
      video.play();
    }
  }, [isRecording, stopRecording, startRecording, projectId, fetchTakes]);

  // Stop recording when video ends naturally
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onEnded = async () => {
      if (!isRecording) return;
      const blob = stopRecording();
      if (blob) {
        setUploading(true);
        try {
          const formData = new FormData();
          formData.append('audio', blob, 'take.wav');
          const res = await fetch(`/api/projects/${projectId}/takes`, {
            method: 'POST',
            body: formData,
          });
          if (res.ok) await fetchTakes();
        } catch (err) {
          console.error('Upload failed:', err);
        } finally {
          setUploading(false);
        }
      }
    };
    video.addEventListener('ended', onEnded);
    return () => video.removeEventListener('ended', onEnded);
  }, [isRecording, stopRecording, projectId, fetchTakes]);

  const playTake = useCallback((takeId: string) => {
    if (takeAudioRef.current) {
      takeAudioRef.current.pause();
      takeAudioRef.current = null;
    }
    if (playingTakeId === takeId) {
      setPlayingTakeId(null);
      return;
    }
    const audio = new Audio(`/api/projects/${projectId}/takes/${takeId}/audio`);
    audio.onended = () => setPlayingTakeId(null);
    audio.play();
    takeAudioRef.current = audio;
    setPlayingTakeId(takeId);
  }, [projectId, playingTakeId]);

  const handleSeek = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = parseFloat(e.target.value);
  }, []);

  const drawFrame = useCallback(() => {
    const canvas = canvasRef.current;
    const video = videoRef.current;
    if (!canvas || !video) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    const t = video.currentTime;
    const nowX = W * NOW_LINE_RATIO;

    ctx.clearRect(0, 0, W, H);

    // Dark background band behind waveform/text area for readability
    const bandY = H * 0.85;
    const bandH = H * 0.15;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.6)';
    ctx.fillRect(0, bandY - bandH, W, bandH * 2);

    if (waveform && waveform.peaks.length > 0) {
      drawWaveform(ctx, waveform, t, W, H, nowX);
    }
    if (words.length > 0) {
      drawTeleprompter(ctx, words, t, W, H, nowX);
    }

    // Now line
    ctx.strokeStyle = 'rgba(255, 100, 100, 0.8)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(nowX, 0);
    ctx.lineTo(nowX, H);
    ctx.stroke();

    setCurrentTime(t);
    animFrameRef.current = requestAnimationFrame(drawFrame);
  }, [words, waveform]);

  useEffect(() => {
    animFrameRef.current = requestAnimationFrame(drawFrame);
    return () => cancelAnimationFrame(animFrameRef.current);
  }, [drawFrame]);

  useEffect(() => {
    const resize = () => {
      const canvas = canvasRef.current;
      const container = containerRef.current;
      if (!canvas || !container) return;
      canvas.width = container.clientWidth;
      canvas.height = container.clientHeight;
    };
    resize();
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);

  const formatTime = (s: number) => {
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', background: '#000' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: '1rem',
        padding: '0.5rem 1rem', background: '#1a1a1a', borderBottom: '1px solid #333',
      }}>
        <button onClick={onBack} style={btnStyle}>← Back</button>
        <span style={{ color: '#999', fontSize: '0.9rem' }}>Project: {projectId.slice(0, 8)}…</span>
      </div>

      <div ref={containerRef} style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        <video
          ref={videoRef}
          src={`/api/projects/${projectId}/video`}
          muted
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          onLoadedMetadata={() => setDuration(videoRef.current?.duration || 0)}
          style={{ width: '100%', height: '100%', objectFit: 'contain' }}
        />
        <canvas
          ref={canvasRef}
          style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', pointerEvents: 'none' }}
        />
      </div>

      {/* Recording indicator */}
      {isRecording && (
        <div style={{
          position: 'absolute', top: '4rem', right: '1rem',
          display: 'flex', alignItems: 'center', gap: '0.5rem',
          padding: '0.4rem 0.8rem', borderRadius: '4px',
          background: 'rgba(200, 0, 0, 0.8)', color: '#fff', fontSize: '0.85rem',
          zIndex: 10,
        }}>
          <span style={{
            width: 10, height: 10, borderRadius: '50%',
            background: '#ff3333', display: 'inline-block',
            animation: 'pulse 1s ease-in-out infinite',
          }} />
          REC
          {/* Level meter */}
          <div style={{
            width: 60, height: 8, background: 'rgba(0,0,0,0.4)',
            borderRadius: 4, overflow: 'hidden', marginLeft: 4,
          }}>
            <div style={{
              width: `${audioLevel * 100}%`, height: '100%',
              background: audioLevel > 0.7 ? '#ff3333' : '#33ff33',
              transition: 'width 50ms',
            }} />
          </div>
        </div>
      )}

      <div style={{
        display: 'flex', alignItems: 'center', gap: '0.75rem',
        padding: '0.6rem 1rem', background: '#1a1a1a', borderTop: '1px solid #333',
      }}>
        <button onClick={togglePlay} style={btnStyle} disabled={isRecording}>
          {isPlaying ? '⏸ Pause' : '▶ Play'}
        </button>
        <button
          onClick={handleRecordPlay}
          disabled={uploading}
          style={{
            ...btnStyle,
            background: isRecording ? '#cc0000' : '#8b0000',
            border: isRecording ? '1px solid #ff3333' : '1px solid #cc0000',
          }}
        >
          {uploading ? '⏳ Uploading…' : isRecording ? '⏹ Stop Rec' : '🎙 Record + Play'}
        </button>
        <span style={{ color: '#aaa', fontSize: '0.8rem', minWidth: '4rem' }}>
          {formatTime(currentTime)}
        </span>
        <input
          type="range" min={0} max={duration} step={0.1}
          value={currentTime}
          onChange={handleSeek}
          style={{ flex: 1 }}
          disabled={isRecording}
        />
        <span style={{ color: '#aaa', fontSize: '0.8rem', minWidth: '4rem', textAlign: 'right' }}>
          {formatTime(duration)}
        </span>
      </div>

      {/* Takes list */}
      {takes.length > 0 && (
        <div style={{
          padding: '0.5rem 1rem', background: '#111', borderTop: '1px solid #333',
          maxHeight: '8rem', overflowY: 'auto',
        }}>
          <div style={{ color: '#888', fontSize: '0.75rem', marginBottom: '0.3rem' }}>
            Takes ({takes.length})
          </div>
          {takes.map((take) => {
            const takeExport = exports.find((e) => e.takeId === take.id);
            return (
              <div key={take.id} style={{
                display: 'flex', alignItems: 'center', gap: '0.5rem',
                padding: '0.25rem 0', borderBottom: '1px solid #222',
              }}>
                <button
                  onClick={() => playTake(take.id)}
                  style={{ ...btnStyle, padding: '0.2rem 0.5rem', fontSize: '0.75rem' }}
                >
                  {playingTakeId === take.id ? '⏹' : '▶'}
                </button>
                <span style={{ color: '#ccc', fontSize: '0.8rem' }}>
                  Take {takes.length - takes.indexOf(take)}
                </span>
                <span style={{ color: '#666', fontSize: '0.75rem' }}>
                  {formatTime(take.duration)} — {new Date(take.createdAt).toLocaleTimeString()}
                </span>
                <span style={{ flex: 1 }} />
                {takeExport?.status === 'done' ? (
                  <a
                    href={`/api/projects/${projectId}/exports/${takeExport.id}?download=true`}
                    download={takeExport.fileName}
                    style={{ ...btnStyle, padding: '0.2rem 0.5rem', fontSize: '0.75rem', background: '#166534', textDecoration: 'none', color: '#fff' }}
                  >
                    📥 Download
                  </a>
                ) : takeExport && takeExport.status !== 'error' ? (
                  <span style={{ color: '#f59e0b', fontSize: '0.75rem' }}>
                    ⏳ {takeExport.status} {takeExport.progress}%
                  </span>
                ) : (
                  <button
                    onClick={() => handleExport(take.id)}
                    disabled={exporting}
                    style={{ ...btnStyle, padding: '0.2rem 0.5rem', fontSize: '0.75rem', background: '#1d4ed8', opacity: exporting ? 0.5 : 1 }}
                  >
                    🎬 Export
                  </button>
                )}
                {takeExport?.status === 'error' && (
                  <span style={{ color: '#ef4444', fontSize: '0.7rem' }} title={takeExport.error}>
                    ❌ Error
                  </span>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Pulse animation for recording indicator */}
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.3; }
        }
      `}</style>
    </div>
  );
}
