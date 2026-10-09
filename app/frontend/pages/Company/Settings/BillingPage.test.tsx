import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { buildSharedPermissions } from 'test/factories/sharedProps';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import BillingPage from './BillingPage';

const REASONS = [
  'too_expensive',
  'missing_features',
  'unused',
  'switched_service',
  'too_complex',
  'low_quality',
  'customer_service',
  'other',
];

const billing = {
  status: 'active' as const,
  periodStartsAt: '2026-10-01T00:00:00Z',
  periodEndsAt: '2026-11-01T12:00:00Z',
  cancelsAt: null,
  usage: {
    workerMinutes: 130,
    measuredUntil: '2026-10-02T11:00:00Z',
    estimate: { amountCents: 1000, currency: 'usd', unitAmountCents: 500, minutesPerUnit: 60 },
  },
  allowance: null,
  canPay: true,
  hasUnpaidInvoice: false,
  cancellationReasons: REASONS,
};

const render = (
  overrides: Partial<typeof billing> | Record<string, unknown> = {},
  checkoutResult: string | null = null,
) =>
  renderAuthedPage(<BillingPage />, {
    props: {
      company: { name: 'Acme Robotics' },
      billing: { ...billing, ...overrides },
      checkoutResult,
      permissions: buildSharedPermissions({ canManageBilling: true }),
    },
  });

describe('Company billing page', () => {
  it('shows what this period has come to so far', () => {
    render();

    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText('130')).toBeInTheDocument();
    expect(screen.getByText('$10.00')).toBeInTheDocument();
    expect(screen.getByText(/Billed at \$5\.00 per 60 worker-minutes/)).toBeInTheDocument();
  });

  it('is the third tab of company settings for an admin', () => {
    render();

    expect(screen.getByRole('tab', { name: 'Billing', selected: true })).toBeInTheDocument();
  });

  // Two steps: the action, then the confirmation that says what happens.
  it('explains the consequences before cancelling, and sends the chosen reason', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel subscription' }));
    const dialog = await screen.findByRole('dialog');
    expect(dialog).toHaveTextContent('It stops now');
    expect(dialog).toHaveTextContent('Usage up to now is billed on a final invoice');
    expect(dialog).toHaveTextContent('Projects, workflows and history are kept');

    await userEvent.click(within(dialog).getByRole('combobox', { name: /Why are you cancelling/ }));
    await userEvent.click(await screen.findByRole('option', { name: 'It costs too much' }));
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel subscription' }));

    await waitFor(() => expect(post).toHaveBeenCalled());
    expect(post.mock.calls[0][0]).toBe('/company/billing_cancellation');
    expect(post.mock.calls[0][1]).toEqual({ reason: 'too_expensive', comment: '' });
  });

  it('asks for more only when the reason is Other', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel subscription' }));
    const dialog = await screen.findByRole('dialog');
    expect(screen.queryByRole('textbox', { name: 'Tell us more' })).not.toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('combobox', { name: /Why are you cancelling/ }));
    await userEvent.click(await screen.findByRole('option', { name: 'Other' }));
    await userEvent.type(screen.getByRole('textbox', { name: 'Tell us more' }), 'Moving in-house');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel subscription' }));

    await waitFor(() => expect(post).toHaveBeenCalled());
    expect(post.mock.calls[0][1]).toEqual({ reason: 'other', comment: 'Moving in-house' });
  });

  it('lets a scheduled cancellation be taken back', async () => {
    const destroy = vi.spyOn(router, 'delete').mockImplementation(() => undefined);
    render({ status: 'cancelling', cancelsAt: '2026-11-01T12:00:00Z' });

    expect(screen.getByText(/the subscription ends and no new sessions start/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Keep subscription' }));

    expect(destroy).toHaveBeenCalledWith('/company/billing_cancellation', expect.anything());
  });

  // A new card would open a second subscription and bill the same minutes twice.
  it('offers the open invoice after a failed payment, not a new card', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render({ status: 'payment_failed', hasUnpaidInvoice: true, usage: null });

    expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Pay invoice' }));

    expect(post.mock.calls[0][0]).toBe('/company/billing_invoice_payment');
  });

  it('offers a card, and nothing to cancel, to a workspace on free capacity', () => {
    render({ status: 'trialing', usage: null, allowance: { hours: 100, usedHours: 40 } });

    expect(screen.getByText(/40 of 100 worker-hours used/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
  });

  it('offers a card to bring back a workspace whose subscription ended', () => {
    render({ status: 'canceled', cancelsAt: '2026-10-01T12:00:00Z', usage: null });

    expect(screen.getByText(/the subscription ended/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  // Stripe confirms the card by webhook, which can land after the redirect back.
  it('says the card is being confirmed when Checkout returns before the webhook', () => {
    render({ status: 'trialing', usage: null, allowance: { hours: 100, usedHours: 40 } }, 'done');

    expect(screen.getByText('Card received')).toBeInTheDocument();
  });

  it('says nothing was charged when card entry was abandoned', () => {
    render({}, 'cancelled');

    expect(screen.getByText(/Nothing was charged/)).toBeInTheDocument();
  });
});
