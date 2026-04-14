import { useState } from 'react';
import { ProjectList } from './components/ProjectList';
import { VideoPlayer } from './components/VideoPlayer';

export function App() {
  const [selectedProject, setSelectedProject] = useState<string | null>(null);

  if (selectedProject) {
    return (
      <VideoPlayer
        projectId={selectedProject}
        onBack={() => setSelectedProject(null)}
      />
    );
  }

  return <ProjectList onSelect={setSelectedProject} />;
}
