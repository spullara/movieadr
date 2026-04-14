import { useRef, useState, useCallback } from 'react';
import { encodeWav } from '../utils/wavEncoder';

export interface RecorderState {
  isRecording: boolean;
  audioLevel: number; // 0-1 for visual meter
}

export function useAudioRecorder() {
  const [state, setState] = useState<RecorderState>({ isRecording: false, audioLevel: 0 });
  const contextRef = useRef<AudioContext | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const chunksRef = useRef<Float32Array[]>([]);
  const sampleRateRef = useRef(44100);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const levelFrameRef = useRef(0);

  const startRecording = useCallback(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    streamRef.current = stream;

    const ctx = new AudioContext();
    contextRef.current = ctx;
    sampleRateRef.current = ctx.sampleRate;

    const source = ctx.createMediaStreamSource(stream);

    // Analyser for level metering
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 256;
    analyserRef.current = analyser;
    source.connect(analyser);

    // ScriptProcessor to capture raw PCM
    const processor = ctx.createScriptProcessor(4096, 1, 1);
    processorRef.current = processor;
    chunksRef.current = [];

    processor.onaudioprocess = (e) => {
      const input = e.inputBuffer.getChannelData(0);
      chunksRef.current.push(new Float32Array(input));
    };

    source.connect(processor);
    processor.connect(ctx.destination);

    // Level metering loop
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    const updateLevel = () => {
      if (!analyserRef.current) return;
      analyserRef.current.getByteTimeDomainData(dataArray);
      let sum = 0;
      for (let i = 0; i < dataArray.length; i++) {
        const v = (dataArray[i] - 128) / 128;
        sum += v * v;
      }
      const rms = Math.sqrt(sum / dataArray.length);
      setState((s) => ({ ...s, audioLevel: Math.min(1, rms * 3) }));
      levelFrameRef.current = requestAnimationFrame(updateLevel);
    };
    levelFrameRef.current = requestAnimationFrame(updateLevel);

    setState({ isRecording: true, audioLevel: 0 });
  }, []);

  const stopRecording = useCallback((): Blob | null => {
    cancelAnimationFrame(levelFrameRef.current);

    if (processorRef.current) {
      processorRef.current.disconnect();
      processorRef.current = null;
    }
    if (contextRef.current) {
      contextRef.current.close();
      contextRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    analyserRef.current = null;

    const chunks = chunksRef.current;
    if (chunks.length === 0) {
      setState({ isRecording: false, audioLevel: 0 });
      return null;
    }

    // Merge chunks
    const totalLength = chunks.reduce((acc, c) => acc + c.length, 0);
    const merged = new Float32Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    chunksRef.current = [];

    setState({ isRecording: false, audioLevel: 0 });
    return encodeWav(merged, sampleRateRef.current);
  }, []);

  return { ...state, startRecording, stopRecording };
}
