import '@testing-library/jest-dom/vitest';
import { describe, it, expect, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DocsNavBar } from './DocsNavBar';

describe('DocsNavBar', () => {
  it('renders the brand logo and primary navigation links', () => {
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    // Logo text is split across an accent span; assert the link by its target.
    const logo = screen.getByRole('link', { name: /aixle/i });
    expect(logo).toHaveAttribute('href', '/docs');

    expect(screen.getByRole('link', { name: 'Docs' })).toHaveAttribute('href', '/docs');
    expect(screen.getByRole('link', { name: 'API' })).toHaveAttribute('href', '/docs/api-guide');
    expect(screen.getByRole('link', { name: 'Changelog' })).toHaveAttribute('href', '/changelog');
  });

  it('marks only the active section as the current page', () => {
    renderPage(<DocsNavBar active="api" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    expect(screen.getByRole('link', { name: 'API' })).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: 'Docs' })).not.toHaveAttribute('aria-current');
    expect(screen.getByRole('link', { name: 'Changelog' })).not.toHaveAttribute('aria-current');
  });

  it('renders the GitHub link opening in a new tab safely', () => {
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    const github = screen.getByRole('link', { name: /GitHub/i });
    expect(github).toHaveAttribute('href', 'https://github.com/aixleHQ/flow');
    expect(github).toHaveAttribute('target', '_blank');
    expect(github).toHaveAttribute('rel', 'noopener noreferrer');
  });

  it('shows the repository’s real star count once it has loaded', () => {
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />, {
      props: { githubStars: 2417 },
    });
    expect(screen.getByRole('link', { name: /GitHub/i })).toHaveTextContent('★ 2.4k');
  });

  it('shows no star count while it loads or when GitHub could not be read', () => {
    const { unmount } = renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);
    expect(screen.getByRole('link', { name: /GitHub/i })).not.toHaveTextContent('★');
    unmount();

    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />, {
      props: { githubStars: null },
    });
    expect(screen.getByRole('link', { name: /GitHub/i })).not.toHaveTextContent('★');
  });

  it('shows small star counts in full', () => {
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />, {
      props: { githubStars: 842 },
    });
    expect(screen.getByRole('link', { name: /GitHub/i })).toHaveTextContent('★ 842');
  });

  it('exposes the search trigger with its keyboard shortcut hint', () => {
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    const search = screen.getByRole('button', { name: 'Open search' });
    expect(search).toHaveTextContent('Search docs...');
    expect(search).toHaveTextContent('⌘K');
  });

  it('fires onMenuClick when the hamburger button is pressed', async () => {
    const onMenuClick = vi.fn();
    renderPage(<DocsNavBar active="docs" onMenuClick={onMenuClick} onSearchClick={vi.fn()} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open navigation menu' }));

    expect(onMenuClick).toHaveBeenCalledTimes(1);
  });

  it('fires onSearchClick when the search trigger is pressed', async () => {
    const onSearchClick = vi.fn();
    renderPage(<DocsNavBar active="docs" onMenuClick={vi.fn()} onSearchClick={onSearchClick} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open search' }));

    expect(onSearchClick).toHaveBeenCalledTimes(1);
  });

  it('keeps the two click handlers independent', async () => {
    const onMenuClick = vi.fn();
    const onSearchClick = vi.fn();
    renderPage(<DocsNavBar active="docs" onMenuClick={onMenuClick} onSearchClick={onSearchClick} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open navigation menu' }));

    expect(onMenuClick).toHaveBeenCalledTimes(1);
    expect(onSearchClick).not.toHaveBeenCalled();
  });
});
