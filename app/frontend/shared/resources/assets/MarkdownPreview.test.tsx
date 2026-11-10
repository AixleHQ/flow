import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { MarkdownPreview } from './MarkdownPreview';

describe('MarkdownPreview', () => {
  it('never executes or renders script, event handlers, iframes or javascript: links', () => {
    const source = [
      '<script>window.__pwned = 1</script>',
      '',
      '<img src="x" onerror="window.__pwned = 2">',
      '',
      '<iframe src="https://evil.example"></iframe>',
      '',
      '[click](javascript:alert(1))',
    ].join('\n');
    renderPage(<MarkdownPreview source={source} />);

    expect(document.querySelector('script')).toBeNull();
    expect(document.querySelector('iframe')).toBeNull();
    expect(document.querySelector('[onerror]')).toBeNull();
    expect(document.querySelector('a[href^="javascript"]')).toBeNull();
    expect((window as unknown as { __pwned?: number }).__pwned).toBeUndefined();
  });

  it('opens absolute links safely in a new tab', () => {
    renderPage(<MarkdownPreview source="[docs](https://example.com/docs)" />);

    const link = screen.getByRole('link', { name: 'docs' });
    expect(link).toHaveAttribute('href', 'https://example.com/docs');
    expect(link).toHaveAttribute('target', '_blank');
    expect(link).toHaveAttribute('rel', 'noopener noreferrer');
  });

  it('degrades relative links and anchors to plain text', () => {
    renderPage(<MarkdownPreview source="[other](./other.md) and [top](#top)" />);

    expect(screen.queryByRole('link')).not.toBeInTheDocument();
    expect(screen.getByText('other')).toBeInTheDocument();
    expect(screen.getByText('top')).toBeInTheDocument();
  });

  it('renders https images only and falls back to the alt text for the rest', () => {
    renderPage(
      <MarkdownPreview
        source={'![remote](https://example.com/a.png)\n\n![local](./a.png)\n\n![http](http://example.com/a.png)'}
      />,
    );

    expect(screen.getByRole('img', { name: 'remote' })).toHaveAttribute('src', 'https://example.com/a.png');
    expect(screen.queryByRole('img', { name: 'local' })).not.toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'http' })).not.toBeInTheDocument();
    expect(screen.getByText('local')).toBeInTheDocument();
    expect(screen.getByText('http')).toBeInTheDocument();
  });
});
