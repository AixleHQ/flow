import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { LegalLinks } from './LegalLinks';

describe('LegalLinks', () => {
  it('links each published document', () => {
    renderPage(<LegalLinks />, { props: { settings: { legalPages: true } } });

    const nav = screen.getByRole('navigation', { name: 'Legal' });
    expect(nav).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Privacy Policy' })).toHaveAttribute('href', '/legal/privacy_policy');
    expect(screen.getByRole('link', { name: 'Terms of Service' })).toHaveAttribute('href', '/legal/terms_of_service');
    expect(screen.getByRole('link', { name: 'Terms of Use' })).toHaveAttribute('href', '/legal/terms_of_use');
  });

  // A customer-run installation publishes nothing: the links would lead to a 404.
  it('renders nothing where no documents are published', () => {
    renderPage(<LegalLinks />, { props: { settings: { legalPages: false } } });

    expect(screen.queryByRole('navigation', { name: 'Legal' })).not.toBeInTheDocument();
  });

  it('renders nothing for a page from a server that does not say', () => {
    renderPage(<LegalLinks />);

    expect(screen.queryByRole('navigation', { name: 'Legal' })).not.toBeInTheDocument();
  });
});
