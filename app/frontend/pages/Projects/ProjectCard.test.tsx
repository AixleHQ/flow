import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { ProjectCard } from './ProjectCard';

// Stat number and label render as separate elements (different fonts), so their
// combined text is split across nodes — match on the element whose own text equals it.
const withText = (text: string) => (_content: string, element: Element | null) =>
  element?.textContent === text && element.children.length === 2;

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
  members: [
    { id: 1, initials: 'AC' },
    { id: 2, initials: 'BD' },
    { id: 3, initials: 'CE' },
  ],
};

describe('ProjectCard', () => {
  it('renders the name, status, and pluralized stats', () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.getByText('Acme')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText(withText('5 sessions'))).toBeInTheDocument();
    expect(screen.getByText(withText('1 workflow'))).toBeInTheDocument(); // singular for count === 1
    expect(screen.getByText(withText('8 tasks'))).toBeInTheDocument();
  });

  it('shows the description as a tooltip on the name, not as body text', async () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.queryByText('A test project')).not.toBeInTheDocument();

    await userEvent.hover(screen.getByText('Acme'));

    expect(await screen.findByText('A test project')).toBeInTheDocument();
  });

  it('renders a member avatar for each preview member plus an overflow count', () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.getByText('AC')).toBeInTheDocument();
    expect(screen.getByText('BD')).toBeInTheDocument();
    expect(screen.getByText('CE')).toBeInTheDocument();
    expect(screen.getByLabelText('3 members')).toBeInTheDocument();
  });

  it('exposes the open/settings actions', () => {
    renderPage(<ProjectCard project={project} />);
    expect(screen.getByRole('button', { name: /open/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /settings/i })).toBeInTheDocument();
  });

  it('dims archived projects', () => {
    renderPage(<ProjectCard project={{ ...project, state: 'archived' }} />);
    expect(screen.getByText('Archived')).toBeInTheDocument();
  });
});
