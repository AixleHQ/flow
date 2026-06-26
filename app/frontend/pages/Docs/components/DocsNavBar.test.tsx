import '@testing-library/jest-dom/vitest';
import { describe, it, expect, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DocsNavBar } from './DocsNavBar';

describe('DocsNavBar', () => {
  it('renders the brand logo and primary navigation links', () => {
    renderPage(<DocsNavBar onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    // Logo text is split across an accent span; assert the link by its target.
    const logo = screen.getByRole('link', { name: /aixle/i });
    expect(logo).toHaveAttribute('href', '/docs');

    expect(screen.getByRole('link', { name: 'Docs' })).toHaveAttribute('href', '/docs');
    expect(screen.getByRole('link', { name: 'API' })).toHaveAttribute('href', '/docs/api-guide');
  });

  it('renders the GitHub link opening in a new tab safely', () => {
    renderPage(<DocsNavBar onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    const github = screen.getByRole('link', { name: /GitHub/i });
    expect(github).toHaveAttribute('href', 'https://github.com/palad-ai');
    expect(github).toHaveAttribute('target', '_blank');
    expect(github).toHaveAttribute('rel', 'noopener noreferrer');
    expect(github).toHaveTextContent('★ 2.4k');
  });

  it('exposes the search trigger with its keyboard shortcut hint', () => {
    renderPage(<DocsNavBar onMenuClick={vi.fn()} onSearchClick={vi.fn()} />);

    const search = screen.getByRole('button', { name: 'Open search' });
    expect(search).toHaveTextContent('Search docs...');
    expect(search).toHaveTextContent('⌘K');
  });

  it('fires onMenuClick when the hamburger button is pressed', async () => {
    const onMenuClick = vi.fn();
    renderPage(<DocsNavBar onMenuClick={onMenuClick} onSearchClick={vi.fn()} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open navigation menu' }));

    expect(onMenuClick).toHaveBeenCalledTimes(1);
  });

  it('fires onSearchClick when the search trigger is pressed', async () => {
    const onSearchClick = vi.fn();
    renderPage(<DocsNavBar onMenuClick={vi.fn()} onSearchClick={onSearchClick} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open search' }));

    expect(onSearchClick).toHaveBeenCalledTimes(1);
  });

  it('keeps the two click handlers independent', async () => {
    const onMenuClick = vi.fn();
    const onSearchClick = vi.fn();
    renderPage(<DocsNavBar onMenuClick={onMenuClick} onSearchClick={onSearchClick} />);

    await userEvent.click(screen.getByRole('button', { name: 'Open navigation menu' }));

    expect(onMenuClick).toHaveBeenCalledTimes(1);
    expect(onSearchClick).not.toHaveBeenCalled();
  });
});
