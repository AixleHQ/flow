import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Repository } from 'shared/resources/repositories/RepositoriesContent';

import RepositoriesPage from './RepositoriesPage';

const project = { id: 42, name: 'Falcon Project' };

const repo = (overrides: Partial<Repository> = {}): Repository => ({
  id: 1,
  fullName: 'octo/hangar',
  cloneUrl: 'https://github.com/octo/hangar.git',
  sourceBranch: 'main',
  isPrivate: true,
  description: null,
  purpose: null,
  scopeIndicator: 'project',
  integration: { id: 9, name: 'GitHub Org', provider: 'github' },
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Projects/Repositories/RepositoriesPage', () => {
  it('renders the empty state with an add CTA when there are no repositories', () => {
    renderAuthedPage(<RepositoriesPage />, { props: { project, repositories: [] } });

    expect(screen.getByRole('heading', { name: 'Repositories' })).toBeInTheDocument();
    expect(screen.getByText('No repositories added')).toBeInTheDocument();
    // Header action + empty-state CTA both read "Add Repository".
    expect(screen.getAllByRole('button', { name: /Add Repository/i }).length).toBeGreaterThanOrEqual(1);
  });

  it('lists project repositories with their branch badge', () => {
    renderAuthedPage(<RepositoriesPage />, {
      props: {
        project,
        repositories: [repo({ id: 1, fullName: 'octo/hangar', sourceBranch: 'main' })],
      },
    });

    expect(screen.getByText('octo/hangar')).toBeInTheDocument();
    expect(screen.getByText('main')).toBeInTheDocument();
    expect(screen.getByText('project')).toBeInTheDocument();
  });

  it('shows company-wide repositories in the unified table with a Scope badge', () => {
    renderAuthedPage(<RepositoriesPage />, {
      props: {
        project,
        repositories: [
          repo({ id: 1, fullName: 'octo/hangar', scopeIndicator: 'project' }),
          repo({ id: 2, fullName: 'octo/shared-lib', scopeIndicator: 'company' }),
        ],
      },
    });

    expect(screen.getByText('octo/shared-lib')).toBeInTheDocument();
    expect(screen.getByText('company')).toBeInTheDocument();
  });

  it('reloads edit branches when editing a project repository', async () => {
    renderAuthedPage(<RepositoriesPage />, {
      props: {
        project,
        repositories: [repo({ id: 7, fullName: 'octo/hangar', scopeIndicator: 'project' })],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Edit' }));

    expect(router.reload).toHaveBeenCalledWith({ data: { edit_repo_id: 7 }, only: ['editBranches'] });
  });

  it('confirms before removing a repository and then fires the delete request', async () => {
    renderAuthedPage(<RepositoriesPage />, {
      props: {
        project,
        repositories: [repo({ id: 5, fullName: 'octo/hangar', scopeIndicator: 'project' })],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Remove' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Remove Repository')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/42/repositories/5',
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
