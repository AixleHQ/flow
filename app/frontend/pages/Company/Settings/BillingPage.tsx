import { Head, router, usePage } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Box,
  Button,
  Card,
  Divider,
  Group,
  List,
  Loader,
  Modal,
  Select,
  SimpleGrid,
  Stack,
  Text,
  Textarea,
} from '@mantine/core';
import { IconBrandAws, IconCreditCard, IconFileInvoice } from '@tabler/icons-react';
import { useEffect, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { formatCalendarDay, formatDateMedium, formatDateTimeShort, parseDate } from 'shared/lib/formatDate';
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

interface Price {
  unitAmountCents: number;
  currency: string;
  minutesPerUnit: number;
}

interface FinalInvoice {
  /** `cancelling` until the card has been stopped at Stripe; `settling` while the last usage is on its way to it. */
  state: 'cancelling' | 'settling' | 'settled' | 'failed';
  url: string | null;
}

interface Billing {
  status: BillingStatus | 'awaiting_subscription';
  periodStartsAt: string | null;
  periodEndsAt: string | null;
  cancelsAt: string | null;
  /** The free trial, while it runs or once it has ended. `lastDay` is `YYYY-MM-DD` (UTC). */
  trial: { days: number; daysLeft: number; lastDay: string } | null;
  /** The rate the card is billed at. Null while the price cannot be read from Stripe. */
  price: Price | null;
  canPay: boolean;
  hasSubscription: boolean;
  hasUnpaidInvoice: boolean;
  finalInvoice: FinalInvoice | null;
  cancellationReasons: string[];
}

interface Usage {
  since: string;
  until: string;
  workerMinutes: number;
  /** The end of the last hour the meter has closed; the hour under way is not in yet. Null for usage AWS was sent. */
  measuredUntil: string | null;
  estimate: Estimate | null;
}

/** One subscription the workspace has had: the card or the AWS Marketplace licence, running or stopped. */
interface Subscription {
  kind: 'card' | 'aws_marketplace';
  status: 'active' | 'cancelling' | 'payment_failed' | 'cancelled';
  /** The period under way for a running subscription; the whole active period for a stopped one. */
  periodStartsAt: string | null;
  periodEndsAt: string | null;
  nextInvoiceAt: string | null;
  /** A cancellation scheduled for the end of the period, which only legacy card subscriptions have. */
  cancelsAt: string | null;
  cancelledAt: string | null;
  usage: Usage | null;
  invoicesUrl: string | null;
  awsAccountId: string | null;
  finalInvoice: FinalInvoice | null;
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

interface Props {
  company: { name: string };
  billing: Billing;
  subscriptions: { active: Subscription | null; previous: Subscription[] };
  /** The listing's page in AWS Marketplace, where a subscription is taken out. Null where none is configured. */
  listingUrl: string | null;
  checkoutResult: 'done' | 'cancelled' | null;
  marketplaceProposal: MarketplaceProposal | null;
  [key: string]: unknown;
}

const STATUS_BADGE: Record<
  Subscription['status'] | 'trialing' | 'allowance' | 'none',
  { label: string; color: string }
> = {
  trialing: { label: 'Free trial', color: 'blue' },
  active: { label: 'Active', color: 'green' },
  cancelling: { label: 'Cancelling', color: 'yellow' },
  allowance: { label: 'Stopped', color: 'red' },
  cancelled: { label: 'Cancelled', color: 'gray' },
  payment_failed: { label: 'Payment failed', color: 'red' },
  none: { label: 'None', color: 'gray' },
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

const AWS_SUBSCRIPTIONS_URL = 'https://aws.amazon.com/marketplace/library';

const formatMoney = (cents: number, currency: string) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.toUpperCase() }).format(cents / 100);

const formatMinutes = (minutes: number) => new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(minutes);

/** "Oct 28 – Nov 28, 2026"; the end alone when the start is not known. */
const formatDateRange = (from: string | null, to: string | null) => {
  const start = parseDate(from);
  const end = parseDate(to);
  if (!end) return start ? `From ${formatDateMedium(from)}` : '—';
  if (!start) return `Until ${formatDateMedium(to)}`;
  return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'short', day: 'numeric' }).formatRange(
    start,
    end,
  );
};

// A per-minute rate is fractions of a cent, so it is not rounded to two places.
const formatRate = (cents: number, currency: string) =>
  new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency.toUpperCase(),
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format(cents / 100);

