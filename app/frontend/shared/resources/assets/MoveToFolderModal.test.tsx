import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { MoveToFolderModal } from './MoveToFolderModal';

describe('MoveToFolderModal', () => {
  it('titles itself with the subject being moved and lists root plus every folder', () => {
    renderPage(
      <MoveToFolderModal
        opened
        onClose={vi.fn()}
        subjectLabel="3 files"
        folderPaths={['dashboard', 'dashboard/specs', 'archive']}
        submitting={false}
        onConfirm={vi.fn()}
      />,
    );

    expect(screen.getByText('Move 3 files')).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /assets \(root\)/i })).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'dashboard' })).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'dashboard/specs' })).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'archive' })).toBeInTheDocument();
  });

  it('disables the Move button until a destination is picked', async () => {
    const onConfirm = vi.fn();
    renderPage(
      <MoveToFolderModal
        opened
        onClose={vi.fn()}
        subjectLabel="report.pdf"
        folderPaths={['dashboard']}
        submitting={false}
        onConfirm={onConfirm}
      />,
    );

    expect(screen.getByRole('button', { name: /move here/i })).toBeDisabled();

    await userEvent.click(screen.getByRole('radio', { name: 'dashboard' }));
    expect(screen.getByRole('button', { name: /move here/i })).toBeEnabled();

    await userEvent.click(screen.getByRole('button', { name: /move here/i }));
    expect(onConfirm).toHaveBeenCalledWith('dashboard');
  });

  it('allows picking root as a destination', async () => {
    const onConfirm = vi.fn();
    renderPage(
      <MoveToFolderModal
        opened
        onClose={vi.fn()}
        subjectLabel="report.pdf"
        folderPaths={['dashboard']}
        submitting={false}
        onConfirm={onConfirm}
      />,
    );

    await userEvent.click(screen.getByRole('radio', { name: /assets \(root\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /move here/i }));

    expect(onConfirm).toHaveBeenCalledWith('');
  });

  it('disables a folder listed as a disabled destination and ignores clicks on it', async () => {
    renderPage(
      <MoveToFolderModal
        opened
        onClose={vi.fn()}
        subjectLabel="dashboard"
        folderPaths={['dashboard', 'dashboard/specs', 'archive']}
        disabledPaths={['dashboard', 'dashboard/specs']}
        submitting={false}
        onConfirm={vi.fn()}
      />,
    );

    const dashboardOption = screen.getByRole('radio', { name: 'dashboard' });
    expect(dashboardOption).toHaveAttribute('aria-disabled', 'true');

    await userEvent.click(dashboardOption);
    expect(screen.getByRole('button', { name: /move here/i })).toBeDisabled();
  });

  it('calls onClose when Cancel is clicked', async () => {
    const onClose = vi.fn();
    renderPage(
      <MoveToFolderModal
        opened
        onClose={onClose}
        subjectLabel="report.pdf"
        folderPaths={[]}
        submitting={false}
        onConfirm={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onClose).toHaveBeenCalled();
  });
});
