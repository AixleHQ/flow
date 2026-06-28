import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { DocsCodeBlock } from './DocsCodeBlock';

// DocsCodeBlock is presentational and takes its data via props, so renderPage is
// used directly. It renders two shapes: an inline <code> (when `inline`) and a
// full code block with a language label + copy button driven by navigator.clipboard.
describe('Docs/components/DocsCodeBlock', () => {
  it('renders inline code without a copy button', () => {
    renderPage(<DocsCodeBlock inline>const answer = 42</DocsCodeBlock>);

    expect(screen.getByText('const answer = 42')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Copy code to clipboard' })).not.toBeInTheDocument();
  });

  it('renders a block with the mapped language label and a Copy button', () => {
    renderPage(<DocsCodeBlock className="language-ruby">puts &apos;hi&apos;</DocsCodeBlock>);

    // `ruby` maps to the human label "Ruby".
    expect(screen.getByText('Ruby')).toBeInTheDocument();
    const copyButton = screen.getByRole('button', { name: 'Copy code to clipboard' });
    expect(copyButton).toHaveTextContent('Copy');
  });

  it('falls back to the raw language key when it is not in the label map', () => {
    renderPage(<DocsCodeBlock className="language-rust">fn main() {}</DocsCodeBlock>);

    // `rust` is not in LANGUAGE_LABELS, so the raw key is shown.
    expect(screen.getByText('rust')).toBeInTheDocument();
  });

  it('omits the language label for the empty-string `text` mapping', () => {
    renderPage(<DocsCodeBlock className="language-text">plain content here</DocsCodeBlock>);

    // `text` maps to '' which is falsy -> no <span> label rendered.
    const block = screen.getByRole('button', { name: 'Copy code to clipboard' });
    expect(block).toBeInTheDocument();
    expect(screen.queryByText('text')).not.toBeInTheDocument();
  });

  it('copies the code to the clipboard and flips the button label to Copied', async () => {
    // userEvent.setup() installs its own clipboard stub, so override AFTER setup
    // to make this spy the one DocsCodeBlock's handleCopy actually calls.
    const user = userEvent.setup();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });

    renderPage(<DocsCodeBlock className="language-bash">echo hello</DocsCodeBlock>);

    await user.click(screen.getByRole('button', { name: 'Copy code to clipboard' }));

    expect(writeText).toHaveBeenCalledWith('echo hello');
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Copy code to clipboard' })).toHaveTextContent('Copied');
    });
  });

  it('shows a notification when the clipboard write fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const user = userEvent.setup();
    // Override AFTER setup so the rejecting spy is the clipboard handleCopy uses.
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error('denied')) },
    });

    renderPage(<DocsCodeBlock className="language-bash">echo boom</DocsCodeBlock>);

    await user.click(screen.getByRole('button', { name: 'Copy code to clipboard' }));

    await waitFor(() => {
      expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Failed to copy', color: 'red' }));
    });
    // On failure the button stays in its default "Copy" state.
    expect(screen.getByRole('button', { name: 'Copy code to clipboard' })).toHaveTextContent('Copy');

    showSpy.mockRestore();
  });
});
