import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import type { Repository } from './RepositoriesContent';
import { RepositoriesContent } from './RepositoriesContent';

const makeRepo = (overrides: Partial<Repository> = {}): Repository => ({
  id: 1,
  fullName: 'acme/backend',
  cloneUrl: 'https://github.com/acme/backend.git',
  sourceBranch: 'main',
  isPrivate: false,
  description: 'Core API service',
  purpose: 'Primary Rails app',
  scopeIndicator: 'company',
  integration: { id: 10, name: 'Acme GitHub', provider: 'github' },
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('RepositoriesContent', () => {
  it('renders the title and a row per seeded repository', () => {
    renderPage(
      <RepositoriesContent
        title="Code Repositories"
        basePath="/companies/1/repositories"
        repositories={[
          makeRepo({ id: 1, fullName: 'acme/backend' }),
          makeRepo({ id: 2, fullName: 'acme/frontend', sourceBranch: 'develop' }),
        ]}
      />,
    );

    expect(screen.getByRole('heading', { name: 'Code Repositories' })).toBeInTheDocument();
    expect(screen.getByText('acme/backend')).toBeInTheDocument();
    expect(screen.getByText('acme/frontend')).toBeInTheDocument();
    // branch badge rendered for the row
    expect(screen.getByText('develop')).toBeInTheDocument();
  });

  it('shows the empty state when there are no repositories', () => {
    renderPage(
      <RepositoriesContent
        title="Code Repositories"
        basePath="/companies/1/repositories"
        repositories={[]}
      />,
    );

    expect(screen.getByText('No repositories added')).toBeInTheDocument();
    // The header Add button + the empty-state Add button are both present.
    expect(screen.getAllByRole('button', { name: /add repository/i }).length).toBeGreaterThanOrEqual(2);
  });

  it('splits repos into project + company sections in a project context', () => {
    renderPage(
      <RepositoriesContent
        title="Project Repositories"
        basePath="/projects/5/repositories"
        repositories={[
          makeRepo({ id: 1, fullName: 'acme/service', scopeIndicator: 'project' }),
          makeRepo({ id: 2, fullName: 'acme/shared-lib', scopeIndicator: 'company' }),
        ]}
      />,
    );

    expect(screen.getByText('This Project')).toBeInTheDocument();
    expect(screen.getByText('Company-wide')).toBeInTheDocument();
    expect(screen.getByText('acme/service')).toBeInTheDocument();
    expect(screen.getByText('acme/shared-lib')).toBeInTheDocument();
  });

  it('opens the Add Repository modal when the header button is clicked', async () => {
    renderPage(
      <RepositoriesContent
        title="Code Repositories"
        basePath="/companies/1/repositories"
        repositories={[makeRepo()]}
      />,
      // AddRepositoryModal reads integrations off usePage().props
      { props: { integrations: [] } },
    );

    await userEvent.click(screen.getByRole('button', { name: /add repository/i }));

    // Modal body becomes visible: assert its unique field labels are present.
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Integration')).toBeInTheDocument();
    expect(within(dialog).getByText('Repository')).toBeInTheDocument();
    expect(within(dialog).getByText('Source branch')).toBeInTheDocument();
  });

  it('confirming the remove dialog fires router.delete for that repo', async () => {
    renderPage(
      <RepositoriesContent
        title="Code Repositories"
        basePath="/companies/1/repositories"
        repositories={[makeRepo({ id: 42, fullName: 'acme/legacy' })]}
      />,
    );

    // Open the row menu (the only icon button before the modal opens).
    await userEvent.click(screen.getByRole('button', { name: '' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: /remove/i }));

    // Confirm modal from @mantine/modals; click its Remove button.
    const confirmBtn = await screen.findByRole('button', { name: 'Remove' });
    await userEvent.click(confirmBtn);

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith(
        '/companies/1/repositories/42',
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });
});
