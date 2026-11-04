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

const LISTING_URL = 'https://aws.amazon.com/marketplace/pp/prodview-x';
const AWS_BILLING_URL = 'https://console.aws.amazon.com/billing/home#/bills';

const billing = {
  status: 'active' as string,
  periodStartsAt: '2026-10-01T00:00:00Z' as string | null,
  periodEndsAt: '2026-11-01T12:00:00Z' as string | null,
  cancelsAt: null as string | null,
  trial: null as { days: number; daysLeft: number; lastDay: string } | null,
  price: { unitAmountCents: 500, currency: 'usd', minutesPerUnit: 60 } as Record<string, unknown> | null,
  provider: 'stripe' as string,
  canPay: true,
  hasSubscription: true,
  hasUnpaidInvoice: false,
  finalInvoice: null as { state: string; url: string | null } | null,
  cancellationReasons: REASONS,
};

const usage = {
  since: '2026-10-01T00:00:00Z',
  until: '2026-10-02T12:00:00Z',
  workerMinutes: 130,
  measuredUntil: '2026-10-02T11:00:00Z' as string | null,
  estimate: { amountCents: 1000, currency: 'usd', unitAmountCents: 500, minutesPerUnit: 60 },
};

type Subscription = Record<string, unknown>;

const card = (over: Subscription = {}): Subscription => ({
  kind: 'card',
  status: 'active',
  periodStartsAt: '2026-10-01T00:00:00Z',
  periodEndsAt: '2026-11-01T12:00:00Z',
  nextInvoiceAt: '2026-11-01T12:00:00Z',
  cancelsAt: null,
  cancelledAt: null,
  usage,
  invoicesUrl: null,
  awsAccountId: null,
  finalInvoice: null,
  ...over,
});

const aws = (over: Subscription = {}): Subscription => ({
  kind: 'aws_marketplace',
  status: 'active',
  periodStartsAt: '2026-10-01T00:00:00Z',
  periodEndsAt: '2026-11-01T00:00:00Z',
  nextInvoiceAt: '2026-11-01T00:00:00Z',
  cancelsAt: null,
  cancelledAt: null,
  usage: { ...usage, workerMinutes: 132.5, measuredUntil: null },
  invoicesUrl: AWS_BILLING_URL,
  awsAccountId: '444455556666',
  finalInvoice: null,
  ...over,
});

const stoppedCard = (over: Subscription = {}): Subscription =>
  card({
    status: 'cancelled',
    periodStartsAt: '2026-07-01T09:00:00Z',
    periodEndsAt: '2026-10-12T14:20:00Z',
    nextInvoiceAt: null,
    cancelledAt: '2026-10-12T14:20:00Z',
    usage: { ...usage, since: '2026-10-01T00:00:00Z', until: '2026-10-12T14:20:00Z', measuredUntil: null },
    invoicesUrl: 'https://invoice.stripe.test/in_1',
    finalInvoice: { state: 'settled', url: 'https://invoice.stripe.test/in_1' },
    ...over,
  });

