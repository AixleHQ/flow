import '@testing-library/jest-dom/vitest';
import Markdown from 'react-markdown';
import { describe, expect, it, vi } from 'vitest';

import { renderPage as render, screen, userEvent } from 'test/renderPage';

import { MarkdownLink } from './MarkdownLink';

const renderMarkdown = (source: string) => render(<Markdown components={{ a: MarkdownLink }}>{source}</Markdown>);

describe('MarkdownLink', () => {
  it('opens a link to another site in a new tab', () => {
    renderMarkdown('See [the PR](https://github.com/acme/app/pull/7).');

    const link = screen.getByRole('link', { name: 'the PR' });
    expect(link).toHaveAttribute('href', 'https://github.com/acme/app/pull/7');
    expect(link).toHaveAttribute('target', '_blank');
    expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  });

  it('keeps links within Flow in the same tab', () => {
    renderMarkdown(
      `[relative](/company/projects/1/board) and [absolute](${window.location.origin}/company/projects/1/board)`,
    );

    for (const name of ['relative', 'absolute']) {
      const link = screen.getByRole('link', { name });
      expect(link).not.toHaveAttribute('target');
      expect(link).not.toHaveAttribute('rel');
    }
  });

  it('does not send a mail link to a blank tab', () => {
    renderMarkdown('[Mail us](mailto:team@example.com)');

    expect(screen.getByRole('link', { name: 'Mail us' })).not.toHaveAttribute('target');
  });

  it('does not pass the click on to the surrounding element', async () => {
    const onContainerClick = vi.fn();
    render(
      <div onClick={onContainerClick}>
        <Markdown components={{ a: MarkdownLink }}>[docs](#install)</Markdown>
      </div>,
    );

    await userEvent.click(screen.getByRole('link', { name: 'docs' }));

    expect(onContainerClick).not.toHaveBeenCalled();
  });
});
