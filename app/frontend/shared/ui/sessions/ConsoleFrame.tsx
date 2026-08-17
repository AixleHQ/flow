import { IconTerminal2 } from '@tabler/icons-react';
import type { CSSProperties, ReactNode } from 'react';

import classes from './ConsoleFrame.module.css';

interface ConsoleFrameProps {
  /** Left of the bar: `repo · /workspace`, or a session label inside a run. */
  label: ReactNode;
  /** Show the pulsing Live badge — a session that is still producing output. */
  live?: boolean;
  /** Read-only note shown under the body. Omitted while the session is live. */
  footer?: ReactNode;
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}

/**
 * The unified console/workspace frame. Callers supply the body (a ttyd iframe,
 * a replay, or the three-column workspace) and nothing else about the chrome.
 */
export function ConsoleFrame({ label, live = false, footer, children, className, style }: ConsoleFrameProps) {
  return (
    <div className={className ? `${classes.frame} ${className}` : classes.frame} style={style}>
      <div className={classes.bar}>
        <span className={classes.repo}>
          <IconTerminal2 size={14} />
          {label}
        </span>
        {live && (
          <span className={classes.live}>
            <span className={classes.liveDot} />
            Live
          </span>
        )}
      </div>
      <div className={classes.body}>{children}</div>
      {footer && <div className={classes.footer}>{footer}</div>}
    </div>
  );
}
