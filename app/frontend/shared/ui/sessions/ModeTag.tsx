import { Tooltip } from '@mantine/core';
import { IconBolt } from '@tabler/icons-react';

import classes from './ModeTag.module.css';

const MODE_LABELS: Record<string, string> = {
  interactive: 'Interactive',
  non_interactive: 'Auto-run',
  automatic: 'Automatic',
  mixed: 'Custom',
};

/** `non_interactive` → `Auto-run`; unknown modes fall back to the raw value. */
export function modeLabel(mode: string | null | undefined): string {
  if (!mode) return '—';
  return MODE_LABELS[mode] ?? mode;
}

/** Modes that run without a human in the loop, and so earn the bolt. */
function isAutomated(mode: string | null | undefined): boolean {
  return mode === 'non_interactive' || mode === 'automatic';
}

interface ModeTagProps {
  mode: string | null | undefined;
}

/**
 * Bolt chip shown next to an automated run's agent. Renders nothing for
 * interactive work — a chip on every row would stop meaning anything.
 */
export function ModeTag({ mode }: ModeTagProps) {
  if (!isAutomated(mode)) return null;

  return (
    <Tooltip label={`Automated — runs as ${modeLabel(mode)}`} withArrow>
      <span className={classes.tag} aria-label={`Automated — ${modeLabel(mode)}`}>
        <IconBolt size={13} />
      </span>
    </Tooltip>
  );
}
