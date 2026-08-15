import { Badge, Box, Tooltip } from '@mantine/core';

import styles from './BoardPage.module.css';

// A CI gate in the same compact vocabulary the Runs chips use: an outlined gray badge with the
// dot doing the colour work, rather than the filled uppercase pill the gate rows used to carry.
// The label is the gate's CI state, so the row no longer needs a second line repeating it.
//
// `stale` keeps a colour of its own rather than sharing red with a failure: a failed check is a
// verdict, a stale gate is the absence of one, and they need different reactions (fix the code
// vs. look at why CI never reported).
const GATE_CHIP_PENDING = { label: 'waiting', dot: 'var(--mantine-color-yellow-6)' };

const GATE_CHIP_STATES: Record<string, { label: string; dot: string }> = {
  pending: GATE_CHIP_PENDING,
  succeeded: { label: 'passed', dot: 'var(--app-success-fg)' },
  failed: { label: 'failed', dot: 'var(--app-danger-fg)' },
  stale: { label: 'stale', dot: 'var(--mantine-color-orange-6)' },
};

// Width the chip column is pinned to, so a stack of gate rows lines its links up instead of
// ragging with the length of each state word.
export const GATE_CHIP_WIDTH = 68;

export function GateStatusChip({ status, tooltip }: { status: string; tooltip?: string }) {
  const state = GATE_CHIP_STATES[status] ?? GATE_CHIP_PENDING;
  // Only a gate still waiting on CI is going anywhere — the dot pulses just like a running run's.
  const isWaiting = status === 'pending';

  const chip = (
    <Badge
      size="xs"
      variant="outline"
      color="gray"
      leftSection={
        <Box
          w={6}
          h={6}
          className={isWaiting ? styles.workflowDotActive : undefined}
          style={{ borderRadius: '50%', backgroundColor: state.dot, flexShrink: 0 }}
        />
      }
      style={{ fontSize: 10, cursor: 'default' }}
    >
      {state.label}
    </Badge>
  );

  // The gate type moved off the row and into the tooltip — it is what the oversized pill used to
  // spell out, and the row's link already says which repo and which PR or run it belongs to.
  return tooltip ? <Tooltip label={tooltip}>{chip}</Tooltip> : chip;
}
