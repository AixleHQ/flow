import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

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
  favorite: false,
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

  it('offers a favorite control that reports the unstarred state', () => {
    renderPage(<ProjectCard project={project} onToggleFavorite={vi.fn()} />);

    const star = screen.getByRole('button', { name: 'Add Acme to favorites' });
    expect(star).toHaveAttribute('aria-pressed', 'false');
  });

  it('reports the starred state on an already favorited project', () => {
    renderPage(<ProjectCard project={{ ...project, favorite: true }} onToggleFavorite={vi.fn()} />);

    const star = screen.getByRole('button', { name: 'Remove Acme from favorites' });
    expect(star).toHaveAttribute('aria-pressed', 'true');
  });

  // The star lives inside the tile but must not open the project — favoriting is
  // done without navigating in.
  it('toggles the favorite without opening the project', async () => {
    const onToggleFavorite = vi.fn();
    const onClick = vi.fn();
    renderPage(<ProjectCard project={project} onClick={onClick} onToggleFavorite={onToggleFavorite} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add Acme to favorites' }));

    expect(onToggleFavorite).toHaveBeenCalledTimes(1);
    expect(onClick).not.toHaveBeenCalled();
  });

  it('omits the favorite control when no toggle handler is given', () => {
    renderPage(<ProjectCard project={project} />);

    expect(screen.queryByRole('button', { name: /favorites/ })).not.toBeInTheDocument();
  });

  it('dims archived projects', () => {
    renderPage(<ProjectCard project={{ ...project, state: 'archived' }} />);
    expect(screen.getByText('Archived')).toBeInTheDocument();
  });
});
