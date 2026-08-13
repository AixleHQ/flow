import { Badge, Box } from '@mantine/core';

import styles from './BoardPage.module.css';
import { WORKFLOW_ACTIVE_STATES } from './taskRuns';

// --- Neutral Status Chip (AC-13, AC-28) ---

// An outlined chip carrying the raw state string, with the dot doing the colour work —
// pulsing while the run is still going.
export function NeutralStatusChip({ state, size = 'xs' }: { state: string; size?: string }) {
  const isRunning = WORKFLOW_ACTIVE_STATES.has(state);
  const isSuccess = state === 'completed' || state === 'succeeded';
  const isFailed = state === 'failed';
  let dotColor = 'var(--mantine-color-gray-5)';
  if (isRunning) dotColor = 'var(--app-warning-fg)';
  else if (isSuccess) dotColor = 'var(--app-success-fg)';
  else if (isFailed) dotColor = 'var(--app-danger-fg)';

  return (
    <Badge
      size={size as 'xs' | 'sm'}
      variant="outline"
      color="gray"
      leftSection={
        <Box
          w={6}
          h={6}
          className={isRunning ? styles.workflowDotActive : undefined}
          style={{ borderRadius: '50%', backgroundColor: dotColor, flexShrink: 0 }}
        />
      }
      style={{ fontSize: 10, cursor: 'default' }}
    >
      {state}
    </Badge>
  );
}
