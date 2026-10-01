import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { ConfigItemFormModal } from './ConfigItemFormModal';

const basePath = '/projects/1/config_items';
const editDialogX = () =>
  within(screen.getByRole('dialog', { name: 'Edit secret' })).getByRole('button', { name: 'Clear' });

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

  it("edits a variable in place and never pre-fills a secret's value", () => {
    const variable = { id: 7, name: 'REGION', value: 'eu-west-1', description: null, itemType: 'variable' };
    const { unmount } = renderPage(
      <ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} item={variable} />,
    );
    expect(screen.getByDisplayValue('eu-west-1')).toBeInTheDocument();
    unmount();

    const secret = { id: 8, name: 'API_KEY', value: '••••••••', description: null, itemType: 'secret' };
    renderPage(<ConfigItemFormModal opened onClose={vi.fn()} basePath={basePath} item={secret} />);
    expect(screen.queryByDisplayValue('••••••••')).not.toBeInTheDocument();
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

  it('clicking Cancel on an untouched form closes it without asking', async () => {
    const onClose = vi.fn();
    renderPage(<ConfigItemFormModal opened onClose={onClose} basePath={basePath} />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('closes an untouched edit without asking', async () => {
    const onClose = vi.fn();
    const item = { id: 7, name: 'REGION', value: 'eu-west-1', description: 'Deploy region', itemType: 'variable' };
    renderPage(<ConfigItemFormModal opened onClose={onClose} basePath={basePath} item={item} />);

    expect(screen.getByDisplayValue('eu-west-1')).toBeInTheDocument();
    await userEvent.click(editDialogX());

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before closing over a typed value, and closes once the user discards', async () => {
    const onClose = vi.fn();
    renderPage(<ConfigItemFormModal opened onClose={onClose} basePath={basePath} />);

    await userEvent.type(screen.getByPlaceholderText('API_KEY'), 'MY_VAR');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('asks before closing an edit through its X once the value changed', async () => {
    const onClose = vi.fn();
    const item = { id: 8, name: 'API_KEY', value: '••••••••', description: null, itemType: 'secret' };
    renderPage(<ConfigItemFormModal opened onClose={onClose} basePath={basePath} item={item} />);

    await userEvent.type(screen.getByPlaceholderText('Enter secret value...'), 'rotated');
    await userEvent.click(editDialogX());

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });
});