const priceSentence = (price: Price) =>
  price.minutesPerUnit > 1
    ? `Billed at ${formatMoney(price.unitAmountCents, price.currency)} per ${price.minutesPerUnit} worker-minutes, in whole packs rounded down.`
    : `Billed at ${formatRate(price.unitAmountCents, price.currency)} per worker-minute through AWS Marketplace.`;

// What the page quotes: the agreement's rate while AWS bills, the card's otherwise.
const quotedPrice = (active: Subscription | null, billing: Billing): Price | null => {
  const estimate = active?.kind === 'aws_marketplace' ? active.usage?.estimate : null;
  if (estimate) {
    return { unitAmountCents: estimate.unitAmountCents, currency: estimate.currency, minutesPerUnit: 1 };
  }
  return active?.kind === 'aws_marketplace' ? null : billing.price;
};

function SectionHeader({ title, count }: { title: string; count?: number }) {
  return (
    <Group
      component="header"
      justify="space-between"
      align="baseline"
      pb={6}
      style={{ borderBottom: '1px solid var(--app-border-default)' }}
    >
      <Text component="h2" fz={13} fw={700} tt="uppercase" m={0} style={{ letterSpacing: '0.06em' }}>
        {title}
      </Text>
      {count !== undefined && (
        <Text fz="sm" c="dimmed">
          {count}
        </Text>
      )}
    </Group>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return (
    <Text fz={11} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: '0.06em' }}>
      {children}
    </Text>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string | null; children: React.ReactNode }) {
  return (
    <Stack gap={4}>
      <Label>{label}</Label>
      <Text fz="md">{children}</Text>
      {hint && (
        <Text fz="sm" c="dimmed">
          {hint}
        </Text>
      )}
    </Stack>
  );
}

function Figure({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <Stack gap={4}>
      <Label>{label}</Label>
      <Text fz="lg" ff="monospace">
        {children}
      </Text>
    </Stack>
  );
}

function StatusBadge({ status }: { status: keyof typeof STATUS_BADGE }) {
  const badge = STATUS_BADGE[status];
  return (
    <Badge variant="dot" color={badge.color} size="md">
      {badge.label}
    </Badge>
  );
}

function KindIcon({ kind }: { kind: Subscription['kind'] }) {
  const Icon = kind === 'card' ? IconCreditCard : IconBrandAws;
  return <Icon size={22} stroke={1.6} aria-hidden style={{ color: 'var(--mantine-color-dimmed)' }} />;
}

const KIND_TITLE: Record<Subscription['kind'], string> = { card: 'Card payment', aws_marketplace: 'AWS Marketplace' };
const KIND_METHOD: Record<Subscription['kind'], string> = {
  card: 'Card via Stripe',
  aws_marketplace: 'AWS Marketplace',
};

/**
 * The frame every subscription is drawn in: who is paid and how it stands at
 * the top, the dates beneath, and the usage block under a rule.
 */
function SubscriptionPanel({
  kind,
  status,
  action,
  fields,
  usage,
  footer,
}: {
  kind: Subscription['kind'];
  status: keyof typeof STATUS_BADGE;
  action?: React.ReactNode;
  fields: React.ReactNode;
  usage?: React.ReactNode;
  footer?: React.ReactNode;
}) {
  return (
    <Card withBorder padding={0}>
      <Box p="lg">
        <Group justify="space-between" align="flex-start" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <KindIcon kind={kind} />
            <Text component="h3" fz="xl" fw={600} m={0}>
              {KIND_TITLE[kind]}
            </Text>
            <StatusBadge status={status} />
          </Group>
          {action && <Group gap="xs">{action}</Group>}
        </Group>
        <SimpleGrid cols={{ base: 1, xs: 3 }} mt="lg" spacing="lg">
          {fields}
        </SimpleGrid>
      </Box>
      {usage && (
        <>
          <Divider />
          <Box p="lg">{usage}</Box>
        </>
      )}
      {footer && (
        <>
          <Divider />
          <Box px="lg" py="md">
            {footer}
          </Box>
        </>
      )}
    </Card>
  );
}

function UsageBlock({
  title,
  window,
  usage,
  costLabel,
  note,
}: {
  title: string;
  window: string;
  usage: Usage;
  costLabel: string;
  note: React.ReactNode;
}) {
  return (
    <Stack gap="md">
      <Group gap="sm" align="baseline">
        <Text fz={13} fw={700} tt="uppercase" style={{ letterSpacing: '0.06em' }}>
          {title}
        </Text>
        <Text fz="sm" c="dimmed">
          {window}
        </Text>
      </Group>
      <SimpleGrid cols={{ base: 1, xs: 3 }} spacing="lg">
        <Figure label="Worker-minutes">{formatMinutes(usage.workerMinutes)}</Figure>
        {usage.estimate && (
          <Figure label={costLabel}>{formatMoney(usage.estimate.amountCents, usage.estimate.currency)}</Figure>
        )}
      </SimpleGrid>
      <Note>{note}</Note>
    </Stack>
  );
}

