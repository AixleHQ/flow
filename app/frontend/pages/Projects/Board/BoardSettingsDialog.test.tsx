import { describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { answerFetch } from 'test/fetchStub';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { BoardSettingsDialog } from './BoardSettingsDialog';

const columns = [
  buildBoardColumn({ id: 100, name: 'Backlog', position: 0 }),
  buildBoardColumn({ id: 200, name: 'In Progress', position: 1 }),
];

const renderDialog = (onClose = vi.fn()) =>
  renderPage(<BoardSettingsDialog opened onClose={onClose} projectId={7} columns={columns} />);

const settingsDialog = () => screen.getByRole('dialog', { name: 'Board Settings' });

describe('BoardSettingsDialog', () => {
  it('closes untouched settings without asking', async () => {
    const onClose = vi.fn();
    renderDialog(onClose);

    await userEvent.click(within(settingsDialog()).getByRole('button', { name: 'Clear' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before discarding a renamed column, and Discard closes', async () => {
    const onClose = vi.fn();
    renderDialog(onClose);

    const [backlog] = within(settingsDialog()).getAllByPlaceholderText('Column name');
    await userEvent.type(backlog, ' later');
    await userEvent.click(within(settingsDialog()).getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    expect(settingsDialog()).toBeInTheDocument();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('treats an added column as unsaved on Escape', async () => {
    const onClose = vi.fn();
    renderDialog(onClose);

    await userEvent.click(within(settingsDialog()).getByRole('button', { name: 'Add Column' }));
    await userEvent.keyboard('{Escape}');

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('closes without asking once the edits are saved', async () => {
    const fetchSpy = answerFetch({ 'PATCH /api/v1/projects/7/columns/:id': {} });
    const onClose = vi.fn();
    renderDialog(onClose);

    const [backlog] = within(settingsDialog()).getAllByPlaceholderText('Column name');
    await userEvent.type(backlog, ' later');
    await userEvent.click(within(settingsDialog()).getByRole('button', { name: 'Save' }));

    await waitFor(() => expect(onClose).toHaveBeenCalledTimes(1));
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/columns/100',
      expect.objectContaining({ method: 'PATCH' }),
    );
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
