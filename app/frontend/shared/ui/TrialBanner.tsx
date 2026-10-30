import { router, usePage } from '@inertiajs/react';
import { Button } from '@mantine/core';
import { IconAlertTriangle, IconCreditCard, IconHourglassHigh } from '@tabler/icons-react';
import { useState } from 'react';

import { formatCalendarDay } from 'shared/lib/formatDate';
import { companyBillingCheckoutPath, companyBillingInvoicePaymentPath } from 'shared/routes';

import classes from './TrialBanner.module.css';
import type { SharedProps } from './types';

const URGENT_DAYS_LEFT = 3;

const days = (count: number) => `${count} day${count === 1 ? '' : 's'}`;

/**
 * Where a workspace on the free trial stands, across the top of every screen.
 *
 * Absent for everyone else: the prop is only sent while a trial is running or
 * has ended.
 */
export const TrialBanner = () => {
  const { trial, permissions } = usePage<Partial<SharedProps> & { [key: string]: unknown }>().props;
  const [starting, setStarting] = useState(false);
  if (!trial) return null;

  const blocked = trial.state === 'blocked';
  const spent = Math.min(100, Math.round(((trial.days - trial.daysLeft) / Math.max(trial.days, 1)) * 100));
  const urgent = !blocked && trial.daysLeft <= URGENT_DAYS_LEFT;
  const lastDay = formatCalendarDay(trial.lastDay);
  // A failed payment is undone by paying its invoice; a new card would open a
  // second subscription and bill the same minutes twice.
  const unpaid = blocked && trial.status === 'payment_failed';
  const ended = blocked && trial.status === 'canceled';
  const carryOn = trial.canPay ? 'Add a card to carry on.' : 'Talk to us to carry on.';
  const Icon = urgent || blocked ? IconAlertTriangle : IconHourglassHigh;

  return (
    <div className={`${classes.root} ${blocked ? classes.blocked : ''}`} role="status">
      <Icon size={20} className={classes.icon} aria-hidden />
      <p className={classes.text}>
        {unpaid ? (
          <>
            Your last payment did not go through, so no new sessions start. Anything already running finishes. Pay the
            open invoice to carry on.
          </>
        ) : ended ? (
          <>
            Your subscription has ended, so no new sessions start. Anything already running finishes. Your data is kept.{' '}
            {carryOn}
          </>
        ) : blocked ? (
          <>
            <strong>Your free trial has ended,</strong> so no new sessions start. Anything already running finishes.{' '}
            {carryOn}
          </>
        ) : urgent ? (
          <>
            <strong>
              {trial.daysLeft <= 1
                ? 'The free trial ends within a day'
                : `The free trial ends in ${days(trial.daysLeft)}`}
            </strong>{' '}
            — the last day is {lastDay}. After that, no new sessions start.
          </>
        ) : (
          <>
            You are on the free trial, on one worker: <span className={classes.figure}>{days(trial.daysLeft)}</span>{' '}
            left, the last day is {lastDay}.
          </>
        )}
      </p>
      {!blocked && (
        <div className={classes.meter} aria-hidden>
          <div className={classes.meterFill} style={{ width: `${spent}%` }} />
        </div>
      )}
      {trial.canPay && permissions?.isAdmin && (
        <Button
          className={classes.cta}
          leftSection={<IconCreditCard size={16} />}
          loading={starting}
          onClick={() => {
            setStarting(true);
            router.post(
              unpaid ? companyBillingInvoicePaymentPath() : companyBillingCheckoutPath(),
              {},
              {
                onFinish: () => setStarting(false),
              },
            );
          }}
        >
          {unpaid ? 'Pay invoice' : urgent ? 'Add a card now' : 'Add a card'}
        </Button>
      )}
    </div>
  );
};
