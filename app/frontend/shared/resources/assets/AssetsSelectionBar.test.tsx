import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { AssetsSelectionBar } from './AssetsSelectionBar';

describe('AssetsSelectionBar', () => {
  it('shows the selected count', () => {
    renderPage(
      <AssetsSelectionBar count={3} submitting={false} onMove={vi.fn()} onDelete={vi.fn()} onExit={vi.fn()} />,
    );
    expect(screen.getByText('3 selected')).toBeInTheDocument();
  });

  it('disables Move and Delete when nothing is selected', () => {
    renderPage(
      <AssetsSelectionBar count={0} submitting={false} onMove={vi.fn()} onDelete={vi.fn()} onExit={vi.fn()} />,
    );
    expect(screen.getByRole('button', { name: /move/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /delete/i })).toBeDisabled();
  });

  it('calls onMove, onDelete and onExit', async () => {
    const onMove = vi.fn();
    const onDelete = vi.fn();
    const onExit = vi.fn();
    renderPage(<AssetsSelectionBar count={2} submitting={false} onMove={onMove} onDelete={onDelete} onExit={onExit} />);

    await userEvent.click(screen.getByRole('button', { name: /move/i }));
    await userEvent.click(screen.getByRole('button', { name: /delete/i }));
    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onMove).toHaveBeenCalled();
    expect(onDelete).toHaveBeenCalled();
    expect(onExit).toHaveBeenCalled();
  });

  it('disables the actions while submitting', () => {
    renderPage(<AssetsSelectionBar count={2} submitting onMove={vi.fn()} onDelete={vi.fn()} onExit={vi.fn()} />);
    expect(screen.getByRole('button', { name: /move/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /delete/i })).toBeDisabled();
  });
});
