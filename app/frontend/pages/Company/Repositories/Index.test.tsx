import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Repository } from 'shared/resources/repositories/RepositoriesContent';

import RepositoriesIndex from './Index';

const repo = (overrides: Partial<Repository> = {}): Repository => ({
  id: 1,
  fullName: 'octo/hangar',
  cloneUrl: 'https://github.com/octo/hangar.git',
  sourceBranch: 'main',
  isPrivate: true,
  description: null,
  purpose: null,
  scopeIndicator: 'company',
  integration: { id: 9, name: 'GitHub Org', provider: 'github' },
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

// `Company/Repositories/Index` receives its page props as direct React props (Inertia injects
// them), so we pass `repositories`/`editBranches` on the element itself. `renderAuthedPage` still
// seeds the shared SharedProps (currentUser/projects/...) the surrounding AuthLayout reads.
describe('Company/Repositories/Index', () => {
  it('renders the empty state with an add CTA when there are no repositories', () => {
    renderAuthedPage(<RepositoriesIndex repositories={[]} />);

    expect(screen.getByRole('heading', { name: 'Repositories' })).toBeInTheDocument();
    expect(screen.getByText('No repositories added')).toBeInTheDocument();
    // Header action + empty-state CTA both read "Add Repository".
    expect(screen.getAllByRole('button', { name: /Add Repository/i }).length).toBeGreaterThanOrEqual(1);
  });

  it('lists repositories with their full name and branch badge', () => {
    renderAuthedPage(<RepositoriesIndex repositories={[repo({ id: 1, fullName: 'octo/hangar', sourceBranch: 'release' })]} />);

    expect(screen.getByText('octo/hangar')).toBeInTheDocument();
    expect(screen.getByText('release')).toBeInTheDocument();
    expect(screen.getByText('GitHub Org')).toBeInTheDocument();
    // No empty-state copy once a repo exists.
    expect(screen.queryByText('No repositories added')).not.toBeInTheDocument();
  });

  it('reloads edit branches when editing a repository', async () => {
    renderAuthedPage(<RepositoriesIndex repositories={[repo({ id: 7, fullName: 'octo/hangar' })]} />);

    // The per-card menu trigger is the icon-only button with no accessible name.
    await userEvent.click(screen.getByRole('button', { name: '' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Edit' }));

    expect(router.reload).toHaveBeenCalledWith({ data: { edit_repo_id: 7 }, only: ['editBranches'] });
  });

  it('confirms before removing a repository and then fires the company-scoped delete request', async () => {
    renderAuthedPage(<RepositoriesIndex repositories={[repo({ id: 5, fullName: 'octo/hangar' })]} />);

    await userEvent.click(screen.getByRole('button', { name: '' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Remove' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Remove Repository')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/repositories/5',
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
