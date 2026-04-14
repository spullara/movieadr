import { useState, useEffect } from 'react';

export function App() {
  const [health, setHealth] = useState<string>('checking...');

  useEffect(() => {
    fetch('/api/health')
      .then((res) => res.json())
      .then((data) => setHealth(data.status))
      .catch(() => setHealth('error'));
  }, []);

  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', maxWidth: '600px', margin: '0 auto' }}>
      <h1>🎤 Movie Karaoke</h1>
      <p>ADR (Automated Dialogue Replacement) Tool</p>
      <p>
        Backend status: <strong>{health}</strong>
      </p>
    </div>
  );
}
