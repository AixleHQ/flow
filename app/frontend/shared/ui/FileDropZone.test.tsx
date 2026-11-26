import '@testing-library/jest-dom/vitest';
import { fireEvent } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { FileDropZone } from './FileDropZone';

const file = (name: string) => new File(['x'], name, { type: 'text/plain' });

describe('shared/ui/FileDropZone', () => {
  it('passes every dropped file to onFiles', () => {
    const onFiles = vi.fn();
    renderPage(<FileDropZone onFiles={onFiles} hint="Max 1 GB" />);

    const files = [file('a.txt'), file('b.txt'), file('c.txt')];
    fireEvent.drop(screen.getByText('Click to select files or drag & drop'), { dataTransfer: { files } });

    expect(onFiles).toHaveBeenCalledWith(files);
    expect(screen.getByText('Max 1 GB')).toBeInTheDocument();
  });

  it('accepts several files in its picker', async () => {
    const onFiles = vi.fn();
    renderPage(<FileDropZone onFiles={onFiles} hint="hint" />);

    const input = screen.getByLabelText('Select files');
    expect(input).toHaveAttribute('multiple');
    const files = [file('a.txt'), file('b.txt')];
    await userEvent.setup().upload(input, files);

    expect(onFiles).toHaveBeenCalledWith(files);
  });

  it('opens its picker when clicked', async () => {
    renderPage(<FileDropZone onFiles={vi.fn()} hint="hint" />);
    const opened = vi.fn();
    screen.getByLabelText('Select files').addEventListener('click', opened);

    await userEvent.setup().click(screen.getByRole('button', { name: /Click to select files/ }));

    expect(opened).toHaveBeenCalledTimes(1);
  });

  it('opens its picker with Enter or Space once tabbed to', async () => {
    const user = userEvent.setup();
    renderPage(<FileDropZone onFiles={vi.fn()} hint="hint" />);
    const opened = vi.fn();
    screen.getByLabelText('Select files').addEventListener('click', opened);

    await user.tab();
    expect(screen.getByRole('button', { name: /Click to select files/ })).toHaveFocus();
    await user.keyboard('{Enter}');
    await user.keyboard(' ');

    expect(opened).toHaveBeenCalledTimes(2);
  });

  it('ignores drops and clicks, and leaves the tab order, while disabled', async () => {
    const user = userEvent.setup();
    const onFiles = vi.fn();
    renderPage(<FileDropZone onFiles={onFiles} hint="hint" disabled />);
    const opened = vi.fn();
    screen.getByLabelText('Select files').addEventListener('click', opened);
    const zone = screen.getByRole('button', { name: /Click to select files/ });

    await user.tab();
    expect(zone).not.toHaveFocus();
    expect(zone).toHaveAttribute('aria-disabled', 'true');

    fireEvent.drop(zone, { dataTransfer: { files: [file('a.txt')] } });
    await user.click(zone);

    expect(onFiles).not.toHaveBeenCalled();
    expect(opened).not.toHaveBeenCalled();
  });
});
