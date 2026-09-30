import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { AddTrackerDrawer } from './AddTrackerDrawer';

const scopes = [
  {
    integrationId: 42,
    integrationName: 'acme/Customer Platform',
    provider: 'azure_devops',
    scopes: [
      { id: 'p1', name: 'Customer Platform' },
      { id: 'p2', name: 'Ops Board' },
    ],
  },
];

describe('AddTrackerDrawer', () => {
  it('preselects the only connection, suggests a handle from the project and posts the tracker', async () => {
    renderPage(
      <AddTrackerDrawer opened onClose={vi.fn()} basePath="/company/projects/7/trackers" availableScopes={scopes} />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: /project/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'Ops Board' }));
    expect(screen.getByRole('textbox', { name: /handle/i })).toHaveValue('ops-board');

    await userEvent.click(screen.getByRole('checkbox', { name: /read-only/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Add tracker' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/trackers',
      {
        tracker: {
          integrationId: '42',
          externalScopeId: 'p2',
          handle: 'ops-board',
          access: 'read_only',
          primary: false,
        },
      },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('refuses a handle that is not lowercase letters, digits and dashes', async () => {
    renderPage(
      <AddTrackerDrawer opened onClose={vi.fn()} basePath="/company/projects/7/trackers" availableScopes={scopes} />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: /project/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'Ops Board' }));
    await userEvent.clear(screen.getByRole('textbox', { name: /handle/i }));
    await userEvent.type(screen.getByRole('textbox', { name: /handle/i }), 'Ops Board!');
    await userEvent.click(screen.getByRole('button', { name: 'Add tracker' }));

    expect(await screen.findByText('Lowercase letters, digits and dashes')).toBeInTheDocument();
    expect(router.post).not.toHaveBeenCalled();
  });
});
