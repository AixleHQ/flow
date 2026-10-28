import { Link, usePage } from '@inertiajs/react';
import { Button } from '@mantine/core';
import { IconAlertTriangle, IconHourglassHigh } from '@tabler/icons-react';

import { companySettingsBillingPath } from 'shared/routes';

// The banner slot above the content is one thing, so it keeps one look. The
// content differs entirely: there is no allowance to show and no card to add.
import classes from './TrialBanner.module.css';
import type { SharedProps } from './types';

/** Where the buyer manages the subscription — it is theirs, not ours. */
const SUBSCRIPTIONS_URL = 'https://aws.amazon.com/marketplace/library';

/**
 * What a workspace AWS Marketplace bills is told while it is stopped.
 *
 * The allowance banner beside this one withholds itself from this payer: there
 * was never an allowance, and Checkout refuses the card it offers. Without
 * something here, a stopped workspace says nothing and sessions that never
 * start read as a fault rather than a subscription.
 *
 * Absent while the workspace is running. The subscription lives in the buyer's
 * AWS account, and there is no number of ours worth putting on every screen.
 */
export const MarketplaceBanner = () => {
  const { marketplace } = usePage<Partial<SharedProps> & { [key: string]: unknown }>().props;
  if (!marketplace) return null;

  const waiting = marketplace.status === 'awaiting_subscription';
  const Icon = waiting ? IconHourglassHigh : IconAlertTriangle;

  return (
    <div className={`${classes.root} ${classes.blocked}`} role="status">
      <Icon size={20} className={classes.icon} aria-hidden />
      <p className={classes.text}>
        {waiting ? (
          <>
            AWS has not confirmed your subscription yet, so no new sessions start. This usually takes a moment. Nothing
            needs doing here.
          </>
        ) : (
          <>
            Your AWS Marketplace subscription has ended, so no new sessions start. Anything already running finishes.
            Your data is kept. Subscribe again in AWS Marketplace to carry on, or pay by card.
          </>
        )}
      </p>
      {!waiting && (
        <>
          <Button size="xs" variant="filled" component="a" href={SUBSCRIPTIONS_URL} target="_blank" rel="noreferrer">
            Open AWS Marketplace
          </Button>
          {/* Not a checkout: the card is offered on the Billing tab, beside
              what AWS was billed this month, and only there. */}
          <Button size="xs" variant="outline" color="white" component={Link} href={companySettingsBillingPath()}>
            Pay by card instead
          </Button>
        </>
      )}
    </div>
  );
};
