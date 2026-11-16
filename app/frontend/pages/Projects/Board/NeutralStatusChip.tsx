import { Badge, Box } from '@mantine/core';

import styles from './BoardPage.module.css';
import { WORKFLOW_ACTIVE_STATES, workflowStatusColor } from './taskRuns';

// --- Neutral Status Chip (AC-13, AC-28) ---

// An outlined chip carrying the raw state string, with the dot doing the colour work —
// pulsing while the run is still going.
export function NeutralStatusChip({ state, size = 'xs' }: { state: string; size?: string }) {
  const isWorking = WORKFLOW_ACTIVE_STATES.has(state) && state !== 'queued';

  return (
    <Badge
      size={size as 'xs' | 'sm'}
      variant="outline"
      color="gray"
      leftSection={
        <Box
          w={6}
          h={6}
          className={isWorking ? styles.workflowDotActive : undefined}
          style={{ borderRadius: '50%', backgroundColor: workflowStatusColor(state), flexShrink: 0 }}
        />
      }
      style={{ fontSize: 10, cursor: 'default' }}
    >
      {state}
    </Badge>
  );
}
