import { describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { SelectionBar } from './SelectionBar';

const renderBar = (onBulkTag = vi.fn()) =>
  renderPage(
    <SelectionBar
      active
      selectedCount={2}
      selectedIds={new Set([1, 2])}
      columns={[buildBoardColumn()]}
      members={[{ id: 1, name: 'Dana Scout' }]}
      canExecute
      onAction={vi.fn()}
      onBulkPriority={vi.fn()}
      onBulkAssign={vi.fn()}
      onBulkTag={onBulkTag}
      onClear={vi.fn()}
    />,
  );

const openTagPrompt = async () => {
  await userEvent.click(screen.getByRole('button', { name: 'Add tag' }));
  return screen.findByRole('dialog', { name: 'Add tag' });
};

describe('SelectionBar Add tag prompt', () => {
  it('adds the typed tag to the selection and closes without asking', async () => {
    const onBulkTag = vi.fn();
    renderBar(onBulkTag);

    const prompt = await openTagPrompt();
    await userEvent.type(within(prompt).getByRole('textbox', { name: 'Tag name' }), '  needs-review ');
    await userEvent.click(within(prompt).getByRole('button', { name: 'Add tag' }));

    expect(onBulkTag).toHaveBeenCalledWith('needs-review');
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Add tag' })).not.toBeInTheDocument());
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('adds the tag on Enter', async () => {
    const onBulkTag = vi.fn();
    renderBar(onBulkTag);

    const prompt = await openTagPrompt();
    await userEvent.type(within(prompt).getByRole('textbox', { name: 'Tag name' }), 'blocked{Enter}');

    expect(onBulkTag).toHaveBeenCalledWith('blocked');
  });

  it('asks before discarding a typed tag, and Discard closes the prompt', async () => {
    const onBulkTag = vi.fn();
    renderBar(onBulkTag);

    const prompt = await openTagPrompt();
    await userEvent.type(within(prompt).getByRole('textbox', { name: 'Tag name' }), 'needs-review');
    await userEvent.click(within(prompt).getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(screen.getByRole('dialog', { name: 'Add tag' })).toBeInTheDocument();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Add tag' })).not.toBeInTheDocument());
    expect(onBulkTag).not.toHaveBeenCalled();

    const reopened = await openTagPrompt();
    expect(within(reopened).getByRole('textbox', { name: 'Tag name' })).toHaveValue('');
  });

  it('closes an empty prompt on Escape without asking', async () => {
    renderBar();

    await openTagPrompt();
    await userEvent.keyboard('{Escape}');

    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Add tag' })).not.toBeInTheDocument());
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
