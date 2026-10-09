import { Head, router, usePage } from '@inertiajs/react';
import { Alert, Badge, Button, Card, Group, List, Modal, Select, Stack, Text, Textarea } from '@mantine/core';
import { useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { formatDateMedium, formatDateTimeShort } from 'shared/lib/formatDate';
import {
  companyBillingCancellationPath,
  companyBillingCheckoutPath,
  companyBillingInvoicePaymentPath,
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

interface Billing {
  status: BillingStatus;
  periodStartsAt: string | null;
  periodEndsAt: string | null;
  cancelsAt: string | null;
  usage: Usage | null;
  allowance: { hours: number; usedHours: number } | null;
  canPay: boolean;
  hasUnpaidInvoice: boolean;
  cancellationReasons: string[];
}

interface Props {
  company: { name: string };
  billing: Billing;
  checkoutResult: 'done' | 'cancelled' | null;
  [key: string]: unknown;
}

const STATUS_BADGE: Record<BillingStatus, { label: string; color: string }> = {
  trialing: { label: 'Free capacity', color: 'blue' },
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

const formatMoney = (cents: number, currency: string) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.toUpperCase() }).format(cents / 100);

const formatMinutes = (minutes: number) => new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(minutes);

function CheckoutResult({ result, status }: { result: Props['checkoutResult']; status: BillingStatus }) {
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
  const confirmed = status === 'active';
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

function SubscriptionCard({ billing }: { billing: Billing }) {
  const [cancelOpen, setCancelOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const badge = STATUS_BADGE[billing.status];
  const endsOn = formatDateMedium(billing.cancelsAt ?? billing.periodEndsAt);

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
      body = billing.allowance && (
        <>
          You are on free capacity: {billing.allowance.usedHours} of {billing.allowance.hours} worker-hours used. Add a
          card to keep going once it runs out.
        </>
      );
      action = addCard;
      break;
    case 'allowance':
      body = 'The free worker-hours are used up, so no new sessions start. Anything already running finishes.';
      action = addCard;
      break;
    case 'active':
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
      body = (
        <>
          On {endsOn} the subscription ended, so no new sessions start. Your data is kept. Add a card to restore access.
        </>
      );
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
          <Text fw={600}>Subscription</Text>
          <Badge color={badge.color} variant="light">
            {badge.label}
          </Badge>
        </Group>
        <Text size="sm" c="dimmed">
          {body}
        </Text>
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

const BillingPage = () => {
  const { company, billing, checkoutResult } = usePage<Props>().props;

  return (
    <AuthLayout>
      <Head title={`Billing — ${company.name}`} />
      <SettingsTabs active="billing" companyName={company.name}>
        <Stack gap="lg" maw={720}>
          <CheckoutResult result={checkoutResult} status={billing.status} />
          <SubscriptionCard billing={billing} />
          {billing.usage && <UsageCard billing={billing} usage={billing.usage} />}
        </Stack>
      </SettingsTabs>
    </AuthLayout>
  );
};

export default BillingPage;
