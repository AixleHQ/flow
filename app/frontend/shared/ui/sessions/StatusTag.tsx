import type { ReactNode } from 'react';

import { statusLabel, statusTone, type StatusTone } from '../StatusBadge';

import classes from './StatusTag.module.css';

const TONE_CLASS: Record<StatusTone, string> = {
  success: classes.success,
  running: classes.running,
  info: classes.info,
  warning: classes.warning,
  danger: classes.danger,
  neutral: classes.neutral,
};

interface StatusTagProps {
  /** Raw state string from the API, e.g. `running`. */
  state?: string | null;
  /** Override the tone when the state string is not self-describing. */
  tone?: StatusTone;
  /** Override the visible text. Defaults to a humanized `state`. */
  children?: ReactNode;
  /** Drop the dot and the uppercasing — used for the model chips. */
  plain?: boolean;
  className?: string;
}

/**
 * The dense status tag used across Sessions & Runs (list rows, detail headers,
 * session cards). Tone resolution is shared with {@link StatusBadge} so a state
 * cannot read green here and grey there; only the shape differs.
 */
export function StatusTag({ state, tone, children, plain = false, className }: StatusTagProps) {
  const resolved = tone ?? statusTone(state);
  const classNames = [classes.tag, plain ? classes.plain : TONE_CLASS[resolved], className].filter(Boolean).join(' ');

  return (
    <span className={classNames}>
      {!plain && <span className={classes.dot} />}
      {children ?? (state ? statusLabel(state) : '—')}
    </span>
  );
}
