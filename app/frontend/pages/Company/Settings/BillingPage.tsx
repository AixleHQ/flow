import { Head, router, usePage } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  List,
  Loader,
  Modal,
  Select,
  Stack,
  Text,
  Textarea,
} from '@mantine/core';
import { useEffect, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { formatCalendarDay, formatDateMedium, formatDateTimeShort } from 'shared/lib/formatDate';
import {
  companyBillingCancellationPath,
  companyBillingCheckoutPath,
  companyBillingInvoicePaymentPath,
  companyMarketplaceLicenseProposalPath,
} from 'shared/routes';
import type { BillingStatus } from 'shared/ui';

import { SettingsTabs } from './SettingsTabs';

interface Estimate {
  amountCents: number;
  currency: string;
  unitAmountCents: number;
  minutesPerUnit: number;
}

interface Usage {
  workerMinutes: number;
  /** The end of the last hour the meter has closed; the hour under way is not in yet. */
  measuredUntil: string | null;
  /** Null while the price cannot be read from Stripe. */
  estimate: Estimate | null;
}

interface FinalInvoice {
  /** `cancelling` until the card has been stopped at Stripe; `settling` while the last usage is on its way to it. */
  state: 'cancelling' | 'settling' | 'settled' | 'failed';
  url: string | null;
}

interface Billing {
  status: BillingStatus;
  periodStartsAt: string | null;
  periodEndsAt: string | null;
  cancelsAt: string | null;
  usage: Usage | null;
  /** The free trial, while it runs or once it has ended. `lastDay` is `YYYY-MM-DD` (UTC). */
  trial: { days: number; daysLeft: number; lastDay: string } | null;
  canPay: boolean;
  hasSubscription: boolean;
  hasUnpaidInvoice: boolean;
  finalInvoice: FinalInvoice | null;
  cancellationReasons: string[];
}

/** Somebody's AWS Marketplace subscription asking to be applied to this workspace. */
interface MarketplaceProposal {
  /** The address the asker proved by opening a link sent to it. */
  askedBy: string;
  /** The AWS account that would be billed — and that can end the subscription. */
  awsAccountId: string;
  askedAt: string;
  /** Whether accepting also stops a card subscription paying for this workspace. */
  replacesCard: boolean;
  /** Worker-minutes the card has not been billed for yet, which accepting puts on its final invoice. */
  finalInvoiceMinutes: number | null;
  /** AWS has confirmed the agreement. Until it has, applying is refused: it would stop the card and leave nothing paying. */
  confirmed: boolean;
  canDecide: boolean;
}

/** Set once AWS Marketplace bills this workspace: what this page shows instead of controls. */
interface Marketplace {
  awsAccountId: string | null;
  subscribedAt: string | null;
  /** The subscription has ended; the workspace is stopped until somebody renews it in AWS. */
  ended: boolean;
  /** AWS is the payer now. False once a card has taken over — the panel is then about this month, not an offer to renew. */
  billsNow: boolean;
  /** Worker-minutes reported towards the AWS bill so far this month. */
  reportedMinutes: number;
  /** The listing's page in AWS Marketplace, where an ended subscription is taken out again. */
  listingUrl: string;
}

interface Props {
  company: { name: string };
  billing: Billing;
  checkoutResult: 'done' | 'cancelled' | null;
  marketplaceProposal: MarketplaceProposal | null;
  marketplaceBilling: Marketplace | null;
  [key: string]: unknown;
}

const STATUS_BADGE: Record<BillingStatus, { label: string; color: string }> = {
  trialing: { label: 'Free trial', color: 'blue' },
  active: { label: 'Active', color: 'green' },
  cancelling: { label: 'Cancelling', color: 'yellow' },
  allowance: { label: 'Stopped', color: 'red' },
  canceled: { label: 'Canceled', color: 'gray' },
  payment_failed: { label: 'Payment failed', color: 'red' },
};

// Stripe's own cancellation feedback values, worded for the person choosing.
const REASON_LABELS: Record<string, string> = {
  too_expensive: 'It costs too much',
  missing_features: 'It is missing something we need',
  unused: 'We are not using it enough',
  switched_service: 'We switched to another service',
  too_complex: 'It is too hard to use',
  low_quality: 'It does not work well enough',
  customer_service: 'Support did not help us',
  other: 'Other',
};

const COMMENT_MAX = 1000;

const SETTLING_POLL_MS = 5000;

const formatMoney = (cents: number, currency: string) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.toUpperCase() }).format(cents / 100);

