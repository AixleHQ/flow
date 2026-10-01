import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { buildRepository } from 'test/factories/repository';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { EditRepositoryModal } from './EditRepositoryModal';

describe('EditRepositoryModal', () => {
  it('renders the title with the repo name and the form fields when a repo is provided', () => {
    renderPage(
      <EditRepositoryModal
        repo={buildRepository()}
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
        repo={buildRepository()}
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
        repo={buildRepository({ sourceBranch: '' })}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /update/i }));

    expect(router.patch).not.toHaveBeenCalled();
  });

  it('closes an untouched edit without asking and without hitting the backend', async () => {
    const onClose = vi.fn();
    renderPage(
      <EditRepositoryModal
        repo={buildRepository()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={onClose}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('asks before closing over an edited field, and closes once the user discards', async () => {
    const onClose = vi.fn();
    renderPage(
      <EditRepositoryModal
        repo={buildRepository()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={onClose}
      />,
    );

    await userEvent.type(screen.getByRole('textbox', { name: 'Purpose' }), ' and refunds');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('shows the AI helper description and placeholder for the Purpose field', () => {
    renderPage(
      <EditRepositoryModal
        repo={buildRepository()}
        branches={['main', 'develop']}
        basePath="/projects/7/repositories"
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText('Helps AI agents understand what this repository is used for')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Optional description...')).toBeInTheDocument();
  });
});
