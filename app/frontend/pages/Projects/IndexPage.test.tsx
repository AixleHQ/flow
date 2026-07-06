import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildProject } from 'test/factories/project';
import { makeFormStub, renderAuthedPage, screen, userEvent, within } from 'test/renderPage';
import type Project from 'types/generated/Project';

import IndexPage from './IndexPage';

// Delegates to the typed factory so the Project drift contract applies here too.
// buildProject defaults description to null; the local builder defaulted it to
// 'First project', so we keep that exact value as an override to preserve the field
// values the search-by-description tests rely on.
const project = (overrides: Partial<Project> = {}): Project =>
  buildProject({ description: 'First project', ...overrides });

describe('Projects/IndexPage', () => {
  it('renders the empty state with a create CTA when there are no projects', () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [] } });

    expect(screen.getByText('No projects yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create Your First Project' })).toBeInTheDocument();
  });

  it('lists projects and filters them by the search query', async () => {
    renderAuthedPage(<IndexPage />, {
      props: { projects: [project({ id: 1, name: 'Acme' }), project({ id: 2, name: 'Globex', slug: 'globex' })] },
    });

    expect(screen.getByText('Acme')).toBeInTheDocument();
    expect(screen.getByText('Globex')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search projects...'), 'glob');

    expect(screen.queryByText('Acme')).not.toBeInTheDocument();
    expect(screen.getByText('Globex')).toBeInTheDocument();
  });

  it('shows the "no projects found" state when the search matches nothing', async () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [project({ name: 'Acme' })] } });

    await userEvent.type(screen.getByPlaceholderText('Search projects...'), 'zzz');

    expect(screen.getByText('No projects found')).toBeInTheDocument();
  });

  it('navigates to the project when a card is opened', async () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [project({ id: 7, name: 'Acme' })] } });

    await userEvent.click(screen.getByTitle('Open project'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7');
  });

  it('matches projects by description, not just name', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        projects: [
          project({ id: 1, name: 'Acme', description: 'rocket fuel research' }),
          project({ id: 2, name: 'Globex', slug: 'globex', description: 'banking ledger' }),
        ],
      },
    });

    await userEvent.type(screen.getByPlaceholderText('Search projects...'), 'rocket');

    expect(screen.getByText('Acme')).toBeInTheDocument();
    expect(screen.queryByText('Globex')).not.toBeInTheDocument();
  });

  it('does not show search/sort controls in the empty state', () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [] } });

    expect(screen.queryByPlaceholderText('Search projects...')).not.toBeInTheDocument();
  });

  it('sorts projects alphabetically by name by default', () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        projects: [project({ id: 1, name: 'Zeta', slug: 'zeta' }), project({ id: 2, name: 'Alpha', slug: 'alpha' })],
      },
    });

    const names = screen.getAllByText(/^(Alpha|Zeta)$/).map((el) => el.textContent);
    expect(names).toEqual(['Alpha', 'Zeta']);
  });

  it('reorders cards when sorting by "Newest first"', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        projects: [
          project({ id: 1, name: 'Alpha', slug: 'alpha', createdAt: '2026-01-01T00:00:00Z' }),
          project({ id: 2, name: 'Zeta', slug: 'zeta', createdAt: '2026-05-01T00:00:00Z' }),
        ],
      },
    });

    // Default name sort puts Alpha first.
    expect(screen.getAllByText(/^(Alpha|Zeta)$/).map((el) => el.textContent)).toEqual(['Alpha', 'Zeta']);

    await userEvent.click(screen.getByDisplayValue('Name'));
    await userEvent.click(screen.getByRole('option', { name: 'Newest first' }));

    // Zeta is newer (May) so it now comes first.
    expect(screen.getAllByText(/^(Alpha|Zeta)$/).map((el) => el.textContent)).toEqual(['Zeta', 'Alpha']);
  });

  it('sorts by last activity, pushing projects without activity to the end', async () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        projects: [
          project({ id: 1, name: 'Quiet', slug: 'quiet', lastActivityAt: null }),
          project({ id: 2, name: 'Busy', slug: 'busy', lastActivityAt: '2026-06-01T00:00:00Z' }),
        ],
      },
    });

    await userEvent.click(screen.getByDisplayValue('Name'));
    await userEvent.click(screen.getByRole('option', { name: 'Last activity' }));

    // Busy has activity so it sorts before the activity-less Quiet.
    expect(screen.getAllByText(/^(Busy|Quiet)$/).map((el) => el.textContent)).toEqual(['Busy', 'Quiet']);
  });

  it('opens the create modal from the header button', async () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [project()] } });

    await userEvent.click(screen.getByRole('button', { name: 'Create Project' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Create New Project')).toBeInTheDocument();
    expect(within(dialog).getByText('Project Name')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('opens the create modal from the empty-state CTA', async () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [] } });

    await userEvent.click(screen.getByRole('button', { name: 'Create Your First Project' }));

    expect(await screen.findByText('Create New Project')).toBeInTheDocument();
  });

  it('keeps the create button disabled while the project name is empty', async () => {
    renderAuthedPage(<IndexPage />, {
      props: { projects: [project()] },
      form: makeFormStub({ name: '', description: '' }),
    });

    await userEvent.click(screen.getByRole('button', { name: 'Create Project' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeDisabled();
  });

  it('submits the create form with a valid project name', async () => {
    const form = makeFormStub({ name: 'Rocketship', description: 'to the moon' });
    renderAuthedPage(<IndexPage />, { props: { projects: [project()] }, form });

    await userEvent.click(screen.getByRole('button', { name: 'Create Project' }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create' }));

    expect(form.post).toHaveBeenCalledWith('/company/projects', expect.any(Object));
  });

  it('navigates to project settings from the card settings action', async () => {
    renderAuthedPage(<IndexPage />, { props: { projects: [project({ id: 42, name: 'Acme' })] } });

    await userEvent.click(screen.getByTitle('Project settings'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/42/settings');
  });

  it('renders pluralized stat labels and member badge on a card', () => {
    renderAuthedPage(<IndexPage />, {
      props: {
        projects: [
          project({ id: 1, name: 'Acme', sessionsCount: 1, workflowsCount: 3, boardTasksCount: 0, membersCount: 2 }),
        ],
      },
    });

    expect(screen.getByText('1 session')).toBeInTheDocument();
    expect(screen.getByText('3 workflows')).toBeInTheDocument();
    expect(screen.getByText('0 tasks')).toBeInTheDocument();
    expect(screen.getByText('2 members')).toBeInTheDocument();
  });
});
