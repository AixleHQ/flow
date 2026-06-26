import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';
import DocsPage from './DocsPage';

// DocsPage reads `slug` from usePage().props and renders inside its own DocsLayout
// (not AuthLayout), so renderPage is used directly with a page-specific `slug` prop.
describe('Docs/DocsPage', () => {
  it('renders the not-found branch for an unknown slug (including the default slug)', () => {
    // No props -> slug defaults to 'what-is-aixle', which is not a registered doc page.
    renderPage(<DocsPage />);

    expect(screen.getByRole('heading', { name: 'Page not found' })).toBeInTheDocument();
    expect(screen.getByText(/does not exist yet/)).toBeInTheDocument();
  });

  it('renders a known doc page with its markdown heading and breadcrumb section', () => {
    renderPage(<DocsPage />, { props: { slug: 'agents' } });

    // The markdown body for the agents page starts with `# Agents`.
    expect(screen.getByRole('heading', { name: 'Agents', level: 1 })).toBeInTheDocument();

    // Breadcrumb shows the section the page belongs to.
    const breadcrumb = screen.getByRole('navigation', { name: 'Breadcrumb' });
    expect(within(breadcrumb).getByText('User guide')).toBeInTheDocument();
  });

  it('opens the search modal and navigates to a result via router.visit', async () => {
    renderPage(<DocsPage />, { props: { slug: 'agents' } });

    await userEvent.click(screen.getByRole('button', { name: 'Open search' }));

    const searchInput = await screen.findByRole('textbox', { name: 'Search documentation' });
    // "gitlab" only appears in the Integrations result description -> a single result.
    await userEvent.type(searchInput, 'gitlab');

    const result = await screen.findByRole('button', { name: /Integrations/ });
    await userEvent.click(result);

    await waitFor(() => {
      expect(router.visit).toHaveBeenCalledWith('/docs/integrations');
    });
  });
});