const stoppedAws = (over: Subscription = {}): Subscription =>
  aws({
    status: 'cancelled',
    periodStartsAt: '2026-06-12T08:00:00Z',
    periodEndsAt: '2026-10-27T16:20:00Z',
    nextInvoiceAt: null,
    cancelledAt: '2026-10-27T16:20:00Z',
    usage: {
      ...usage,
      since: '2026-10-01T00:00:00Z',
      until: '2026-10-27T16:20:00Z',
      workerMinutes: 97,
      measuredUntil: null,
    },
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

const render = ({
  billing: overrides = {},
  active = card() as Subscription | null,
  previous = [] as Subscription[],
  listingUrl = null as string | null,
  checkoutResult = null as string | null,
  marketplaceProposal = null as Record<string, unknown> | null,
} = {}) =>
  renderAuthedPage(<BillingPage />, {
    props: {
      company: { name: 'Acme Robotics' },
      billing: { ...billing, ...overrides },
      subscriptions: { active, previous },
      listingUrl,
      checkoutResult,
      marketplaceProposal,
      permissions: buildSharedPermissions({ canManageBilling: true, canViewBilling: true }),
    },
  });

const trialing = { status: 'trialing', trial: { days: 30, daysLeft: 12, lastDay: '2026-11-11' } };

describe('Company billing page', () => {
  it('quotes the price, and shows what this period has come to so far', () => {
    render();

    expect(screen.getByText(/Billed at \$5\.00 per 60 worker-minutes/)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Active subscription' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Card payment' })).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText('Card via Stripe')).toBeInTheDocument();
    expect(screen.getByText('130')).toBeInTheDocument();
    expect(screen.getByText('$10.00')).toBeInTheDocument();
  });

  it('is the third tab of company settings for an admin', () => {
    render();

    expect(screen.getByRole('tab', { name: 'Billing', selected: true })).toBeInTheDocument();
  });

  it('lists nothing under previous subscriptions when there are none', () => {
    render();

    expect(screen.queryByRole('heading', { name: 'Previous subscriptions' })).not.toBeInTheDocument();
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
    render({
      billing: { status: 'cancelling', cancelsAt: '2026-11-01T12:00:00Z' },
      active: card({ status: 'cancelling', cancelsAt: '2026-11-01T12:00:00Z' }),
    });

    expect(screen.getByText('Cancelling')).toBeInTheDocument();
    expect(screen.getByText(/the subscription ends and no new sessions start/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Keep subscription' }));

    expect(destroy).toHaveBeenCalledWith('/company/billing_cancellation', expect.anything());
  });

  // A new card would open a second subscription and bill the same minutes twice.
  it('offers the open invoice after a failed payment, not a new card', async () => {
    const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
    render({
      billing: { status: 'payment_failed', hasUnpaidInvoice: true },
      active: card({ status: 'payment_failed', usage: null }),
    });

    expect(screen.getByText('Payment failed')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Pay invoice' }));

    expect(post.mock.calls[0][0]).toBe('/company/billing_invoice_payment');
  });

  it('offers a card, and nothing to cancel, to a workspace on the free trial', () => {
    render({ billing: trialing, active: null });

    expect(screen.getByRole('heading', { name: 'Free trial' })).toBeInTheDocument();
    expect(screen.getByText(/12 of 30 days left, the last day is Nov 11, 2026/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
  });

  it('points at us, not at a card, where there is nowhere to pay', () => {
    render({ billing: { ...trialing, canPay: false }, active: null });

    expect(screen.getByText(/Talk to us to keep going after it/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
  });

  // Running without ever having paid: an operator set it active by hand.
  it('offers a card, and nothing to cancel, to an active workspace with no subscription', () => {
    render({ billing: { hasSubscription: false, periodStartsAt: null, periodEndsAt: null }, active: null });

    expect(screen.getByText(/No card is on file/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancel subscription' })).not.toBeInTheDocument();
  });

  it('offers a card to bring back a workspace whose subscription ended', () => {
    render({ billing: { status: 'canceled', cancelsAt: '2026-10-01T12:00:00Z' }, active: null });

    expect(screen.getByText(/the subscription ended/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  // A workspace handed over to AWS Marketplace keeps the period end of the
  // Stripe subscription it left, and that date is in the future.
  it('names no date for an ended subscription it has no cancellation for', () => {
    render({ billing: { status: 'canceled', cancelsAt: null }, active: null });

    expect(screen.getByText(/^The subscription has ended, so no new sessions start\./)).toBeInTheDocument();
    expect(screen.queryByText(/Nov 1, 2026/)).not.toBeInTheDocument();
  });

  // The design spells it the British way, everywhere: badges, fields and text.
  it('spells cancelled with two Ls throughout', () => {
    render({
      billing: { status: 'canceled', cancelsAt: '2026-10-12T14:20:00Z' },
      active: null,
      previous: [stoppedCard()],
    });

    expect(screen.queryByText(/\bCanceled\b/)).not.toBeInTheDocument();
    expect(screen.getAllByText('Cancelled').length).toBeGreaterThan(0);
  });

  describe('a subscription that ended', () => {
    const canceled = { status: 'canceled', cancelsAt: '2026-10-12T14:20:00Z' };

    afterEach(() => {
      vi.useRealTimers();
    });

    // The card bills in whole packs; minutes that filled none are a real $0.00,
    // said so rather than left looking like a missing figure.
    it('says why the final cost is nothing when the minutes did not fill a pack', () => {
      render({
        billing: canceled,
        active: null,
        previous: [
          stoppedCard({ usage: { ...usage, workerMinutes: 52.8, estimate: { ...usage.estimate, amountCents: 0 } } }),
        ],
      });

      expect(screen.getByText('53')).toBeInTheDocument();
      expect(screen.getByText('$0.00')).toBeInTheDocument();
      expect(screen.getByText('Under one pack of 60 worker-minutes')).toBeInTheDocument();
    });

    it('is listed with its period, the day it was cancelled and what its final invoice covered', () => {
      render({ billing: canceled, active: null, previous: [stoppedCard()] });

      expect(screen.getByRole('heading', { name: 'Previous subscriptions' })).toBeInTheDocument();
      expect(screen.getByRole('heading', { name: 'Card payment' })).toBeInTheDocument();
      expect(screen.getByText('Active period')).toBeInTheDocument();
      expect(screen.getByText('Final usage')).toBeInTheDocument();
      expect(screen.getByText('130')).toBeInTheDocument();
      expect(screen.getByText('$10.00')).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Invoices' })).toHaveAttribute(
        'href',
        'https://invoice.stripe.test/in_1',
      );
    });

    it('is shown with its final invoice being prepared, and the page asks again until it is ready', () => {
      vi.useFakeTimers();
      const reload = vi.spyOn(router, 'reload').mockImplementation(() => undefined);
      render({
        billing: { ...canceled, finalInvoice: { state: 'settling', url: null } },
        active: null,
        previous: [stoppedCard({ invoicesUrl: null, finalInvoice: { state: 'settling', url: null } })],
      });

      expect(screen.getAllByText(/Preparing the final invoice/).length).toBeGreaterThan(0);
      expect(screen.queryByRole('link', { name: 'Invoices' })).not.toBeInTheDocument();
      vi.advanceTimersByTime(5000);

      expect(reload).toHaveBeenCalledWith({ only: ['billing', 'subscriptions'] });
    });

    it('stops asking once the invoice is issued', () => {
      vi.useFakeTimers();
      const reload = vi.spyOn(router, 'reload').mockImplementation(() => undefined);
      render({
        billing: { ...canceled, finalInvoice: { state: 'settled', url: 'https://invoice.stripe.test/in_1' } },
        active: null,
        previous: [stoppedCard()],
      });

      vi.advanceTimersByTime(15000);
      expect(reload).not.toHaveBeenCalled();
    });

    // A new subscription waits until the declined final invoice is paid.
    it('offers the unpaid invoice instead of a new card', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({
        billing: { ...canceled, hasUnpaidInvoice: true, finalInvoice: { state: 'settled', url: null } },
        active: null,
        previous: [stoppedCard({ invoicesUrl: null, finalInvoice: { state: 'settled', url: null } })],
      });

      expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
      await userEvent.click(screen.getByRole('button', { name: 'Pay final invoice' }));

      expect(post.mock.calls[0][0]).toBe('/company/billing_invoice_payment');
    });

    it('lists the ended subscriptions in the order given, with a count', () => {
      render({ billing: canceled, active: null, previous: [stoppedAws(), stoppedCard()] });

      const headings = screen.getAllByRole('heading', { level: 3 }).map((heading) => heading.textContent);
      expect(headings).toEqual(['No active subscription', 'AWS Marketplace', 'Card payment']);
      expect(screen.getByRole('heading', { name: 'Previous subscriptions' }).parentElement).toHaveTextContent('2');
    });
  });

  // Stripe confirms the card by webhook, which can land after the redirect back.
  it('says the card is being confirmed when Checkout returns before the webhook', () => {
    render({ billing: trialing, active: null, checkoutResult: 'done' });

    expect(screen.getByText('Card received')).toBeInTheDocument();
  });

  it('says nothing was charged when card entry was abandoned', () => {
    render({ checkoutResult: 'cancelled' });

    expect(screen.getByText(/Nothing was charged/)).toBeInTheDocument();
  });

  // The listing is the way to pay through AWS. Offered beside the card to a
  // workspace with nothing paying, and under the card to one already paying by
  // card, which may prefer its AWS bill.
  describe('paying through AWS Marketplace', () => {
    it('is offered beside the card where nothing pays yet', () => {
      render({ billing: trialing, active: null, listingUrl: LISTING_URL });

      expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Pay via AWS Marketplace' })).toHaveAttribute('href', LISTING_URL);
    });

    it('is offered to a workspace paying by card, as a way to switch', () => {
      render({ listingUrl: LISTING_URL });

      expect(screen.getByRole('link', { name: 'Pay via AWS Marketplace' })).toHaveAttribute('href', LISTING_URL);
      expect(screen.getByText(/The card is stopped once the subscription is applied/)).toBeInTheDocument();
    });

    it('is not offered where no listing is configured', () => {
      render({ billing: trialing, active: null });

      expect(screen.queryByRole('link', { name: 'Pay via AWS Marketplace' })).not.toBeInTheDocument();
    });

    it('is not offered to a workspace AWS already bills', () => {
      render({ active: aws(), listingUrl: LISTING_URL });

      expect(screen.queryByRole('link', { name: 'Pay via AWS Marketplace' })).not.toBeInTheDocument();
    });
  });

  // Somebody else's purchase asking to become this workspace's bill. Accepting
  // hands billing to an AWS account that may not be ours, and whoever holds
  // that subscription can stop the workspace by unsubscribing -- so the screen
  // spells the consequences out rather than summarising them.
  describe('a request to bill through AWS Marketplace', () => {
    it('names who asked and which AWS account would be billed', () => {
      render({ marketplaceProposal: proposal() });

      expect(screen.getByText(/bought an AWS Marketplace subscription/)).toHaveTextContent(
        'dana@acme-robotics.example',
      );
      expect(screen.getByText(/would be billed through AWS account/)).toHaveTextContent('444455556666');
    });

    it('says the subscription holder can stop the workspace', () => {
      render({ marketplaceProposal: proposal() });

      expect(screen.getByText(/can end it/)).toHaveTextContent('this workspace stops when they do');
    });

    // The admin should not have to work out that two things cannot both bill.
    it('says the card is stopped too, when there is one', () => {
      render({ marketplaceProposal: proposal({ replacesCard: true }) });

      expect(screen.getByText(/card subscription paying for this workspace/)).toBeInTheDocument();
    });

    // Deciding this blind was the difference from an ordinary cancellation,
    // which shows what the final invoice will be on a screen of its own.
    it('says what the final card invoice will be for', () => {
      render({ marketplaceProposal: proposal({ replacesCard: true, finalInvoiceMinutes: 184.5 }) });

      expect(screen.getByText(/card subscription paying for this workspace/)).toHaveTextContent('184.5');
    });

    it('says nothing about a card when there is none', () => {
      render({ marketplaceProposal: proposal() });

      expect(screen.queryByText(/card subscription paying for this workspace/)).not.toBeInTheDocument();
    });

    // One click moves who bills the workspace and stops the card, so the
    // button asks first; nothing is sent until the admin says so again.
    it('asks before applying it, and sends nothing until the admin confirms', async () => {
      const post = vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({ marketplaceProposal: proposal({ replacesCard: true, finalInvoiceMinutes: 184.5 }) });

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
      render({ marketplaceProposal: proposal() });

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
      render({ marketplaceProposal: proposal() });

      await userEvent.click(screen.getByRole('button', { name: 'Decline' }));

      expect(remove).toHaveBeenCalledWith('/company/marketplace_license_proposal');
    });

    // Applying cancels the card in the same breath, and only a confirmation
    // starts the workspace again — so before AWS has confirmed, the button
    // would stop the card and leave nothing paying for the workspace.
    it('will not let it be applied before AWS has confirmed it', () => {
      render({ marketplaceProposal: proposal({ confirmed: false }) });

      expect(screen.getByRole('button', { name: 'Apply the subscription' })).toBeDisabled();
      expect(screen.getByText(/AWS has not confirmed this subscription yet/)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Decline' })).toBeEnabled();
    });

    it('does not offer a decline while an apply is in flight', async () => {
      vi.spyOn(router, 'post').mockImplementation(() => undefined);
      render({ marketplaceProposal: proposal() });

      await userEvent.click(screen.getByRole('button', { name: 'Apply the subscription' }));
      const dialog = await screen.findByRole('dialog');
      await userEvent.click(within(dialog).getByRole('button', { name: 'Apply it' }));

      expect(screen.getByRole('button', { name: 'Decline' })).toBeDisabled();
    });

    // Moving who bills the workspace is an administrator's decision; everyone
    // else sees the request and no buttons.
    it('offers no decision to somebody who cannot make it', () => {
      render({ marketplaceProposal: proposal({ canDecide: false }) });

      expect(screen.queryByRole('button', { name: 'Apply the subscription' })).not.toBeInTheDocument();
      expect(screen.getByText(/An administrator of Acme Robotics decides this/)).toBeInTheDocument();
    });

    it('is absent when nobody has asked', () => {
      render();

      expect(screen.queryByText(/request to bill this workspace/i)).not.toBeInTheDocument();
    });
  });

  describe('a workspace billed through AWS Marketplace', () => {
    it('says where the bill comes from, and which account pays it', () => {
      render({ active: aws() });

      expect(screen.getByRole('heading', { name: 'AWS Marketplace' })).toBeInTheDocument();
      expect(screen.getByText('AWS account 444455556666')).toBeInTheDocument();
      expect(screen.getByText('Active')).toBeInTheDocument();
    });

    // The one figure not visible in AWS until the invoice exists.
    it('shows what has been reported towards that bill, and where the bill is', () => {
      render({ active: aws() });

      expect(screen.getByText('133')).toBeInTheDocument();
      expect(screen.getByText(/reported to AWS this calendar month/)).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Invoices' })).toHaveAttribute('href', AWS_BILLING_URL);
    });

    // A private offer is priced on its own terms, and the card's price has
    // nothing to do with a workspace AWS bills.
    it('quotes the rate the agreement was accepted at, not the card price', () => {
      render({
        active: aws({
          usage: { ...usage, estimate: { amountCents: 1350, currency: 'usd', unitAmountCents: 6, minutesPerUnit: 1 } },
        }),
      });

      expect(screen.getByText('Billed at $0.06 per worker-minute through AWS Marketplace.')).toBeInTheDocument();
      expect(screen.queryByText(/per 60 worker-minutes/)).not.toBeInTheDocument();
    });

    it('quotes no card price to a workspace AWS billed while nothing bills it', () => {
      render({
        billing: { status: 'canceled', hasSubscription: false, cancelsAt: null, provider: 'aws_marketplace' },
        active: null,
        previous: [stoppedAws()],
      });

      expect(screen.queryByText(/^Billed at/)).not.toBeInTheDocument();
    });

    it('still quotes the card price to a workspace a card billed and stopped', () => {
      render({
        billing: { status: 'canceled', hasSubscription: false, cancelsAt: null, provider: 'stripe' },
        active: null,
        previous: [stoppedCard()],
      });

      expect(screen.getByText(/^Billed at \$5\.00 per 60 worker-minutes/)).toBeInTheDocument();
    });

    it('quotes no price for an AWS subscription whose rate was never read', () => {
      render({ active: aws({ usage: { ...usage, estimate: null } }) });

      expect(screen.queryByText(/^Billed at/)).not.toBeInTheDocument();
    });

    it('offers no card and no cancellation, because neither is ours to do', () => {
      render({ active: aws() });

      expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /Cancel/ })).not.toBeInTheDocument();
      expect(screen.getByRole('link', { name: /Manage subscription/ })).toBeInTheDocument();
    });

    // A workspace that goes back to a card still gets an AWS bill for the
    // minutes it ran there, so the ended subscription stays listed with them,
    // beneath the card that runs the workspace now.
    it('lists the ended AWS subscription beneath the card that took over', () => {
      render({ previous: [stoppedAws()] });

      const headings = screen.getAllByRole('heading', { level: 3 }).map((heading) => heading.textContent);
      expect(headings).toEqual(['Card payment', 'AWS Marketplace']);
      expect(screen.getByText('97')).toBeInTheDocument();
      expect(screen.getByText(/in the month the subscription ended/)).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Invoices' })).toHaveAttribute('href', AWS_BILLING_URL);
    });

    // Renewing in AWS is one way out of a stopped workspace; a card is the
    // other, and withholding it left a cancelled customer with neither.
    it('offers the card and the listing, once the subscription has ended', () => {
      render({
        billing: { status: 'canceled', hasSubscription: false, cancelsAt: null },
        active: null,
        previous: [stoppedAws()],
        listingUrl: LISTING_URL,
      });

      expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Pay via AWS Marketplace' })).toHaveAttribute('href', LISTING_URL);
    });
  });
});
