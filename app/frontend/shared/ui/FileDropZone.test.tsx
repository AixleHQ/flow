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

  it('ignores drops while disabled', () => {
    const onFiles = vi.fn();
    renderPage(<FileDropZone onFiles={onFiles} hint="hint" disabled />);

    fireEvent.drop(screen.getByText('Click to select files or drag & drop'), {
      dataTransfer: { files: [file('a.txt')] },
    });

    expect(onFiles).not.toHaveBeenCalled();
  });
});
