import { router } from '@inertiajs/react';
import { Button, Modal, TextInput } from '@mantine/core';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';

import { visitHeld } from 'test/inertiaVisit';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { confirmLeave } from './guards';
import { useUnsavedChanges } from './useUnsavedChanges';

function NoteDialog({ onClose }: { onClose: () => void }) {
  const [note, setNote] = useState('');
  const requestClose = useUnsavedChanges({ dirty: note !== '', saving: false, onClose });

  return (
    <Modal opened onClose={requestClose} title="Add note" closeButtonProps={{ 'aria-label': 'Close' }}>
      <TextInput label="Note" value={note} onChange={(e) => setNote(e.currentTarget.value)} />
      <Button onClick={requestClose}>Cancel</Button>
    </Modal>
  );
}

function NameForm({
  label = 'Name',
  saving = false,
  onSave,
}: {
  label?: string;
  saving?: boolean;
  onSave?: (name: string) => Promise<boolean>;
}) {
  const [saved, setSaved] = useState('Acme');
  const [name, setName] = useState('Acme');
  useUnsavedChanges({
    dirty: name !== saved,
    saving,
    onSave: onSave
      ? async () => {
          const ok = await onSave(name);
          if (ok) setSaved(name);
          return ok;
        }
      : undefined,
  });

  return <TextInput label={label} value={name} onChange={(e) => setName(e.currentTarget.value)} />;
}

const noteDialog = () => screen.getByRole('dialog', { name: 'Add note' });
const discardQuestion = () => screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
const saveQuestion = () => screen.findByRole('dialog', { name: 'Save your changes?' });

const elsewhere = '/company/projects';
const elsewhereUrl = () => new URL(elsewhere, window.location.origin).href;

