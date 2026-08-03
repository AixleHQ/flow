import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { ConfigItemsContent, type ConfigItem } from './ConfigItemsContent';

const makeItem = (overrides: Partial<ConfigItem> = {}): ConfigItem => ({
  id: 1,
  name: 'API_KEY',
  value: 'abc123',
  description: 'An API key',
  itemType: 'variable',
  scopeType: 'project',
  scopeIndicator: 'P',
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const items: ConfigItem[] = [
  makeItem({ id: 1, name: 'API_KEY', itemType: 'variable', value: 'abc123' }),
  makeItem({ id: 2, name: 'DB_PASSWORD', itemType: 'secret', value: 'topsecret', description: null }),
];

const renderContent = (configItems: ConfigItem[] = items) =>
  renderPage(<ConfigItemsContent configItems={configItems} basePath="/projects/1/config_items" title="Config Items" />);

// The per-row "…" menu trigger is an icon-only ActionIcon (no accessible name),
// identified by the dots-vertical icon it contains.
const rowMenuTriggers = (container: HTMLElement): HTMLButtonElement[] =>
  Array.from(container.querySelectorAll<HTMLButtonElement>('button')).filter((b) =>
    b.querySelector('.tabler-icon-dots-vertical'),
  );

describe('ConfigItemsContent', () => {
  it('renders the title and a row per config item', () => {
    renderContent();

    expect(screen.getByRole('heading', { name: 'Config Items' })).toBeInTheDocument();
    expect(screen.getByText('API_KEY')).toBeInTheDocument();
    expect(screen.getByText('DB_PASSWORD')).toBeInTheDocument();
    // variable value is shown verbatim; secret value is masked
    expect(screen.getByText('abc123')).toBeInTheDocument();
    expect(screen.queryByText('topsecret')).not.toBeInTheDocument();
    expect(screen.getByText('••••••••')).toBeInTheDocument();
  });

  it('shows an empty state when there are no items', () => {
    renderContent([]);

    expect(screen.getByText('No config items found')).toBeInTheDocument();
    expect(screen.queryByText('API_KEY')).not.toBeInTheDocument();
  });

  it('narrows the list as the user searches by name', async () => {
    renderContent();

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'DB');

    expect(screen.getByText('DB_PASSWORD')).toBeInTheDocument();
    expect(screen.queryByText('API_KEY')).not.toBeInTheDocument();
  });

  it('opens the Add modal when the add button is clicked', async () => {
    renderContent();

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /add secret/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Add secret')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('opens the Edit modal from a row menu', async () => {
    const { container } = renderContent();

    // open the first row's "…" menu, then click Edit
    await userEvent.click(rowMenuTriggers(container)[0]);
    await userEvent.click(await screen.findByRole('menuitem', { name: /edit/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Edit secret')).toBeInTheDocument();
  });

  it('fires router.delete after confirming a row delete', async () => {
    const { container } = renderContent();

    await userEvent.click(rowMenuTriggers(container)[0]);
    await userEvent.click(await screen.findByRole('menuitem', { name: /delete/i }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith(
        '/projects/1/config_items/1',
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });
});
