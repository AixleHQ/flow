import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { DocsSearchModal } from './DocsSearchModal';

describe('DocsSearchModal', () => {
  it('renders the search input when opened', () => {
    renderPage(<DocsSearchModal open onClose={vi.fn()} />);

    expect(screen.getByPlaceholderText('Search documentation…')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: 'Search documentation' })).toBeInTheDocument();
  });

  it('does not render the input when closed', () => {
    renderPage(<DocsSearchModal open={false} onClose={vi.fn()} />);

    expect(screen.queryByPlaceholderText('Search documentation…')).not.toBeInTheDocument();
  });

  it('shows matching results as the user types', async () => {
    const user = userEvent.setup();
    renderPage(<DocsSearchModal open onClose={vi.fn()} />);

    await user.type(screen.getByRole('textbox', { name: 'Search documentation' }), 'workflows');

    const listbox = await screen.findByRole('listbox');
    expect(within(listbox).getByText('Workflows')).toBeInTheDocument();
    // The matched result also surfaces its description text.
    expect(
      within(listbox).getByText(/A DAG of steps orchestrated by Temporal/i),
    ).toBeInTheDocument();
  });

  it('shows a no-results message for a query with no matches', async () => {
    const user = userEvent.setup();
    renderPage(<DocsSearchModal open onClose={vi.fn()} />);

    await user.type(screen.getByRole('textbox', { name: 'Search documentation' }), 'zzzznomatch');

    expect(await screen.findByText(/No results for/i)).toBeInTheDocument();
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
  });

  it('navigates and closes when a result is clicked', async () => {
    const onClose = vi.fn();
    const user = userEvent.setup();
    renderPage(<DocsSearchModal open onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Search documentation' }), 'quick start');

    const option = await screen.findByRole('button', { name: /Quick start/ });
    await user.click(option);

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.visit).toHaveBeenCalledWith('/docs/quick-start');
  });

  it('moves the active option with ArrowDown and navigates the active result on Enter', async () => {
    const onClose = vi.fn();
    const user = userEvent.setup();
    renderPage(<DocsSearchModal open onClose={onClose} />);

    const input = screen.getByRole('textbox', { name: 'Search documentation' });
    // "user guide" matches several entries (section + titles), giving us a multi-item list.
    await user.type(input, 'user guide');

    const listbox = await screen.findByRole('listbox');
    const options = within(listbox).getAllByRole('option');
    expect(options.length).toBeGreaterThan(1);

    // First option starts active.
    await waitFor(() => expect(options[0]).toHaveAttribute('aria-selected', 'true'));

    await user.keyboard('{ArrowDown}');
    await waitFor(() => expect(options[1]).toHaveAttribute('aria-selected', 'true'));

    await user.keyboard('{Enter}');
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.visit).toHaveBeenCalledTimes(1);
    expect(router.visit).toHaveBeenCalledWith(expect.stringMatching(/^\/docs\//));
  });
});