describe('useUnsavedChanges — closing the form', () => {
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
    await user.click(within(await discardQuestion()).getByRole('button', { name: 'Keep editing' }));

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
    await user.click(within(await discardQuestion()).getByRole('button', { name: 'Discard' }));

    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('does not ask once the input is changed back to what it was', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    const note = screen.getByRole('textbox', { name: 'Note' });
    await user.type(note, 'x');
    await user.clear(note);
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('guards Escape the same way, and Escape on the question means keep editing', async () => {
    const user = userEvent.setup();
    const onClose = vi.fn();
    renderPage(<NoteDialog onClose={onClose} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.keyboard('{Escape}');
    await discardQuestion();

    await user.keyboard('{Escape}');

    await waitFor(() =>
      expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument(),
    );
    expect(onClose).not.toHaveBeenCalled();
    expect(noteDialog()).toBeInTheDocument();
  });

  it('asks only once when a second close arrives while the question is open', async () => {
    const user = userEvent.setup();
    renderPage(<NoteDialog onClose={vi.fn()} />);

    await user.type(screen.getByRole('textbox', { name: 'Note' }), 'draft');
    await user.click(screen.getByRole('button', { name: 'Cancel' }));
    await discardQuestion();
    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(screen.getAllByRole('dialog', { name: 'Discard unsaved changes?' })).toHaveLength(1);
  });
});

describe('useUnsavedChanges — leaving the page', () => {
  it('lets a visit through while nothing is dirty', () => {
    renderPage(<NameForm />);

    expect(visitHeld(elsewhere)).toBe(false);
  });

  it('holds a visit to another page and makes it once the user discards', async () => {
    const user = userEvent.setup();
    renderPage(<NameForm />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    expect(visitHeld(elsewhere)).toBe(true);
    expect(router.visit).not.toHaveBeenCalled();

    await user.click(within(await discardQuestion()).getByRole('button', { name: 'Discard' }));

    expect(router.visit).toHaveBeenCalledWith(elsewhereUrl(), expect.objectContaining({ method: 'get' }));
  });

  it('lets a visit through while the form is saving, and holds it again once the save ends', async () => {
    const user = userEvent.setup();
    const { rerender } = renderPage(<NameForm saving />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    expect(visitHeld(elsewhere)).toBe(false);

    rerender(<NameForm saving={false} />);

    expect(visitHeld(elsewhere)).toBe(true);
  });

  it('stays on the page on Keep editing', async () => {
    const user = userEvent.setup();
    renderPage(<NameForm />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    visitHeld(elsewhere);
    await user.click(within(await discardQuestion()).getByRole('button', { name: 'Keep editing' }));

    expect(router.visit).not.toHaveBeenCalled();
    expect(screen.getByRole('textbox', { name: 'Name' })).toHaveValue('Acme Inc');
  });

  it('does not ask for a save, a reload of this page or a prefetch', async () => {
    const user = userEvent.setup();
    renderPage(<NameForm />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    const here = `${window.location.pathname}?tab=x`;
    expect(visitHeld(elsewhere, { method: 'patch' })).toBe(false);
    expect(visitHeld(here)).toBe(false);
    expect(visitHeld(elsewhere, { prefetch: true })).toBe(false);
  });

  it('saves, then leaves, when the user picks Save', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(true);
    renderPage(<NameForm onSave={onSave} />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    visitHeld(elsewhere);
    await user.click(within(await saveQuestion()).getByRole('button', { name: 'Save' }));

    expect(onSave).toHaveBeenCalledWith('Acme Inc');
    await waitFor(() => expect(router.visit).toHaveBeenCalledWith(elsewhereUrl(), expect.anything()));
  });

  it('stays when the save fails, and asks again on the next leave', async () => {
    const user = userEvent.setup();
    renderPage(<NameForm onSave={vi.fn().mockResolvedValue(false)} />);
    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

    visitHeld(elsewhere);
    await user.click(within(await saveQuestion()).getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Save your changes?' })).not.toBeInTheDocument());

    expect(router.visit).not.toHaveBeenCalled();
    await waitFor(() => expect(visitHeld(elsewhere)).toBe(true));
  });

  it('asks once for two dirty forms, and offers no Save that would keep only one of them', async () => {
    const user = userEvent.setup();
    renderPage(
      <>
        <NameForm label="First" onSave={vi.fn().mockResolvedValue(true)} />
        <NameForm label="Second" onSave={vi.fn().mockResolvedValue(true)} />
      </>,
    );
    await user.type(screen.getByRole('textbox', { name: 'First' }), '1');
    await user.type(screen.getByRole('textbox', { name: 'Second' }), '2');

    visitHeld(elsewhere);
    const question = await discardQuestion();

    expect(screen.getAllByRole('dialog', { name: 'Discard unsaved changes?' })).toHaveLength(1);
    expect(within(question).queryByRole('button', { name: 'Save' })).not.toBeInTheDocument();
  });

  it('asks before signing out over a dirty form, and signs out on Discard', async () => {
    const user = userEvent.setup();
    const signOut = vi.fn();
    renderPage(<NameForm />);

    confirmLeave(signOut);
    expect(signOut).toHaveBeenCalledTimes(1);

    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');
    confirmLeave(signOut);
    expect(signOut).toHaveBeenCalledTimes(1);

    await user.click(within(await discardQuestion()).getByRole('button', { name: 'Discard' }));
    expect(signOut).toHaveBeenCalledTimes(2);
  });

  it('asks the browser to confirm a reload or tab close only while dirty', async () => {
    const user = userEvent.setup();
    renderPage(<NameForm />);

    const pristine = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(pristine);
    expect(pristine.defaultPrevented).toBe(false);

    await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');
    const dirty = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(dirty);
    expect(dirty.defaultPrevented).toBe(true);
  });

  it('holds browser back, puts the page back on Keep editing, and goes back on Discard', async () => {
    const user = userEvent.setup();
    const inertiaPopstate = vi.fn();
    window.history.replaceState({ page: 'previous' }, '', '/previous');
    window.history.pushState({ page: 'form' }, '', '/form');
    window.addEventListener('popstate', inertiaPopstate);
    try {
      renderPage(<NameForm />);
      await user.type(screen.getByRole('textbox', { name: 'Name' }), ' Inc');

      window.history.back();
      const question = await discardQuestion();
      expect(inertiaPopstate).not.toHaveBeenCalled();
      expect(window.location.pathname).toBe('/form');
      await user.click(within(question).getByRole('button', { name: 'Keep editing' }));
      await waitFor(() =>
        expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument(),
      );
      expect(window.location.pathname).toBe('/form');

      window.history.back();
      await user.click(within(await discardQuestion()).getByRole('button', { name: 'Discard' }));

      await waitFor(() => expect(inertiaPopstate).toHaveBeenCalledTimes(1));
      expect(inertiaPopstate.mock.calls[0][0].state).toEqual({ page: 'previous' });
      expect(window.location.pathname).toBe('/previous');
    } finally {
      window.removeEventListener('popstate', inertiaPopstate);
    }
  });
});
