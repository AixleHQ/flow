import { router, usePage } from '@inertiajs/react';
import { Button } from '@mantine/core';
import { useState } from 'react';

import { companyBillingCheckoutPath } from 'shared/routes';

import classes from './TrialBanner.module.css';
import type { SharedProps } from './types';

/**
 * What a workspace on free capacity has spent, on every screen.
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

  return (
    <div className={`${classes.root} ${blocked ? classes.blocked : ''}`} role="status">
      <p className={classes.text}>
        {blocked ? (
          <>
            You have used all <span className={classes.figure}>{trial.allowanceHours}</span> of your free worker-hours,
            so no new sessions start. Anything already running finishes.{' '}
            {trial.canPay ? 'Add a card to carry on.' : 'Talk to us to carry on.'}
          </>
        ) : (
          <>
            You are on free capacity: <span className={classes.figure}>{trial.usedHours}</span> of{' '}
            <span className={classes.figure}>{trial.allowanceHours}</span> worker-hours used.
            {trial.hoursLeftAtCurrentRate != null && (
              <>
                {' '}
                At {trial.maxSessions} worker{trial.maxSessions === 1 ? '' : 's'} that is about{' '}
                <span className={classes.figure}>{trial.hoursLeftAtCurrentRate}</span> hours left.
              </>
            )}
          </>
        )}
      </p>
      {trial.canPay && permissions?.isAdmin ? (
        <Button
          size="xs"
          variant={blocked ? 'filled' : 'default'}
          loading={starting}
          onClick={() => {
            setStarting(true);
            router.post(companyBillingCheckoutPath(), {}, { onFinish: () => setStarting(false) });
          }}
        >
          Add a card
        </Button>
      ) : (
        <div className={classes.meter} aria-hidden>
          <div className={classes.meterFill} style={{ width: `${spent}%` }} />
        </div>
      )}
    </div>
  );
};
