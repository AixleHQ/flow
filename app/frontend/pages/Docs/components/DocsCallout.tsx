import { IconAlertCircle, IconAlertTriangle, IconBulb, IconInfoCircle } from '@tabler/icons-react';
import { type ReactNode } from 'react';

import classes from '../DocsPage.module.css';

type CalloutVariant = 'info' | 'warning' | 'danger' | 'tip';

interface Props {
  children: ReactNode;
  variant?: CalloutVariant;
}

const CALLOUT_CONFIG: Record<CalloutVariant, { icon: typeof IconInfoCircle; className: string; label: string }> = {
  info: { icon: IconInfoCircle, className: classes.calloutInfo, label: 'Info' },
  warning: { icon: IconAlertTriangle, className: classes.calloutWarning, label: 'Warning' },
  danger: { icon: IconAlertCircle, className: classes.calloutDanger, label: 'Danger' },
  tip: { icon: IconBulb, className: classes.calloutTip, label: 'Tip' },
};

export function DocsCallout({ children, variant = 'info' }: Props) {
  const { icon: Icon, className, label } = CALLOUT_CONFIG[variant];

  return (
    <div role="note" aria-label={label} className={`${classes.callout} ${className}`}>
      <span className={classes.calloutIcon}>
        <Icon size={16} />
      </span>
      <div className={classes.calloutBody}>{children}</div>
    </div>
  );
}
