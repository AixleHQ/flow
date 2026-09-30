import { Box, Group, Text, Tooltip } from '@mantine/core';
import { Fragment, type ReactElement } from 'react';

import { formatDuration, formatRelativeTime } from './boardFormat';
import { CHIP_TOOLTIP_PROPS } from './chipTooltip';
import { workflowRunStateLabel, workflowStatusColor } from './taskRuns';
import type { Task } from './types';

type RecentRun = Task['recentWorkflowRuns'][number];

// In dark mode the chip tooltip's background sits a few shades off the column behind it, so a
// multi-row block needs an edge to read as one surface.
const FRAME = '1px solid var(--app-border-strong)';

export function RecentRunsTooltip({ runs, children }: { runs: RecentRun[]; children: ReactElement }) {
  return (
    <Tooltip
      {...CHIP_TOOLTIP_PROPS}
      label={<RecentRunsList runs={runs} />}
      styles={{
        tooltip: { border: FRAME, boxShadow: '0 8px 24px rgba(0, 0, 0, 0.35)' },
        arrow: { border: FRAME },
      }}
    >
      {children}
    </Tooltip>
  );
}

function RecentRunsList({ runs }: { runs: RecentRun[] }) {
  return (
    <Box py={2}>
      <Text fz={10} fw={600} tt="uppercase" mb={6} style={{ letterSpacing: 0.4, opacity: 0.6 }}>
        Recent runs
      </Text>
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: 'auto auto auto',
          columnGap: 16,
          rowGap: 4,
          alignItems: 'center',
        }}
      >
        {runs.map((run) => (
          <Fragment key={run.id}>
            <Group gap={6} wrap="nowrap">
              <Box
                w={6}
                h={6}
                style={{ borderRadius: '50%', backgroundColor: workflowStatusColor(run.state), flexShrink: 0 }}
              />
              <Text fz={12} fw={500}>
                {workflowRunStateLabel(run.state)}
              </Text>
            </Group>
            <Text fz={12} style={{ opacity: 0.7, whiteSpace: 'nowrap' }}>
              {formatRelativeTime(run.createdAt)}
            </Text>
            <Text fz={12} ta="right" style={{ opacity: 0.7, whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>
              {run.durationSeconds != null ? formatDuration(run.durationSeconds) : ''}
            </Text>
            {run.errorMessage && (
              <Text fz={11} pl={12} mt={-2} lineClamp={2} style={{ gridColumn: '1 / -1', opacity: 0.6 }}>
                {run.errorMessage}
              </Text>
            )}
          </Fragment>
        ))}
      </Box>
    </Box>
  );
}
