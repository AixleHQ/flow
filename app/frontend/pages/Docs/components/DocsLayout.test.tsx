import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { type TocItem } from '../data/pages';

import { DocsLayout } from './DocsLayout';

const toc: TocItem[] = [
  { id: 'overview', text: 'Configuration overview', level: 2 },
  { id: 'details', text: 'Nested details', level: 3 },
];

function renderLayout() {
  renderPage(
    <DocsLayout slug="agents" title="Agents page title" section="User guide" toc={toc}>
      <p>Rendered doc body paragraph</p>
    </DocsLayout>,
    {},
  );
}

describe('Docs/components/DocsLayout', () => {
  it('renders the children article content and the breadcrumb title/section', () => {
    renderLayout();

    expect(screen.getByText('Rendered doc body paragraph')).toBeInTheDocument();

    const breadcrumb = screen.getByRole('navigation', { name: 'Breadcrumb' });
    expect(within(breadcrumb).getByText('User guide')).toBeInTheDocument();
    expect(within(breadcrumb).getByText('Agents page title')).toBeInTheDocument();
  });

  it('renders the table of contents headings from the toc prop', () => {
    renderLayout();

    const tocNav = screen.getByRole('navigation', { name: 'Table of contents' });
    expect(within(tocNav).getByText('On this page')).toBeInTheDocument();
    expect(within(tocNav).getByRole('link', { name: 'Configuration overview' })).toBeInTheDocument();
    expect(within(tocNav).getByRole('link', { name: 'Nested details' })).toBeInTheDocument();
  });

  it('renders prev/next navigation links derived from the slug', () => {
    // For slug "agents": prev = "Quick start", next = "Runtimes" in NAV_STRUCTURE.
    renderLayout();

    const pageNav = screen.getByRole('navigation', { name: 'Previous and next pages' });
    const prevLink = within(pageNav).getByRole('link', { name: /Previous/ });
    const nextLink = within(pageNav).getByRole('link', { name: /Next/ });

    expect(prevLink).toHaveAttribute('href', '/docs/quick-start');
    expect(nextLink).toHaveAttribute('href', '/docs/runtimes');
    expect(prevLink).toHaveTextContent('Quick start');
    expect(nextLink).toHaveTextContent('Runtimes');
  });

  it('opens the search modal when the navbar search button is clicked', async () => {
    renderLayout();

    expect(screen.queryByRole('textbox', { name: 'Search documentation' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Open search' }));

    expect(await screen.findByRole('textbox', { name: 'Search documentation' })).toBeInTheDocument();
  });

  it('opens the search modal via the Cmd+K keyboard shortcut', async () => {
    renderLayout();

    expect(screen.queryByRole('textbox', { name: 'Search documentation' })).not.toBeInTheDocument();

    await userEvent.keyboard('{Meta>}k{/Meta}');

    expect(await screen.findByRole('textbox', { name: 'Search documentation' })).toBeInTheDocument();
  });

  it('hides the table of contents when the toc prop is empty', () => {
    renderPage(
      <DocsLayout slug="agents" title="Agents page title" section="User guide" toc={[]}>
        <p>Body without toc</p>
      </DocsLayout>,
      {},
    );

    expect(screen.queryByRole('navigation', { name: 'Table of contents' })).not.toBeInTheDocument();
    expect(screen.getByText('Body without toc')).toBeInTheDocument();
  });
});
