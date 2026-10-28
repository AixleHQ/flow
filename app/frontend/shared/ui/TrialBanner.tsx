import { router, usePage } from '@inertiajs/react';
import { Button } from '@mantine/core';
import { IconAlertTriangle, IconCreditCard, IconHourglassHigh } from '@tabler/icons-react';
import { useState } from 'react';

import { companyBillingCheckoutPath, companyBillingInvoicePaymentPath } from 'shared/routes';

import classes from './TrialBanner.module.css';
import type { SharedProps } from './types';

const URGENT_SPENT_PERCENT = 85;
const URGENT_HOURS_LEFT = 24;

const workers = (count: number | null) => `${count} worker${count === 1 ? '' : 's'}`;
const hours = (count: number) => `${count} hour${count === 1 ? '' : 's'}`;

/**
 * What a workspace on free capacity has spent, across the top of every screen.
 *
 * The allowance is a quantity and the workspace sets the rate it burns at, so
 * "40 hours left" means four days at one worker and four hours at ten. Both
 * numbers are shown, because only the second one answers "when do I need to do
 * something about this".
 *
 * Absent for everyone else: the prop is only sent while an allowance is running
 * or spent.
 */
export const TrialBanner = () => {
  const { trial, permissions } = usePage<Partial<SharedProps> & { [key: string]: unknown }>().props;
  const [starting, setStarting] = useState(false);
  if (!trial) return null;

  const blocked = trial.state === 'blocked';
  const spent = Math.min(100, Math.round((trial.usedHours / Math.max(trial.allowanceHours, 1)) * 100));
  const hoursLeft = trial.hoursLeftAtCurrentRate;
  const urgent = !blocked && (spent >= URGENT_SPENT_PERCENT || (hoursLeft != null && hoursLeft < URGENT_HOURS_LEFT));
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
            <strong>
              You have used all <span className={classes.figure}>{trial.allowanceHours}</span> of your free
              worker-hours,
            </strong>{' '}
            so no new sessions start. Anything already running finishes. {carryOn}
          </>
        ) : urgent && hoursLeft != null ? (
          <>
            <strong>Free capacity runs out in about {hours(hoursLeft)}</strong> at {workers(trial.maxSessions)}. After
            that, no new sessions start.
          </>
        ) : urgent ? (
          <>
            <strong>Free capacity is almost gone:</strong> <span className={classes.figure}>{trial.usedHours}</span> of{' '}
            <span className={classes.figure}>{trial.allowanceHours}</span> worker-hours used. When it runs out, no new
            sessions start.
          </>
        ) : (
          <>
            You are on free capacity: <span className={classes.figure}>{trial.usedHours}</span> of{' '}
            <span className={classes.figure}>{trial.allowanceHours}</span> worker-hours used.
            {hoursLeft != null && (
              <>
                {' '}
                At {workers(trial.maxSessions)} that is about <span className={classes.figure}>{hoursLeft}</span> hours
                left.
              </>
            )}
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
