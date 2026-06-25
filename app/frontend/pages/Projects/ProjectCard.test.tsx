import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { ProjectCard } from './ProjectCard';

// ProjectCard declares its own local Project interface (concrete counts), so build a matching
// fixture inline rather than from the generated type (whose counts are `unknown`).
const project = {
  id: 1,
  name: 'Acme',
  description: 'A test project',
  slug: 'acme',
  state: 'active',
  collaboratorsCount: 2,
  membersCount: 3,
  sessionsCount: 5,
  workflowsCount: 1,
  boardTasksCount: 8,
  lastActivityAt: '2026-06-20T00:00:00Z',
  createdAt: '2026-01-01T00:00:00Z',
};

describe('ProjectCard', () => {
  it('renders the name, description, and pluralized stats', () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.getByText('Acme')).toBeInTheDocument();
    expect(screen.getByText('A test project')).toBeInTheDocument();
    expect(screen.getByText('5 sessions')).toBeInTheDocument();
    expect(screen.getByText('1 workflow')).toBeInTheDocument(); // singular for count === 1
    expect(screen.getByText('8 tasks')).toBeInTheDocument();
    expect(screen.getByText('3 members')).toBeInTheDocument();
  });

  it('exposes the open/settings actions', () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.getByTitle('Open project')).toBeInTheDocument();
    expect(screen.getByTitle('Project settings')).toBeInTheDocument();
  });
});
