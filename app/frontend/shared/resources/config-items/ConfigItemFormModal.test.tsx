import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { ConfigItemFormModal } from './ConfigItemFormModal';

const basePath = '/projects/1/config_items';

describe('ConfigItemFormModal', () => {
  it('renders the create-mode title and fields when no item is given', () => {
    renderPage(<ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} />);

    expect(screen.getByRole('heading', { name: 'Add secret' })).toBeInTheDocument();
    expect(screen.getByPlaceholderText('API_KEY')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('renders the edit-mode title and pre-fills the name when an item is given', () => {
    const item = { id: 7, name: 'API_KEY', value: 'secret', description: 'A key', itemType: 'variable' };
    renderPage(<ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} item={item} />);

    expect(screen.getByRole('heading', { name: 'Edit secret' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Update' })).toBeInTheDocument();
    expect(screen.getByDisplayValue('API_KEY')).toBeInTheDocument();
  });

  it('submitting a valid create form fires router.post with the config item payload', async () => {
    renderPage(<ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} />);

    await userEvent.type(screen.getByPlaceholderText('API_KEY'), 'MY_VAR');
    await userEvent.type(screen.getByPlaceholderText('Enter value...'), 'hello');
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        basePath,
        { configItem: expect.objectContaining({ name: 'MY_VAR', value: 'hello', itemType: 'variable' }) },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('does NOT fire router.post when required fields are empty (validation blocks)', async () => {
    renderPage(<ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} />);

    // Submit with name + value left empty — zod validation should block the request.
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    expect(router.post).not.toHaveBeenCalled();
  });

  it('clicking Cancel calls onClose', async () => {
    const onClose = vi.fn();
    renderPage(<ConfigItemFormModal opened onClose={onClose} basePath={basePath} />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalled();
  });
});
