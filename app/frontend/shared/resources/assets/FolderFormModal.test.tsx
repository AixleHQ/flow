import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { FolderFormModal } from './FolderFormModal';

describe('FolderFormModal', () => {
  it('titles itself "New folder" and shows where the folder will be created', () => {
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        parentLabel="dashboard"
        existingNames={[]}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    expect(screen.getByText('New folder')).toBeInTheDocument();
    expect(screen.getByText(/creating inside: dashboard/i)).toBeInTheDocument();
  });

  it('falls back to "Assets (root)" when there is no parent label', () => {
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        parentLabel=""
        existingNames={[]}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    expect(screen.getByText(/creating inside: assets \(root\)/i)).toBeInTheDocument();
  });

  it('titles itself "Rename folder" and pre-fills the current name', () => {
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="rename"
        initialName="dashboard"
        existingNames={['dashboard', 'archive']}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    expect(screen.getByText('Rename folder')).toBeInTheDocument();
    expect(screen.getByDisplayValue('dashboard')).toBeInTheDocument();
  });

  it('rejects an empty name without calling onSubmit', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(screen.getByText('Folder name is required.')).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('rejects a name containing a slash', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), 'a/b');
    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(screen.getByText(/can’t contain "\/"/)).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('rejects ".." so a folder can never name its own parent', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), '..');
    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(screen.getByText('".." is not a usable folder name.')).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  // Asset folders have always been free-form labels; the folder view must not be narrower.
  it('accepts a name with a space and non-Latin characters', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), 'Отчёты (Q3)');
    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(onSubmit).toHaveBeenCalledWith('Отчёты (Q3)');
  });

  it('rejects a name colliding with an existing sibling', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={['archive']}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), 'archive');
    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(screen.getByText(/already exists here/i)).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('allows renaming to the folder’s own current name (a no-op)', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="rename"
        initialName="dashboard"
        existingNames={['dashboard']}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /^save$/i }));

    expect(onSubmit).toHaveBeenCalledWith('dashboard');
  });

  it('submits a trimmed, valid name', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), '  specs  ');
    await userEvent.click(screen.getByRole('button', { name: /^create$/i }));

    expect(onSubmit).toHaveBeenCalledWith('specs');
  });

  it('submits on Enter', async () => {
    const onSubmit = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={onSubmit}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), 'specs{Enter}');

    expect(onSubmit).toHaveBeenCalledWith('specs');
  });

  it('shows a server-side error and disables the form while submitting', () => {
    renderPage(
      <FolderFormModal
        opened
        onClose={vi.fn()}
        mode="create"
        existingNames={[]}
        submitting
        serverError="Parent folder does not exist."
        onSubmit={vi.fn()}
      />,
    );

    expect(screen.getByText('Parent folder does not exist.')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('e.g. specs')).toBeDisabled();
  });

  it('calls onClose when Cancel is clicked', async () => {
    const onClose = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={onClose}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onClose).toHaveBeenCalled();
  });

  it('asks before discarding a typed folder name, and closes on Discard', async () => {
    const onClose = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={onClose}
        mode="create"
        existingNames={[]}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('e.g. specs'), 'specs');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(screen.getByRole('dialog', { name: 'New folder' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('asks before the X discards a changed name in a rename', async () => {
    const onClose = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={onClose}
        mode="rename"
        initialName="dashboard"
        existingNames={['dashboard']}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    const field = screen.getByDisplayValue('dashboard');
    await userEvent.clear(field);
    await userEvent.type(field, 'reports');
    await userEvent.click(
      within(screen.getByRole('dialog', { name: 'Rename folder' })).getByRole('button', { name: 'Clear' }),
    );

    expect(await screen.findByRole('dialog', { name: 'Discard unsaved changes?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('closes an untouched rename without asking', async () => {
    const onClose = vi.fn();
    renderPage(
      <FolderFormModal
        opened
        onClose={onClose}
        mode="rename"
        initialName="dashboard"
        existingNames={['dashboard']}
        submitting={false}
        onSubmit={vi.fn()}
      />,
    );

    await userEvent.click(
      within(screen.getByRole('dialog', { name: 'Rename folder' })).getByRole('button', { name: 'Clear' }),
    );

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
