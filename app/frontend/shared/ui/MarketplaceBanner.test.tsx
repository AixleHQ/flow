import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { MarketplaceBanner } from './MarketplaceBanner';

describe('MarketplaceBanner', () => {
  // Sent only to a workspace AWS bills, and only while it is stopped.
  it('is not drawn for anyone else', () => {
    renderPage(<MarketplaceBanner />, { props: {} });

    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  // The whole reason this exists: the allowance banner withholds itself from
  // this payer, so without it a stopped workspace says nothing at all.
  it('says a cancelled subscription is why nothing starts, and where to renew it', () => {
    renderPage(<MarketplaceBanner />, { props: { marketplace: { status: 'canceled' } } });

    expect(screen.getByRole('status')).toHaveTextContent('subscription has ended');
    expect(screen.getByRole('link', { name: 'Open AWS Marketplace' })).toHaveAttribute(
      'href',
      'https://aws.amazon.com/marketplace/library',
    );
  });

  // Waiting is not a problem to act on, so it is not given an action.
  it('says waiting needs nothing doing, and offers no button', () => {
    renderPage(<MarketplaceBanner />, { props: { marketplace: { status: 'awaiting_subscription' } } });

    expect(screen.getByRole('status')).toHaveTextContent('not confirmed your subscription yet');
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  // A card is a way out once the subscription has ended, but it is offered on
  // the Billing tab beside what AWS was billed this month -- the banner points
  // there rather than opening a checkout of its own.
  it('points at Billing for a card rather than taking one itself', () => {
    renderPage(<MarketplaceBanner />, { props: { marketplace: { status: 'canceled' } } });

    expect(screen.queryByRole('button', { name: /card/i })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Pay by card instead' })).toHaveAttribute(
      'href',
      '/company/settings/billing',
    );
  });
});
