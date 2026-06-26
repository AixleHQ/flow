import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { DocsSidebar } from './DocsSidebar';

// DocsSidebar takes its data via props (currentSlug/onNavigate) and reads the
// static NAV_STRUCTURE import, so renderPage with direct props is sufficient.
describe('Docs/components/DocsSidebar', () => {
  it('renders the navigation landmark and both section labels', () => {
    renderPage(<DocsSidebar currentSlug="agents" />);

    expect(screen.getByRole('navigation', { name: 'Documentation navigation' })).toBeInTheDocument();
    expect(screen.getByText('User guide')).toBeInTheDocument();
    expect(screen.getByText('Reference')).toBeInTheDocument();
  });

  it('renders every leaf nav item as a link pointing at its /docs/<slug> route', () => {
    renderPage(<DocsSidebar currentSlug="agents" />);

    const agents = screen.getByRole('link', { name: 'Agents' });
    expect(agents).toHaveAttribute('href', '/docs/agents');

    expect(screen.getByRole('link', { name: 'Quick start' })).toHaveAttribute('href', '/docs/quick-start');
    expect(screen.getByRole('link', { name: 'MCP servers' })).toHaveAttribute('href', '/docs/mcp');
    expect(screen.getByRole('link', { name: 'CLI reference' })).toHaveAttribute('href', '/docs/cli-ref');
    expect(screen.getByRole('link', { name: 'API' })).toHaveAttribute('href', '/docs/api-guide');
  });

  it('disambiguates the two "Overview" links by their section href', () => {
    renderPage(<DocsSidebar currentSlug="reference" />);

    // "Overview" appears once per section (user-guide & reference).
    const overviews = screen.getAllByRole('link', { name: 'Overview' });
    expect(overviews).toHaveLength(2);
    const hrefs = overviews.map((a) => a.getAttribute('href'));
    expect(hrefs).toEqual(expect.arrayContaining(['/docs/user-guide', '/docs/reference']));
  });

  // These links are real Inertia <Link>s; left alone, a click would trigger
  // the real Router.visit (which has no live page context under jsdom and
  // throws). A capture-phase preventDefault makes Inertia's shouldIntercept()
  // bail out before visiting, while React's synthetic onClick -> onNavigate
  // still fires first.
  function suppressHardNavigation() {
    const handler = (e: Event) => e.preventDefault();
    document.addEventListener('click', handler, true);
    return () => document.removeEventListener('click', handler, true);
  }

  it('fires onNavigate when a nav link is clicked', async () => {
    const restore = suppressHardNavigation();
    const onNavigate = vi.fn();
    renderPage(<DocsSidebar currentSlug="agents" onNavigate={onNavigate} />);

    await userEvent.click(screen.getByRole('link', { name: 'Tools' }));

    expect(onNavigate).toHaveBeenCalledTimes(1);
    restore();
  });

  it('omits onNavigate gracefully and still renders the link when the prop is not provided', async () => {
    const restore = suppressHardNavigation();
    renderPage(<DocsSidebar currentSlug="board" />);

    // Clicking without an onNavigate handler must not throw.
    await userEvent.click(screen.getByRole('link', { name: 'Workflows' }));

    expect(screen.getByRole('link', { name: 'Workflows' })).toHaveAttribute('href', '/docs/workflows');
    restore();
  });

  it('renders all Reference-section items under the navigation landmark', () => {
    renderPage(<DocsSidebar currentSlug="config-schema" />);

    const nav = screen.getByRole('navigation', { name: 'Documentation navigation' });
    expect(within(nav).getByRole('link', { name: 'Configuration reference' })).toHaveAttribute(
      'href',
      '/docs/config-schema',
    );
    expect(within(nav).getByRole('link', { name: 'Integrations' })).toHaveAttribute('href', '/docs/integrations');
  });
});
