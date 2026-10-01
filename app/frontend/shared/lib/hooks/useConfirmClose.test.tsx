import { Button, Modal, TextInput } from '@mantine/core';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { useConfirmClose } from './useConfirmClose';

function NoteDialog({ onClose }: { onClose: () => void }) {
  const [note, setNote] = useState('');
  const requestClose = useConfirmClose(note !== '', onClose);

  return (
    <Modal opened onClose={requestClose} title="Add note" closeButtonProps={{ 'aria-label': 'Close' }}>
      <TextInput label="Note" value={note} onChange={(e) => setNote(e.currentTarget.value)} />
      <Button onClick={requestClose}>Cancel</Button>
    </Modal>
  );
}

const noteDialog = () => screen.getByRole('dialog', { name: 'Add note' });
const discardDialog = () => screen.findByRole('dialog', { name: 'Discard unsaved changes?' });

describe('useConfirmClose', () => {
  it('closes a pristine dialog straight away, without asking', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.click(within(noteDialog()).getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before closing a dialog with unsaved input, and keeps it open on Keep editing', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.click(within(noteDialog()).getByRole('button', { name: 'Close' }));

    await user.click(within(await discardDialog()).getByRole('button', { name: 'Keep editing' }));

    await waitFor(() =>
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument(),
    );
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByRole('textbox', { name: 'Note' })).toHaveValue('draft');
  });

  it('closes once the user chooses Discard', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    await user.click(within(await discardDialog()).getByRole('button', { name: 'Discard' }));

    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('guards Escape the same way, and Escape on the question means keep editing', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.keyboard('{Escape}');
    await discardDialog();

    await user.keyboard('{Escape}');

    await waitFor(() =>
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument(),
    );
    expect(onClose).not.toHaveBeenCalled();
    expect(noteDialog()).toBeInTheDocument();
  });

  it('asks only once when a second close arrives while the question is open', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    await discardDialog();
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(screen.getAllByRole('dialog', { name: 'Discard unsaved changes?' })).toHaveLength(1);
  });
});
