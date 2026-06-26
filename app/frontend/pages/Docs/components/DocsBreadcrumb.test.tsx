import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';
import { renderPage, screen, within } from 'test/renderPage';
import { DocsBreadcrumb } from './DocsBreadcrumb';

// DocsBreadcrumb is a presentational component that takes `section` and `title`
// via props and renders a Breadcrumb nav with a "Docs" Link plus the two labels.
describe('Docs/components/DocsBreadcrumb', () => {
  it('renders a Breadcrumb navigation landmark', () => {
    renderPage(<DocsBreadcrumb section="User guide" title="Connecting agents" />);

    expect(screen.getByRole('navigation', { name: 'Breadcrumb' })).toBeInTheDocument();
  });

  it('renders the "Docs" home link pointing at /docs', () => {
    renderPage(<DocsBreadcrumb section="User guide" title="Connecting agents" />);

    const docsLink = screen.getByRole('link', { name: 'Docs' });
    expect(docsLink).toHaveAttribute('href', '/docs');
  });

  it('shows the section and title from props', () => {
    renderPage(<DocsBreadcrumb section="Reference manual" title="Webhook payloads" />);

    const breadcrumb = screen.getByRole('navigation', { name: 'Breadcrumb' });
    expect(within(breadcrumb).getByText('Reference manual')).toBeInTheDocument();
    expect(within(breadcrumb).getByText('Webhook payloads')).toBeInTheDocument();
  });

  it('reflects different prop values when re-rendered', () => {
    const { rerender } = renderPage(
      <DocsBreadcrumb section="Getting started" title="Installation" />,
    );
    expect(screen.getByText('Installation')).toBeInTheDocument();

    rerender(<DocsBreadcrumb section="Integrations" title="GitLab setup" />);
    expect(screen.queryByText('Installation')).not.toBeInTheDocument();
    expect(screen.getByText('Integrations')).toBeInTheDocument();
    expect(screen.getByText('GitLab setup')).toBeInTheDocument();
  });

  it('keeps the home link distinct from the current page title', () => {
    renderPage(<DocsBreadcrumb section="User guide" title="Docs overview" />);

    // The "Docs" home link and a page titled "Docs overview" must not collide:
    // only the home link is a link role, the title is plain text.
    expect(screen.getByRole('link', { name: 'Docs' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Docs overview' })).not.toBeInTheDocument();
    expect(screen.getByText('Docs overview')).toBeInTheDocument();
  });
});
