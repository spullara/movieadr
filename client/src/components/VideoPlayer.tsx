import { useRef, useEffect, useState, useCallback } from 'react';

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
  const fontSize = Math.max(20, Math.min(32, H * 0.05));
  ctx.font = `bold ${fontSize}px system-ui, sans-serif`;
  ctx.textBaseline = 'middle';
  const pxPerSec = W * 0.15;
  const y = H * 0.15;
  const visibleLeft = currentTime - (nowX / pxPerSec) - 2;
  const visibleRight = currentTime + ((W - nowX) / pxPerSec) + 2;

  for (const w of words) {
    if (w.start < visibleLeft || w.start > visibleRight) continue;
    const x = nowX + (w.start - currentTime) * pxPerSec;

    if (currentTime >= w.start && currentTime <= w.end) {
      const textW = ctx.measureText(w.word).width;
      ctx.fillStyle = 'rgba(255, 100, 100, 0.25)';
      ctx.fillRect(x - 2, y - fontSize * 0.6, textW + 4, fontSize * 1.2);
      ctx.fillStyle = '#ffffff';
    } else if (currentTime > w.end) {
      ctx.fillStyle = 'rgba(255, 255, 255, 0.3)';
    } else {
      ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
    }
    ctx.fillText(w.word, x, y);
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

  const [words, setWords] = useState<TimedWord[]>([]);
  const [waveform, setWaveform] = useState<WaveformData | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);

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

      <div style={{
        display: 'flex', alignItems: 'center', gap: '0.75rem',
        padding: '0.6rem 1rem', background: '#1a1a1a', borderTop: '1px solid #333',
      }}>
        <button onClick={togglePlay} style={btnStyle}>
          {isPlaying ? '⏸ Pause' : '▶ Play'}
        </button>
        <span style={{ color: '#aaa', fontSize: '0.8rem', minWidth: '4rem' }}>
          {formatTime(currentTime)}
        </span>
        <input
          type="range" min={0} max={duration} step={0.1}
          value={currentTime}
          onChange={handleSeek}
          style={{ flex: 1 }}
        />
        <span style={{ color: '#aaa', fontSize: '0.8rem', minWidth: '4rem', textAlign: 'right' }}>
          {formatTime(duration)}
        </span>
      </div>
    </div>
  );
}
