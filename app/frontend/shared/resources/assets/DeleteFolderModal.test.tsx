import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DeleteFolderModal } from './DeleteFolderModal';

describe('DeleteFolderModal', () => {
  it('offers a plain confirm-delete for an empty folder', async () => {
    const onConfirm = vi.fn();
    renderPage(
      <DeleteFolderModal
        opened
        onClose={vi.fn()}
        folderLabel="dashboard"
        itemCount={0}
        submitting={false}
        onConfirm={onConfirm}
      />,
    );

    expect(screen.getByText('Delete folder')).toBeInTheDocument();
    expect(
      screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === 'Delete dashboard? This cannot be undone.'),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /delete anyway/i })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /^delete$/i }));
    expect(onConfirm).toHaveBeenCalledWith(false);
  });

  it('warns and offers "Delete anyway" for a non-empty folder, with the item count in the message', async () => {
    const onConfirm = vi.fn();
    renderPage(
      <DeleteFolderModal
        opened
        onClose={vi.fn()}
        folderLabel="dashboard"
        itemCount={3}
        submitting={false}
        onConfirm={onConfirm}
      />,
    );

    expect(screen.getByText('Folder not empty')).toBeInTheDocument();
    expect(screen.getByText(/still has 3 items inside/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^delete$/i })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /delete anyway/i }));
    expect(onConfirm).toHaveBeenCalledWith(true);
  });

  it('uses singular wording for exactly one item', () => {
    renderPage(
      <DeleteFolderModal
        opened
        onClose={vi.fn()}
        folderLabel="dashboard"
        itemCount={1}
        submitting={false}
        onConfirm={vi.fn()}
      />,
    );

    expect(screen.getByText(/still has 1 item inside/i)).toBeInTheDocument();
  });

  it('calls onClose when Cancel is clicked', async () => {
    const onClose = vi.fn();
    renderPage(
      <DeleteFolderModal
        opened
        onClose={onClose}
        folderLabel="dashboard"
        itemCount={0}
        submitting={false}
        onConfirm={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onClose).toHaveBeenCalled();
  });
});
