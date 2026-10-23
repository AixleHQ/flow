import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import MarketplaceLandingPage from './LandingPage';

describe('MarketplaceLandingPage', () => {
  it('sends a visitor back to their AWS subscription', () => {
    renderPage(<MarketplaceLandingPage />);

    expect(screen.getByRole('link', { name: 'Go to AWS Marketplace' })).toHaveAttribute(
      'href',
      'https://aws.amazon.com/marketplace/library',
    );
  });

  it('offers sign-in to whoever already finished', () => {
    renderPage(<MarketplaceLandingPage />);

    expect(screen.getByRole('link', { name: 'Sign in' })).toHaveAttribute('href', '/login');
  });
});
