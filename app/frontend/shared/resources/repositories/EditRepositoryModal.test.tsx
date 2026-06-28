import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { EditRepositoryModal } from './EditRepositoryModal';

const makeRepo = (overrides: Partial<Parameters<typeof EditRepositoryModal>[0]['repo'] & object> = {}) => ({
  id: 42,
  fullName: 'acme/payments-api',
  sourceBranch: 'main',
  purpose: 'Billing service',
  description: 'Handles invoices',
  integration: { id: 1, name: 'GitHub', provider: 'github' },
  ...overrides,
});

describe('EditRepositoryModal', () => {
  it('renders the title with the repo name and the form fields when a repo is provided', () => {
    renderPage(
      <EditRepositoryModal
        repo={makeRepo()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText('Edit acme/payments-api')).toBeInTheDocument();
    expect(screen.getByText('Source branch')).toBeInTheDocument();
    expect(screen.getByText('Purpose')).toBeInTheDocument();
    expect(screen.getByText('Description')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /update/i })).toBeInTheDocument();
  });

  it('submitting fires router.patch with the repo path and current values', async () => {
    renderPage(
      <EditRepositoryModal
        repo={makeRepo()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /update/i }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/7/repositories/42',
        { repository: { sourceBranch: 'main', purpose: 'Billing service', description: 'Handles invoices' } },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('does NOT submit when the source branch is empty (validation blocks)', async () => {
    renderPage(
      <EditRepositoryModal
        repo={makeRepo({ sourceBranch: '' })}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /update/i }));

    expect(router.patch).not.toHaveBeenCalled();
  });

  it('clicking Cancel calls onClose without hitting the backend', async () => {
    const onClose = vi.fn();
    renderPage(
      <EditRepositoryModal
        repo={makeRepo()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={onClose}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('shows the AI helper description and placeholder for the Purpose field', () => {
    renderPage(
      <EditRepositoryModal
        repo={makeRepo()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText('Helps AI agents understand what this repository is used for')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Optional description...')).toBeInTheDocument();
  });
});
