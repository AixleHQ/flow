import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { ConfigItem } from 'shared/resources/config-items/ConfigItemsContent';

import ConfigPage from './ConfigPage';

const project = { id: 7, name: 'Gateway Service' };

const makeItem = (overrides: Partial<ConfigItem> = {}): ConfigItem => ({
  id: 1,
  name: 'DATABASE_URL',
  value: 'postgres://localhost/app',
  description: 'Primary database connection',
  itemType: 'variable',
  scopeType: 'project',
  scopeIndicator: 'P',
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const configItems: ConfigItem[] = [
  makeItem({ id: 1, name: 'DATABASE_URL', itemType: 'variable', value: 'postgres://localhost/app' }),
  makeItem({ id: 2, name: 'STRIPE_KEY', itemType: 'secret', value: 'sk_live_abc123', description: null }),
];

describe('Projects/Config/ConfigPage', () => {
  it('renders the title and primary controls with seeded props', () => {
    renderAuthedPage(<ConfigPage />, { props: { project, configItems } });

    expect(screen.getByRole('heading', { name: 'Project Config Items' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add Config Item' })).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search by name...')).toBeInTheDocument();
  });

  it('lists config items and masks secret values', () => {
    renderAuthedPage(<ConfigPage />, { props: { project, configItems } });

    expect(screen.getByText('DATABASE_URL')).toBeInTheDocument();
    expect(screen.getByText('STRIPE_KEY')).toBeInTheDocument();
    // variable value shown verbatim, secret value masked
    expect(screen.getByText('postgres://localhost/app')).toBeInTheDocument();
    expect(screen.getByText('••••••••')).toBeInTheDocument();
    expect(screen.queryByText('sk_live_abc123')).not.toBeInTheDocument();
  });

  it('filters items by the search query (name match)', async () => {
    renderAuthedPage(<ConfigPage />, { props: { project, configItems } });

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'stripe');

    expect(screen.getByText('STRIPE_KEY')).toBeInTheDocument();
    expect(screen.queryByText('DATABASE_URL')).not.toBeInTheDocument();
  });

  it('shows the empty state when no items match the search', async () => {
    renderAuthedPage(<ConfigPage />, { props: { project, configItems } });

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'no-such-key');

    expect(screen.getByText('No config items found')).toBeInTheDocument();
    expect(screen.queryByText('DATABASE_URL')).not.toBeInTheDocument();
  });

  it('deletes an item via the row menu after confirmation', async () => {
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
    renderAuthedPage(<ConfigPage />, { props: { project, configItems } });

    // Use the secret row (id 2): a secret has no Copy button, so its only button is the
    // row's action-menu trigger.
    const secretRow = screen.getByText('STRIPE_KEY').closest('tr') as HTMLElement;
    await userEvent.click(within(secretRow).getByRole('button'));

    await userEvent.click(await screen.findByRole('menuitem', { name: 'Delete' }));

    expect(confirmSpy).toHaveBeenCalledWith('Delete STRIPE_KEY?');
    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7/config_items/2',
      expect.objectContaining({ preserveScroll: true }),
    );

    confirmSpy.mockRestore();
  });
});
