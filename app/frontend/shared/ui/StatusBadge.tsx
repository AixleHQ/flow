import { Badge, type BadgeProps } from '@mantine/core';
import type { ReactNode } from 'react';

export type StatusTone = 'success' | 'running' | 'info' | 'warning' | 'danger' | 'neutral';

/**
 * The canonical state → tone map.
 *
 * Six independent `STATE_CONFIG` / `STATUS_COLORS` maps had drifted apart
 * across the app (`running` was blue in one place and yellow in another;
 * `finished` was grey on sessions while `completed` was green on runs), so the
 * same underlying condition read differently depending on which screen you were
 * looking at. New states go here, not into a page-local map.
 */
const STATE_TONES: Record<string, StatusTone> = {
  // terminal, good
  completed: 'success',
  succeeded: 'success',
  finished: 'success',
  ready: 'success',
  active: 'success',
  connected: 'success',
  enabled: 'success',
  // in flight
  running: 'running',
  in_progress: 'running',
  starting: 'running',
  finishing: 'running',
  // waiting on something
  pending: 'info',
  queued: 'info',
  not_started: 'info',
  invited: 'info',
  // needs attention but not broken
  paused: 'warning',
  inactive: 'warning',
  suspended: 'warning',
  // broken
  failed: 'danger',
  error: 'danger',
  // terminal, neutral
  cancelled: 'neutral',
  archived: 'neutral',
  disabled: 'neutral',
};

const TONE_STYLES: Record<StatusTone, { color: string; background: string; borderColor: string }> = {
  success: {
    color: 'var(--app-success-fg)',
    background: 'var(--app-success-bg)',
    borderColor: 'var(--app-success-border)',
  },
  running: { color: 'var(--app-info-fg)', background: 'var(--app-info-bg)', borderColor: 'var(--app-info-border)' },
  info: { color: 'var(--app-info-fg)', background: 'var(--app-info-bg)', borderColor: 'var(--app-info-border)' },
  warning: {
    color: 'var(--app-warning-fg)',
    background: 'var(--app-warning-bg)',
    borderColor: 'var(--app-warning-border)',
  },
  danger: {
    color: 'var(--app-danger-fg)',
    background: 'var(--app-danger-bg)',
    borderColor: 'var(--app-danger-border)',
  },
  neutral: {
    color: 'var(--app-text-secondary)',
    background: 'var(--app-action-hover)',
    borderColor: 'var(--app-border-default)',
  },
};

/** Resolve a raw state string to a tone. Unknown states read as neutral. */
export function statusTone(state: string | null | undefined): StatusTone {
  if (!state) return 'neutral';
  return STATE_TONES[state] ?? 'neutral';
}

/** `in_progress` → `In progress`. Only used when no explicit label is given. */
export function statusLabel(state: string): string {
  const words = state.replace(/_/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

interface StatusBadgeProps extends Omit<BadgeProps, 'color' | 'variant' | 'children'> {
  /** Raw state string from the API, e.g. `running`. */
  state?: string | null;
  /** Override the tone when the state string is not self-describing. */
  tone?: StatusTone;
  /** Override the visible text. Defaults to a humanized `state`. */
  children?: ReactNode;
}

/**
 * The one status badge in the app. Tokenized, so it clears AA in both schemes —
 * the raw Mantine `green`/`orange`/`blue` badges it replaces measured as low as
 * 1.55:1 on a light canvas at 9px/700.
 */
export function StatusBadge({ state, tone, children, size = 'sm', ...props }: StatusBadgeProps) {
  const resolved = tone ?? statusTone(state);
  return (
    <Badge size={size} variant="default" styles={{ root: TONE_STYLES[resolved] }} {...props}>
      {children ?? (state ? statusLabel(state) : '—')}
    </Badge>
  );
}
