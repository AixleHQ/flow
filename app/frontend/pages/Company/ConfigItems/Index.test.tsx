import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { ConfigItem } from 'shared/resources/config-items/ConfigItemsContent';

import ConfigItemsIndex from './Index';

const configItem = (overrides: Partial<ConfigItem> = {}): ConfigItem => ({
  id: 1,
  name: 'DATABASE_URL',
  value: 'postgres://localhost',
  description: 'Primary database connection',
  itemType: 'variable',
  scopeType: 'company',
  scopeIndicator: 'Company',
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Company/ConfigItems/Index', () => {
  it('renders the title and lists the seeded config items', () => {
    renderAuthedPage(
      <ConfigItemsIndex
        configItems={[
          configItem({ id: 1, name: 'DATABASE_URL' }),
          configItem({ id: 2, name: 'API_TOKEN', itemType: 'secret' }),
        ]}
      />,
    );

    expect(screen.getByRole('heading', { name: 'Config Items' })).toBeInTheDocument();
    expect(screen.getByText('DATABASE_URL')).toBeInTheDocument();
    expect(screen.getByText('API_TOKEN')).toBeInTheDocument();
  });

  it('shows the empty state when there are no config items', () => {
    renderAuthedPage(<ConfigItemsIndex configItems={[]} />);

    expect(screen.getByText('No config items found')).toBeInTheDocument();
  });

  it('filters config items by the search query', async () => {
    renderAuthedPage(
      <ConfigItemsIndex
        configItems={[configItem({ id: 1, name: 'DATABASE_URL' }), configItem({ id: 2, name: 'REDIS_HOST' })]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'redis');

    expect(screen.queryByText('DATABASE_URL')).not.toBeInTheDocument();
    expect(screen.getByText('REDIS_HOST')).toBeInTheDocument();
  });

  it('opens the create modal when "Add Config Item" is clicked', async () => {
    renderAuthedPage(<ConfigItemsIndex configItems={[]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add Config Item' }));

    expect(screen.getByRole('heading', { name: 'Add Config Item' })).toBeInTheDocument();
  });

  it('deletes a config item via the row menu after confirmation', async () => {
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
    // Use a secret item so the row's only button is the actions menu trigger (no copy button).
    renderAuthedPage(
      <ConfigItemsIndex configItems={[configItem({ id: 42, name: 'DATABASE_URL', itemType: 'secret' })]} />,
    );

    const row = screen.getByText('DATABASE_URL').closest('tr');
    expect(row).not.toBeNull();
    await userEvent.click(within(row as HTMLElement).getByRole('button'));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Delete' }));

    expect(confirmSpy).toHaveBeenCalledWith('Delete DATABASE_URL?');
    expect(router.delete).toHaveBeenCalledWith('/company/config_items/42', { preserveScroll: true });

    confirmSpy.mockRestore();
  });
});