// A string is set as dimmed text; a component (the final invoice status) draws its own.
function Note({ children }: { children: React.ReactNode }) {
  if (!children) return null;
  return typeof children === 'string' ? (
    <Text fz="sm" c="dimmed">
      {children}
    </Text>
  ) : (
    <>{children}</>
  );
}

function InvoicesButton({ href }: { href: string }) {
  return (
    <Button
      component="a"
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      variant="default"
      leftSection={<IconFileInvoice size={16} />}
    >
      Invoices
    </Button>
  );
}

function PayViaMarketplaceButton({ href }: { href: string }) {
  return (
    <Button
      component="a"
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      variant="default"
      leftSection={<IconBrandAws size={16} />}
    >
      Pay via AWS Marketplace
    </Button>
  );
}

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
      return invoice.url ? (
        <Text size="sm" c="dimmed">
          The final invoice has been issued.
        </Text>
      ) : (
        <Text size="sm" c="dimmed">
          The final invoice has been issued; Stripe sends it to the billing email.
        </Text>
      );
    case 'failed':
      return <Text size="sm">Stripe issues the final invoice within the hour.</Text>;
  }
}

/** The card paying now, in whichever state it is in. */
function RunningCard({
  subscription,
  billing,
  listingUrl,
}: {
  subscription: Subscription;
  billing: Billing;
  listingUrl: string | null;
}) {
  const [cancelOpen, setCancelOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const post = (path: string) => {
    setBusy(true);
    router.post(path, {}, { onFinish: () => setBusy(false) });
  };

  let action: React.ReactNode = null;
  let note: React.ReactNode = null;
  switch (subscription.status) {
    case 'active':
      action = (
        <Button variant="outline" color="red" onClick={() => setCancelOpen(true)}>
          Cancel subscription
        </Button>
      );
      break;
    case 'cancelling':
      note = (
        <>
          On {formatDateMedium(subscription.cancelsAt ?? subscription.periodEndsAt)} the subscription ends and no new
          sessions start. Until then everything keeps working, and usage up to that date is billed on the final invoice.
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
    case 'payment_failed':
      note = billing.hasUnpaidInvoice
        ? 'Your last payment did not go through, so no new sessions start. Pay the open invoice to restore access.'
        : 'Your last payment did not go through, so no new sessions start. The invoice will appear here shortly.';
      action = billing.hasUnpaidInvoice && (
        <Button color="red" loading={busy} onClick={() => post(companyBillingInvoicePaymentPath())}>
          Pay invoice
        </Button>
      );
      break;
    case 'cancelled':
      break;
  }

  return (
    <>
      <SubscriptionPanel
        kind="card"
        status={subscription.status}
        action={action}
        fields={
          <>
            <Field label="Billing method">{KIND_METHOD.card}</Field>
            <Field label="Current period">
              {formatDateRange(subscription.periodStartsAt, subscription.periodEndsAt)}
            </Field>
            <Field label="Next invoice">{formatDateMedium(subscription.nextInvoiceAt)}</Field>
          </>
        }
        usage={
          subscription.usage && (
            <UsageBlock
              title="Usage this period"
              window={`Since ${formatDateMedium(subscription.usage.since)}`}
              usage={subscription.usage}
              costLabel="Estimated cost"
              note={
                <>
                  {subscription.usage.measuredUntil
                    ? `Measured up to ${formatDateTimeShort(subscription.usage.measuredUntil)}; each hour is added once it closes.`
                    : 'Each hour is added once it closes.'}{' '}
                  The invoice has the final amount.
                </>
              }
            />
          )
        }
        footer={
          (note || listingUrl) && (
            <Stack gap="xs">
              {note && <Text size="sm">{note}</Text>}
              {listingUrl && (
                <Text size="sm" c="dimmed">
                  Prefer your AWS bill?{' '}
                  <Anchor href={listingUrl} target="_blank" rel="noopener noreferrer" size="sm">
                    Pay via AWS Marketplace
                  </Anchor>
                  . The card is stopped once the subscription is applied to this workspace, with a final invoice for the
                  usage it has not been billed for yet.
                </Text>
              )}
            </Stack>
          )
        }
      />
      <CancelModal opened={cancelOpen} onClose={() => setCancelOpen(false)} reasons={billing.cancellationReasons} />
    </>
  );
}

/** The AWS Marketplace subscription paying now. Nothing here is ours to change: the subscription is managed in AWS. */
function RunningLicense({ subscription }: { subscription: Subscription }) {
  return (
    <SubscriptionPanel
      kind="aws_marketplace"
      status={subscription.status}
      action={
        <>
          {subscription.invoicesUrl && <InvoicesButton href={subscription.invoicesUrl} />}
          <Button
            component="a"
            href={AWS_SUBSCRIPTIONS_URL}
            target="_blank"
            rel="noopener noreferrer"
            variant="default"
          >
            Manage subscription
          </Button>
        </>
      }
      fields={
        <>
          <Field label="Billing method" hint={subscription.awsAccountId && `AWS account ${subscription.awsAccountId}`}>
            {KIND_METHOD.aws_marketplace}
          </Field>
          <Field label="Current period">
            {formatDateRange(subscription.periodStartsAt, subscription.periodEndsAt)}
          </Field>
          <Field label="Next invoice">{formatDateMedium(subscription.nextInvoiceAt)}</Field>
        </>
      }
      usage={
        subscription.usage && (
          <UsageBlock
            title="Usage this period"
            window={`Since ${formatDateMedium(subscription.usage.since)}`}
            usage={subscription.usage}
            costLabel="Estimated cost"
            note="Worker-minutes reported to AWS this calendar month, which the AWS bill for the month is counted from. The subscription is cancelled in AWS, not here."
          />
        )
      }
    />
  );
}

/** A subscription that ended: what it was, when, and what its last bill covered. */
function StoppedSubscription({ subscription }: { subscription: Subscription }) {
  const usage = subscription.usage;
  const window = usage ? formatDateRange(usage.since, usage.until) : '';
  const note =
    subscription.kind === 'card'
      ? subscription.finalInvoice && <FinalInvoiceStatus invoice={subscription.finalInvoice} />
      : 'Worker-minutes reported to AWS in the month the subscription ended, on that account’s AWS bill.';

  return (
    <SubscriptionPanel
      kind={subscription.kind}
      status="cancelled"
      action={subscription.invoicesUrl && <InvoicesButton href={subscription.invoicesUrl} />}
      fields={
        <>
          <Field label="Billing method">{KIND_METHOD[subscription.kind]}</Field>
          <Field label="Active period">{formatDateRange(subscription.periodStartsAt, subscription.periodEndsAt)}</Field>
          <Field label="Cancelled">{formatDateMedium(subscription.cancelledAt)}</Field>
        </>
      }
      usage={
        usage ? (
          <UsageBlock title="Final usage" window={window} usage={usage} costLabel="Final cost" note={note} />
        ) : (
          <Note>{note}</Note>
        )
      }
    />
  );
}

/**
 * The Active subscription section when nothing pays: the trial, a stopped
 * workspace, or one that never had a card. The ways to pay are offered here.
 */
function NoSubscription({ billing, listingUrl }: { billing: Billing; listingUrl: string | null }) {
  const [busy, setBusy] = useState(false);
  const post = (path: string) => {
    setBusy(true);
    router.post(path, {}, { onFinish: () => setBusy(false) });
  };
  const payLater = billing.canPay ? 'Add a card to carry on.' : 'Talk to us to carry on.';
  const endedOn = billing.cancelsAt && formatDateMedium(billing.cancelsAt);

  let status: keyof typeof STATUS_BADGE = 'none';
  let title = 'No active subscription';
  let body: React.ReactNode;
  let primary: React.ReactNode = null;
  let offerPayment = true;
  switch (billing.status) {
    case 'trialing':
      status = 'trialing';
      title = 'Free trial';
      body = billing.trial && (
        <>
          You are on the free trial, on one worker: {billing.trial.daysLeft} of {billing.trial.days} days left, the last
          day is {formatCalendarDay(billing.trial.lastDay)}.{' '}
          {billing.canPay
            ? 'Add a card to keep going after it and choose how many workers to run.'
            : 'Talk to us to keep going after it.'}
        </>
      );
      break;
    case 'allowance':
      status = 'allowance';
      title = 'Free trial';
      body = `The free trial has ended, so no new sessions start. Anything already running finishes. ${payLater}`;
      break;
    case 'canceled':
      status = 'cancelled';
      body = (
        <>
          {endedOn
            ? `On ${endedOn} the subscription ended, so no new sessions start.`
            : 'The subscription has ended, so no new sessions start.'}{' '}
          Your data is kept.{' '}
          {billing.hasUnpaidInvoice ? 'The final invoice is unpaid: pay it to add a card again.' : payLater}
        </>
      );
      if (billing.hasUnpaidInvoice) {
        offerPayment = false;
        primary = (
          <Button color="red" loading={busy} onClick={() => post(companyBillingInvoicePaymentPath())}>
            Pay final invoice
          </Button>
        );
      }
      break;
    case 'payment_failed':
      status = 'payment_failed';
      body = billing.hasUnpaidInvoice
        ? 'Your last payment did not go through, so no new sessions start. Pay the open invoice to restore access.'
        : 'Your last payment did not go through, so no new sessions start. The invoice will appear here shortly.';
      offerPayment = false;
      primary = billing.hasUnpaidInvoice && (
        <Button color="red" loading={busy} onClick={() => post(companyBillingInvoicePaymentPath())}>
          Pay invoice
        </Button>
      );
      break;
    case 'awaiting_subscription':
      body = 'AWS has not confirmed the subscription yet. The workspace starts as soon as it does.';
      offerPayment = false;
      break;
    default:
      body = 'No card is on file, so nothing is billed yet. Add a card to pay for the worker-minutes you use.';
  }

  return (
    <Card withBorder padding="lg">
      <Stack gap="md">
        <Group gap="sm">
          <Text component="h3" fz="xl" fw={600} m={0}>
            {title}
          </Text>
          <StatusBadge status={status} />
        </Group>
        <Text size="sm" c="dimmed">
          {body}
        </Text>
        {billing.finalInvoice && <FinalInvoiceStatus invoice={billing.finalInvoice} />}
        <Group>
          {primary}
          {offerPayment && billing.canPay && (
            <Button
              leftSection={<IconCreditCard size={16} />}
              loading={busy}
              onClick={() => post(companyBillingCheckoutPath())}
            >
              Add a card
            </Button>
          )}
          {offerPayment && listingUrl && <PayViaMarketplaceButton href={listingUrl} />}
        </Group>
      </Stack>
    </Card>
  );
}

// The final invoice is settled by a background job a minute or two after the
// cancellation; the page asks for its props again until it is done.
function useRefreshWhileSettling(settling: boolean) {
  useEffect(() => {
    if (!settling) return;
    const timer = setInterval(() => router.reload({ only: ['billing', 'subscriptions'] }), SETTLING_POLL_MS);
    return () => clearInterval(timer);
  }, [settling]);
}

const settlingState = (invoice: FinalInvoice | null) =>
  invoice?.state === 'cancelling' || invoice?.state === 'settling';

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

const BillingPage = () => {
  const { company, billing, subscriptions, listingUrl, checkoutResult, marketplaceProposal } = usePage<Props>().props;
  const active = subscriptions.active;
  const price = quotedPrice(active, billing);
  useRefreshWhileSettling(
    settlingState(billing.finalInvoice) || subscriptions.previous.some((entry) => settlingState(entry.finalInvoice)),
  );

  return (
    <AuthLayout>
      <Head title={`Billing — ${company.name}`} />
      <SettingsTabs active="billing" companyName={company.name}>
        <Stack gap="xl" maw={880}>
          <Stack gap={4}>
            <Text component="h1" fz={28} fw={700} m={0}>
              Billing
            </Text>
            {price && (
              <Text fz="md" c="dimmed">
                {priceSentence(price)}
              </Text>
            )}
          </Stack>

          <CheckoutResult result={checkoutResult} billing={billing} />
          {marketplaceProposal && <MarketplaceProposalCard proposal={marketplaceProposal} companyName={company.name} />}

          <Stack gap="md">
            <SectionHeader title="Active subscription" />
            {active?.kind === 'card' && <RunningCard subscription={active} billing={billing} listingUrl={listingUrl} />}
            {active?.kind === 'aws_marketplace' && <RunningLicense subscription={active} />}
            {!active && <NoSubscription billing={billing} listingUrl={listingUrl} />}
          </Stack>

          {subscriptions.previous.length > 0 && (
            <Stack gap="md">
              <SectionHeader title="Previous subscriptions" count={subscriptions.previous.length} />
              {subscriptions.previous.map((entry) => (
                <StoppedSubscription
                  key={`${entry.kind}-${entry.cancelledAt}-${entry.periodStartsAt}`}
                  subscription={entry}
                />
              ))}
            </Stack>
          )}
        </Stack>
      </SettingsTabs>
    </AuthLayout>
  );
};

export default BillingPage;
