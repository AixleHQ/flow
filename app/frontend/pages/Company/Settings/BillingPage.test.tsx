import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

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
  hasSubscription: true,
  hasUnpaidInvoice: false,
  finalInvoice: null as { state: 'settling' | 'settled' | 'failed'; url: string | null } | null,
  cancellationReasons: REASONS,
};

const render = (
  overrides: Partial<typeof billing> | Record<string, unknown> = {},
  checkoutResult: string | null = null,
  marketplaceProposal: Record<string, unknown> | null = null,
  marketplaceBilling: Record<string, unknown> | null = null,
) =>
  renderAuthedPage(<BillingPage />, {
    props: {
      company: { name: 'Acme Robotics' },
      billing: { ...billing, ...overrides },
      checkoutResult,
      marketplaceProposal,
      marketplaceBilling,
      permissions: buildSharedPermissions({ canManageBilling: true, canViewBilling: true }),
    },
  });

const marketplace = (over = {}) => ({
  awsAccountId: '444455556666',
  subscribedAt: '2026-10-25T17:44:31Z',
  ended: false,
  billsNow: true,
  reportedMinutes: 132.5,
  ...over,
});

const proposal = (over = {}) => ({
  askedBy: 'dana@acme-robotics.example',
  awsAccountId: '444455556666',
  askedAt: '2026-10-25T09:00:00Z',
  replacesCard: false,
  finalInvoiceMinutes: null,
  confirmed: true,
  canDecide: true,
  ...over,
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

  // Running without ever having paid: an operator set it active by hand.
  it('offers a card, and nothing to cancel, to an active workspace with no subscription', () => {
    render({ hasSubscription: false, periodStartsAt: null, periodEndsAt: null, usage: null });

    expect(screen.getByText(/No card is on file/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
  });

  it('offers a card to bring back a workspace whose subscription ended', () => {
    render({ status: 'canceled', cancelsAt: '2026-10-01T12:00:00Z', usage: null });

    expect(screen.getByText(/the subscription ended/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  // A workspace handed over to AWS Marketplace keeps the period end of the
  // Stripe subscription it left, and that date is in the future.
  it('names no date for an ended subscription it has no cancellation for', () => {
    render({ status: 'canceled', cancelsAt: null, usage: null });

    expect(screen.getByText(/^The subscription has ended, so no new sessions start\./)).toBeInTheDocument();
    expect(screen.queryByText(/Nov 1, 2026/)).not.toBeInTheDocument();
  });

  describe('the final invoice after cancelling', () => {
    const canceled = { status: 'canceled' as const, cancelsAt: '2026-10-12T14:20:00Z', usage: null };

    afterEach(() => {
      vi.useRealTimers();
    });

    it('is shown as being prepared, and the page asks again until it is ready', () => {
      vi.useFakeTimers();
      const reload = vi.spyOn(router, 'reload').mockImplementation(() => undefined);
      render({ ...canceled, finalInvoice: { state: 'settling', url: null } });

      expect(screen.getByText(/Preparing the final invoice/)).toBeInTheDocument();
      vi.advanceTimersByTime(5000);

      expect(reload).toHaveBeenCalledWith({ only: ['billing'] });
    });

    it('links to the invoice once it is issued, and stops asking', () => {
      vi.useFakeTimers();
      const reload = vi.spyOn(router, 'reload').mockImplementation(() => undefined);
      render({ ...canceled, finalInvoice: { state: 'settled', url: 'https://invoice.stripe.test/in_1' } });

      expect(screen.getByRole('link', { name: 'View the final invoice' })).toHaveAttribute(
        'href',
        'https://invoice.stripe.test/in_1',
      );
      vi.advanceTimersByTime(15000);
      expect(reload).not.toHaveBeenCalled();
    });

    // A new subscription waits until the declined final invoice is paid.
    it('offers the unpaid invoice instead of a new card', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({ ...canceled, hasUnpaidInvoice: true, finalInvoice: { state: 'settled', url: null } });

      expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
      await userEvent.click(screen.getByRole('button', { name: 'Pay final invoice' }));

      expect(post.mock.calls[0][0]).toBe('/company/billing_invoice_payment');
    });
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

  // Somebody else's purchase asking to become this workspace's bill. Accepting
  // hands billing to an AWS account that may not be ours, and whoever holds
  // that subscription can stop the workspace by unsubscribing -- so the screen
  // spells the consequences out rather than summarising them.
  describe('a request to bill through AWS Marketplace', () => {
    it('names who asked and which AWS account would be billed', () => {
      render({}, null, proposal());

      expect(screen.getByText(/bought an AWS Marketplace subscription/)).toHaveTextContent(
        'dana@acme-robotics.example',
      );
      expect(screen.getByText(/would be billed through AWS account/)).toHaveTextContent('444455556666');
    });

    it('says the subscription holder can stop the workspace', () => {
      render({}, null, proposal());

      expect(screen.getByText(/can end it/)).toHaveTextContent('this workspace stops when they do');
    });

    // The admin should not have to work out that two things cannot both bill.
    it('says the card is stopped too, when there is one', () => {
      render({}, null, proposal({ replacesCard: true }));

      expect(screen.getByText(/card subscription paying for this workspace/)).toBeInTheDocument();
    });

    // Deciding this blind was the difference from an ordinary cancellation,
    // which shows what the final invoice will be on a screen of its own.
    it('says what the final card invoice will be for', () => {
      render({}, null, proposal({ replacesCard: true, finalInvoiceMinutes: 184.5 }));

      expect(screen.getByText(/card subscription paying for this workspace/)).toHaveTextContent('184.5');
    });

    it('says nothing about a card when there is none', () => {
      render({}, null, proposal());

      expect(screen.queryByText(/card subscription paying for this workspace/)).not.toBeInTheDocument();
    });

    // One click moves who bills the workspace and stops the card, so the
    // button asks first; nothing is sent until the admin says so again.
    it('asks before applying it, and sends nothing until the admin confirms', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({}, null, proposal({ replacesCard: true, finalInvoiceMinutes: 184.5 }));

      await userEvent.click(screen.getByRole('button', { name: 'Apply the subscription' }));
      const dialog = await screen.findByRole('dialog');

      expect(post).not.toHaveBeenCalled();
      expect(dialog).toHaveTextContent('444455556666');
      expect(dialog).toHaveTextContent('184.5');

      await userEvent.click(within(dialog).getByRole('button', { name: 'Apply it' }));

      expect(post).toHaveBeenCalledWith('/company/marketplace_license_proposal', {}, expect.anything());
    });

    it('can be thought better of', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({}, null, proposal());

      await userEvent.click(screen.getByRole('button', { name: 'Apply the subscription' }));
      const dialog = await screen.findByRole('dialog');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Keep things as they are' }));

      expect(post).not.toHaveBeenCalled();
      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    });

    // Separate renders, not two clicks: applying holds the pair while the
    // request is in flight, which is the point -- an admin must not be able to
    // decline something they are already applying.
    it('declines it through the same resource', async () => {
      const remove = vi.spyOn(router, 'delete').mockImplementation(() => undefined);
      render({}, null, proposal());

      await userEvent.click(screen.getByRole('button', { name: 'Decline' }));

      expect(remove).toHaveBeenCalledWith('/company/marketplace_license_proposal');
    });

    // Applying cancels the card in the same breath, and only a confirmation
    // starts the workspace again — so before AWS has confirmed, the button
    // would stop the card and leave nothing paying for the workspace.
    it('will not let it be applied before AWS has confirmed it', () => {
      render({}, null, proposal({ confirmed: false }));

      expect(screen.getByRole('button', { name: 'Apply the subscription' })).toBeDisabled();
      expect(screen.getByText(/AWS has not confirmed this subscription yet/)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Decline' })).toBeEnabled();
    });

    it('does not offer a decline while an apply is in flight', async () => {
      vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({}, null, proposal());

      await userEvent.click(screen.getByRole('button', { name: 'Apply the subscription' }));
      const dialog = await screen.findByRole('dialog');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Apply it' }));

      expect(screen.getByRole('button', { name: 'Decline' })).toBeDisabled();
    });

    // Moving who bills the workspace is an administrator's decision; everyone
    // else sees the request and no buttons.
    it('offers no decision to somebody who cannot make it', () => {
      render({}, null, proposal({ canDecide: false }));

      expect(screen.queryByRole('button', { name: 'Apply the subscription' })).not.toBeInTheDocument();
      expect(screen.getByText(/An administrator of Acme Robotics decides this/)).toBeInTheDocument();
    });

    it('is absent when nobody has asked', () => {
      render();

      expect(screen.queryByText(/request to bill this workspace/i)).not.toBeInTheDocument();
    });
  });

  // The page used to be taken away from a workspace AWS bills, which read as
  // billing gone missing rather than billing kept somewhere else.
  // A workspace that goes back to a card still gets an AWS bill for the minutes
  // it ran there this month. Keyed on the payer alone the panel vanished the
  // moment the card arrived, leaving "0 worker-minutes this period" beside a
  // charge the product never mentioned.
  it('keeps the AWS panel for the month AWS billed, without offering to renew', () => {
    render({}, null, null, marketplace({ ended: true, billsNow: false, reportedMinutes: 97 }));

    expect(screen.getByText(/A card pays for Acme Robotics now/)).toBeInTheDocument();
    expect(screen.getByText('97')).toBeInTheDocument();
    expect(screen.queryByText(/Renewing it in AWS/)).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /Manage the subscription/ })).not.toBeInTheDocument();
  });

  describe('a workspace billed through AWS Marketplace', () => {
    it('says where the bill comes from, and which account pays it', () => {
      render({}, null, null, marketplace());

      expect(screen.getByText('Billed through AWS Marketplace')).toBeInTheDocument();
      expect(screen.getByText(/is paid for through AWS Marketplace/)).toHaveTextContent('444455556666');
    });

    // The one figure not visible in AWS until the invoice exists.
    it('shows what has been reported towards that bill', () => {
      render({}, null, null, marketplace());

      expect(screen.getByText(/worker-minutes reported to AWS/)).toHaveTextContent('132.5');
    });

    it('offers no card and no cancellation, because neither is ours to do', () => {
      render({}, null, null, marketplace());

      expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Cancel/ })).not.toBeInTheDocument();
      expect(screen.getByRole('link', { name: /Manage the subscription in AWS Marketplace/ })).toBeInTheDocument();
    });

    it('says the workspace is stopped once the subscription has ended', () => {
      render({}, null, null, marketplace({ ended: true }));

      expect(screen.getByText('Ended')).toBeInTheDocument();
      expect(screen.getByText(/Renewing it in AWS starts it again/)).toBeInTheDocument();
    });

    // Renewing in AWS is one way out of a stopped workspace; a card is the
    // other, and withholding it left a cancelled customer with neither.
    it('offers the card as well, once the subscription has ended', () => {
      // As the workspace then is: stopped, with no card behind it.
      render({ status: 'canceled', hasSubscription: false, usage: null }, null, null, marketplace({ ended: true }));

      expect(screen.getByRole('button', { name: /card/i })).toBeInTheDocument();
    });

    it('offers no card while the subscription is live', () => {
      render({}, null, null, marketplace());

      expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
    });
  });
});
