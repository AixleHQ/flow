import { Badge, Box, Tooltip } from '@mantine/core';

import styles from './BoardPage.module.css';
import { CHIP_TOOLTIP_PROPS } from './chipTooltip';

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

// Width reserved for the chip column, so a stack of gate rows lines its links up instead of
// ragging with the length of each state word. Sized for the longest label ("waiting", the widest
// of the four and the state a gate spends most of its life in) with headroom to spare: at 68 the
// column was two pixels short of it and Mantine's badge ellipsis clipped it to "waiti…". It is a
// floor rather than a hard width — see the call site — so a wider label would push its own row's
// link right instead of losing letters.
export const GATE_CHIP_WIDTH = 78;

export function GateStatusChip({ status, tooltip }: { status: string; tooltip?: string }) {
  const state = GATE_CHIP_STATES[status] ?? GATE_CHIP_PENDING;
  // Only a gate still waiting on CI is going anywhere — the dot pulses just like a running run's.
  const isWaiting = status === 'pending';

  const dot = (
    <Box
      w={6}
      h={6}
      className={isWaiting ? styles.workflowDotActive : undefined}
      style={{ borderRadius: '50%', backgroundColor: state.dot, flexShrink: 0 }}
    />
  );

  if (!tooltip) {
    return (
      <Badge size="xs" variant="outline" color="gray" leftSection={dot} style={{ fontSize: 10, cursor: 'default' }}>
        {state.label}
      </Badge>
    );
  }

  // The gate type moved off the row and into the tooltip — it is what the oversized pill used to
  // spell out, and the row's link already says which repo and which PR or run it belongs to. A
  // stale gate's diagnostic rides here too, and that one is a whole sentence, so the tooltip wraps
  // at the same width the card's CI summary chip uses instead of stretching off the panel.
  //
  // The look is the shared board-chip one, the same tooltip a card wears in a collapsed column —
  // see `CHIP_TOOLTIP_PROPS`.
  //
  // The trigger is a real button, not a bare span. This tooltip is the only place a stale gate's
  // diagnostic exists, so hover cannot be the only way in: as a button the chip is reachable by
  // Tab, `events.focus` opens the tooltip when it lands there (Mantine wires the open tooltip up
  // as the button's `aria-describedby`, so a screen reader reads the diagnostic out), and
  // `events.touch` opens it on a tap for anyone without a pointer to hover with. Escape or a press
  // outside closes it again.
  return (
    <Tooltip
      {...CHIP_TOOLTIP_PROPS}
      label={tooltip}
      multiline
      maw={320}
      events={{ hover: true, focus: true, touch: true }}
    >
      <Badge
        component="button"
        type="button"
        // The visible label is the state word alone, which says nothing about there being more to
        // read; the name keeps that word (so speaking it still matches what is on screen) and adds
        // what activating the chip is for.
        aria-label={`${state.label} CI gate — show details`}
        className="mantine-focus-auto"
        size="xs"
        variant="outline"
        color="gray"
        leftSection={dot}
        style={{ fontSize: 10, fontFamily: 'inherit', appearance: 'none', cursor: 'help' }}
      >
        {state.label}
      </Badge>
    </Tooltip>
  );
}