const formatMinutes = (minutes: number) => new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(minutes);

function CheckoutResult({ result, billing }: { result: Props['checkoutResult']; billing: Billing }) {
  if (result === 'cancelled') {
    return (
      <Alert color="gray" title="Card entry cancelled">
        Nothing was charged and nothing has changed.
      </Alert>
    );
  }
  if (result !== 'done') return null;

  // Stripe confirms the card by webhook, which can land a few seconds after the
  // customer is sent back here.
  const confirmed = billing.status === 'active' && billing.hasSubscription;
  return (
    <Alert color="green" title={confirmed ? 'Card added' : 'Card received'}>
      {confirmed
        ? 'Your workspace is on a paid subscription. New sessions can start.'
        : 'Stripe is confirming the card. Reload this page in a moment to see the subscription.'}
    </Alert>
  );
}

function CancelModal({ opened, onClose, reasons }: { opened: boolean; onClose: () => void; reasons: string[] }) {
  const [reason, setReason] = useState<string | null>(null);
  const [comment, setComment] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const confirm = () => {
    setSubmitting(true);
    router.post(
      companyBillingCancellationPath(),
      { reason: reason ?? '', comment: reason === 'other' ? comment : '' },
      { onSuccess: onClose, onFinish: () => setSubmitting(false) },
    );
  };

  return (
    <Modal opened={opened} onClose={onClose} title="Cancel the subscription?" size="md">
      <Stack gap="md">
        <List size="sm" spacing={6}>
          <List.Item>It stops now: no new sessions start, and anything already running finishes.</List.Item>
          <List.Item>Usage up to now is billed on a final invoice.</List.Item>
          <List.Item>Projects, workflows and history are kept, and admins can still sign in.</List.Item>
          <List.Item>Add a card at any time to restore access.</List.Item>
        </List>

        <Select
          label="Why are you cancelling?"
          description="Optional. It helps us decide what to fix."
          placeholder="Choose a reason"
          data={reasons.map((value) => ({ value, label: REASON_LABELS[value] ?? value }))}
          value={reason}
          onChange={setReason}
          clearable
        />
        {reason === 'other' && (
          <Textarea
            label="Tell us more"
            value={comment}
            onChange={(event) => setComment(event.currentTarget.value)}
            maxLength={COMMENT_MAX}
            autosize
            minRows={2}
          />
        )}

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Keep subscription
          </Button>
          <Button color="red" loading={submitting} onClick={confirm}>
            Cancel subscription
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function FinalInvoiceStatus({ invoice }: { invoice: FinalInvoice }) {
  switch (invoice.state) {
    case 'cancelling':
    case 'settling':
      return (
        <Group gap="xs">
          <Loader size="xs" />
          <Text size="sm">
            Preparing the final invoice for usage up to the cancellation. This takes a minute or two.
          </Text>
        </Group>
      );
    case 'settled':
      return (
        invoice.url && (
          <Anchor href={invoice.url} target="_blank" rel="noopener noreferrer" size="sm">
            View the final invoice
          </Anchor>
        )
      );
    case 'failed':
      return <Text size="sm">Stripe issues the final invoice within the hour.</Text>;
  }
}

function SubscriptionCard({ billing, title = 'Subscription' }: { billing: Billing; title?: string }) {
  const [cancelOpen, setCancelOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const badge = STATUS_BADGE[billing.status];
  const endsOn = formatDateMedium(billing.cancelsAt ?? billing.periodEndsAt);
  // Only a cancellation we recorded dates an ending. `periodEndsAt` stands in
  // while the subscription is still running towards one, but it outlives the
  // subscription: a workspace handed over to AWS Marketplace keeps the period
  // end of the Stripe subscription it left, which is in the future.
  const endedOn = billing.cancelsAt && formatDateMedium(billing.cancelsAt);
  const ended = endedOn
    ? `On ${endedOn} the subscription ended, so no new sessions start.`
    : 'The subscription has ended, so no new sessions start.';

  const post = (path: string) => {
    setBusy(true);
    router.post(path, {}, { onFinish: () => setBusy(false) });
  };
  const addCard = billing.canPay && (
    <Button loading={busy} onClick={() => post(companyBillingCheckoutPath())}>
      Add a card
    </Button>
  );

  let body: React.ReactNode;
  let action: React.ReactNode = null;
  switch (billing.status) {
    case 'trialing':
      body = billing.trial && (
        <>
          You are on the free trial, on one worker: {billing.trial.daysLeft} of {billing.trial.days} days left, the last
          day is {formatCalendarDay(billing.trial.lastDay)}.{' '}
          {billing.canPay
            ? 'Add a card to keep going after it and choose how many workers to run.'
            : 'Talk to us to keep going after it.'}
        </>
      );
      action = addCard;
      break;
    case 'allowance':
      body = `The free trial has ended, so no new sessions start. Anything already running finishes. ${
        billing.canPay ? 'Add a card to carry on.' : 'Talk to us to carry on.'
      }`;
      action = addCard;
      break;
    case 'active':
      if (!billing.hasSubscription) {
        body = 'No card is on file, so nothing is billed yet. Add a card to pay for the worker-minutes you use.';
        action = addCard;
        break;
      }
      body = (
        <>
          Billed monthly by card for the worker-minutes you use. Current period:{' '}
          {formatDateMedium(billing.periodStartsAt)} – {formatDateMedium(billing.periodEndsAt)}
        </>
      );
      action = (
        <Button variant="default" color="red" onClick={() => setCancelOpen(true)}>
          Cancel subscription
        </Button>
      );
      break;
    case 'cancelling':
      body = (
        <>
          On {endsOn} the subscription ends and no new sessions start. Until then everything keeps working, and usage up
          to that date is billed on the final invoice.
        </>
      );
      action = (
        <Button
          variant="default"
          loading={busy}
          onClick={() => {
            setBusy(true);
            router.delete(companyBillingCancellationPath(), { onFinish: () => setBusy(false) });
          }}
        >
          Keep subscription
        </Button>
      );
      break;
    case 'canceled':
      if (billing.hasUnpaidInvoice) {
        body = <>{ended} Your data is kept. The final invoice is unpaid: pay it to add a card again.</>;
        action = (
          <Button color="red" loading={busy} onClick={() => post(companyBillingInvoicePaymentPath())}>
            Pay final invoice
          </Button>
        );
        break;
      }
      body = <>{ended} Your data is kept. Add a card to restore access.</>;
      action = addCard;
      break;
    case 'payment_failed':
      body = billing.hasUnpaidInvoice
        ? 'Your last payment did not go through, so no new sessions start. Pay the open invoice to restore access.'
        : 'Your last payment did not go through, so no new sessions start. The invoice will appear here shortly.';
      action = billing.hasUnpaidInvoice && (
        <Button color="red" loading={busy} onClick={() => post(companyBillingInvoicePaymentPath())}>
          Pay invoice
        </Button>
      );
      break;
  }

  return (
    <Card withBorder padding="lg">
      <Stack gap="sm">
        <Group justify="space-between">
          <Text fw={600}>{title}</Text>
          <Badge color={badge.color} variant="light">
            {badge.label}
          </Badge>
        </Group>
        <Text size="sm" c="dimmed">
          {body}
        </Text>
        {billing.finalInvoice && <FinalInvoiceStatus invoice={billing.finalInvoice} />}
        {action && <Group>{action}</Group>}
      </Stack>
      <CancelModal opened={cancelOpen} onClose={() => setCancelOpen(false)} reasons={billing.cancellationReasons} />
    </Card>
  );
}

function UsageCard({ billing, usage }: { billing: Billing; usage: Usage }) {
  const { estimate } = usage;

  return (
    <Card withBorder padding="lg">
      <Stack gap="sm">
        <Text fw={600}>This billing period</Text>
        <Text size="sm">
          Since {formatDateMedium(billing.periodStartsAt)}:{' '}
          <Text span fw={600}>
            {formatMinutes(usage.workerMinutes)}
          </Text>{' '}
          worker-minutes
          {estimate && (
            <>
              , about{' '}
              <Text span fw={600}>
                {formatMoney(estimate.amountCents, estimate.currency)}
              </Text>{' '}
              so far
            </>
          )}
        </Text>
        <Text size="xs" c="dimmed">
          {estimate &&
            `Billed at ${formatMoney(estimate.unitAmountCents, estimate.currency)} per ${estimate.minutesPerUnit} worker-minutes, in whole packs rounded down. `}
          {usage.measuredUntil
            ? `Measured up to ${formatDateTimeShort(usage.measuredUntil)}; each hour is added once it closes.`
            : 'Each hour is added once it closes.'}{' '}
          The invoice has the final amount.
        </Text>
      </Stack>
    </Card>
  );
}

// The final invoice is settled by a background job a minute or two after the
// cancellation; the page asks for the billing prop again until it is done.
function useRefreshWhileSettling(settling: boolean) {
  useEffect(() => {
    if (!settling) return;
    const timer = setInterval(() => router.reload({ only: ['billing'] }), SETTLING_POLL_MS);
    return () => clearInterval(timer);
  }, [settling]);
}

function MarketplaceProposalCard({ proposal, companyName }: { proposal: MarketplaceProposal; companyName: string }) {
  const [applyOpen, setApplyOpen] = useState(false);
  const [deciding, setDeciding] = useState(false);

  const apply = () => {
    setDeciding(true);
    router.post(
      companyMarketplaceLicenseProposalPath(),
      {},
      { onSuccess: () => setApplyOpen(false), onFinish: () => setDeciding(false) },
    );
  };

  return (
    <Card withBorder padding="lg">
      <Stack gap="sm">
        <Group justify="space-between" wrap="nowrap">
          <Text fw={600}>A request to bill this workspace through AWS Marketplace</Text>
          <Badge color="yellow">Waiting</Badge>
        </Group>
        <Text size="sm" c="var(--app-text-secondary)">
          <b>{proposal.askedBy}</b> bought an AWS Marketplace subscription to Aixle Flow and asks for it to be applied
          to {companyName}. They confirmed that address on {formatDateMedium(proposal.askedAt)}.
        </Text>
        <ProposalConsequences proposal={proposal} companyName={companyName} />
        {!proposal.confirmed && (
          <Alert color="gray" title="Waiting for AWS">
            AWS has not confirmed this subscription yet, so it cannot be applied. This usually takes a few minutes.
            Applying it before then would stop the card and leave the workspace with nothing paying for it.
          </Alert>
        )}
        {proposal.canDecide ? (
          <Group>
            <Button loading={deciding} disabled={!proposal.confirmed} onClick={() => setApplyOpen(true)}>
              Apply the subscription
            </Button>
            <Button
              variant="default"
              disabled={deciding}
              onClick={() => router.delete(companyMarketplaceLicenseProposalPath())}
            >
              Decline
            </Button>
          </Group>
        ) : (
          <Text size="sm" c="var(--app-text-tertiary)">
            An administrator of {companyName} decides this.
          </Text>
        )}
      </Stack>
      <Modal
        opened={applyOpen}
        onClose={() => setApplyOpen(false)}
        title="Apply the AWS Marketplace subscription?"
        size="md"
      >
        <Stack gap="md">
          <Text size="sm">This takes effect now and is not undone by declining later:</Text>
          <ProposalConsequences proposal={proposal} companyName={companyName} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setApplyOpen(false)} disabled={deciding}>
              Keep things as they are
            </Button>
            <Button loading={deciding} onClick={apply}>
              Apply it
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Card>
  );
}

// What accepting does, spelled out rather than summarised: billing goes to an
// AWS account that may belong to somebody else, who can stop the workspace by
// unsubscribing, and the card paying for it today is stopped at once.
function ProposalConsequences({ proposal, companyName }: { proposal: MarketplaceProposal; companyName: string }) {
  return (
    <List size="sm" spacing={4}>
      <List.Item>
        {companyName} would be billed through AWS account <b>{proposal.awsAccountId}</b>, which you may not control.
      </List.Item>
      <List.Item>Whoever holds that subscription can end it, and this workspace stops when they do.</List.Item>
      {proposal.replacesCard && (
        <List.Item>
          The card subscription paying for this workspace is stopped at the same moment, and a final invoice follows
          {proposal.finalInvoiceMinutes != null ? (
            <>
              {' '}
              for the <b>{formatMinutes(proposal.finalInvoiceMinutes)}</b> worker-minutes it has not been billed for yet
            </>
          ) : (
            <> for the capacity used up to then</>
          )}
          .
        </List.Item>
      )}
    </List>
  );
}

const AWS_SUBSCRIPTIONS_URL = 'https://aws.amazon.com/marketplace/library';

// A workspace AWS bills has nothing to change here. Taken away from the page
// entirely, its billing read as gone missing rather than kept somewhere else,
// so the card says where the bill comes from and what has been reported
// towards it -- the one figure not visible in AWS until the invoice exists.
function MarketplaceCard({ marketplace, companyName }: { marketplace: Marketplace; companyName: string }) {
  return (
    <Card withBorder padding="lg">
      <Stack gap="sm">
        <Group justify="space-between" wrap="nowrap">
          <Text fw={600}>Billed through AWS Marketplace</Text>
          <Badge color={marketplace.ended ? 'red' : 'green'}>{marketplace.ended ? 'Ended' : 'Active'}</Badge>
        </Group>
        <Text size="sm" c="var(--app-text-secondary)">
          {!marketplace.billsNow ? (
            <>
              A card pays for {companyName} now, so nothing more is reported to AWS. The minutes below ran through AWS
              Marketplace earlier this month and are on that account&apos;s AWS bill for it.
            </>
          ) : marketplace.ended ? (
            <>
              The AWS Marketplace subscription for {companyName} has ended, so the workspace is stopped. Renewing it in
              AWS starts it again.
            </>
          ) : (
            <>
              {companyName} is paid for through AWS Marketplace
              {marketplace.awsAccountId && (
                <>
                  {' '}
                  on AWS account <b>{marketplace.awsAccountId}</b>
                </>
              )}
              . Your usage appears on that account&apos;s AWS bill, and the subscription is cancelled there rather than
              here.
            </>
          )}
        </Text>
        <List size="sm" spacing={4}>
          <List.Item>
            <b>{formatMinutes(marketplace.reportedMinutes)}</b> worker-minutes reported to AWS this calendar month —
            what the AWS bill for the month is counted from, including any earlier subscription in it.
          </List.Item>
          {marketplace.subscribedAt && (
            <List.Item>Subscribed on {formatDateMedium(marketplace.subscribedAt)}.</List.Item>
          )}
        </List>
        {/* The library manages a running subscription; an ended one is taken
            out again on the listing's own page, which the library never leads
            to. */}
        {marketplace.billsNow && !marketplace.ended && (
          <Anchor href={AWS_SUBSCRIPTIONS_URL} target="_blank" rel="noopener noreferrer" size="sm" fw={500}>
            Manage the subscription in AWS Marketplace
          </Anchor>
        )}
        {marketplace.billsNow && marketplace.ended && (
          <Anchor href={marketplace.listingUrl} target="_blank" rel="noopener noreferrer" size="sm" fw={500}>
            Subscribe again in AWS Marketplace
          </Anchor>
        )}
      </Stack>
    </Card>
  );
}

const BillingPage = () => {
  const { company, billing, checkoutResult, marketplaceProposal, marketplaceBilling } = usePage<Props>().props;
  useRefreshWhileSettling(billing.finalInvoice?.state === 'cancelling' || billing.finalInvoice?.state === 'settling');

  return (
    <AuthLayout>
      <Head title={`Billing — ${company.name}`} />
      <SettingsTabs active="billing" companyName={company.name}>
        <Stack gap="lg" maw={720}>
          <CheckoutResult result={checkoutResult} billing={billing} />
          {marketplaceProposal && <MarketplaceProposalCard proposal={marketplaceProposal} companyName={company.name} />}
          {/* Whichever pays now comes first. Both are shown once the AWS
              subscription has ended: the panel says what happened and where to
              renew, and the card is the other way to carry on -- and once a
              card has taken over, the AWS panel is a statement about this
              month's bill, beneath the subscription that runs the workspace.
              While the AWS subscription is live there is no card to offer: it
              would be a second bill for the same capacity. */}
          {marketplaceBilling?.billsNow && (
            <MarketplaceCard marketplace={marketplaceBilling} companyName={company.name} />
          )}
          {(!marketplaceBilling || marketplaceBilling.ended) && (
            <>
              <SubscriptionCard billing={billing} title={marketplaceBilling ? 'Billed by card' : 'Subscription'} />
              {billing.usage && <UsageCard billing={billing} usage={billing.usage} />}
            </>
          )}
          {marketplaceBilling && !marketplaceBilling.billsNow && (
            <MarketplaceCard marketplace={marketplaceBilling} companyName={company.name} />
          )}
        </Stack>
      </SettingsTabs>
    </AuthLayout>
  );
};

export default BillingPage;
