import { IconTerminal2 } from '@tabler/icons-react';
import type { CSSProperties, ReactNode, Ref } from 'react';

import classes from './ConsoleFrame.module.css';

interface ConsoleFrameProps {
  /** Left of the bar: `repo · /workspace`, or a session label inside a run. */
  label: ReactNode;
  /** Show the pulsing Live badge — a session that is still producing output. */
  live?: boolean;
  /** Read-only note shown under the body. Omitted while the session is live. */
  footer?: ReactNode;
  /** Controls at the right end of the bar, after the Live badge. */
  actions?: ReactNode;
  /** Pin the frame over the whole viewport, covering the app sidebar and page header. */
  maximized?: boolean;
  ref?: Ref<HTMLDivElement>;
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}

/**
 * The unified console/workspace frame. Callers supply the body (a ttyd iframe,
 * a replay, or the three-column workspace) and nothing else about the chrome.
 */
export function ConsoleFrame({
  label,
  live = false,
  footer,
  actions,
  maximized = false,
  ref,
  children,
  className,
  style,
}: ConsoleFrameProps) {
  const frameClass = [classes.frame, className, maximized && classes.maximized].filter(Boolean).join(' ');
  return (
    <div
      ref={ref}
      className={frameClass}
      style={style}
      role="region"
      aria-label="Console"
      data-maximized={maximized || undefined}
    >
      <div className={classes.bar}>
        <span className={classes.repo}>
          <IconTerminal2 size={14} />
          {label}
        </span>
        <span className={classes.barEnd}>
          {live && (
            <span className={classes.live}>
              <span className={classes.liveDot} />
              Live
            </span>
          )}
          {actions}
        </span>
      </div>
      <div className={classes.body}>{children}</div>
      {footer && <div className={classes.footer}>{footer}</div>}
    </div>
  );
}
