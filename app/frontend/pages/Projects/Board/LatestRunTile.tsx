import { Box, Button, Text } from '@mantine/core';
import { IconArrowRight, IconBolt } from '@tabler/icons-react';

import { formatCostCents, formatDuration } from './boardFormat';
import { RunTileRow } from './RunTileRow';
import type { TaskWorkflowRun } from './taskRuns';

// The Details tab's "Latest run" block (AC-19): the same row a Runs tab entry renders,
// with a "View runs" button where that tab shows the run's timestamp, and the run's
// duration/cost on one compact line underneath.
export function LatestRunTile({
  run,
  projectId,
  onViewRuns,
}: {
  run: TaskWorkflowRun;
  projectId: number;
  onViewRuns: () => void;
}) {
  const dur = run.durationSeconds;
  const cost = run.totalCostCents;

  return (
    <Box style={{ marginBottom: 20 }}>
      {/* sec-label */}
      <Box
        style={{
          fontSize: 12,
          fontWeight: 600,
          letterSpacing: '0.04em',
          textTransform: 'uppercase',
          color: 'var(--mantine-color-dimmed)',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          paddingBottom: 10,
          borderBottom: '1px solid var(--app-border-default)',
          marginBottom: 14,
        }}
      >
        <IconBolt size={14} color="var(--app-primary-strong)" />
        Latest run
      </Box>
      {/* run tile — same row as a Runs tab entry, with "View runs" where that tab shows the date */}
      <Box p="xs" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
        <RunTileRow
          run={run}
          projectId={projectId}
          trailing={
            <Button
              variant="subtle"
              size="compact-xs"
              rightSection={<IconArrowRight size={12} />}
              onClick={onViewRuns}
              style={{ flexShrink: 0 }}
            >
              View runs
            </Button>
          }
        />
        {(dur != null || cost != null) && (
          <Text size="xs" c="dimmed" ff="monospace" mt={6}>
            {[dur != null ? formatDuration(dur) : null, cost != null ? formatCostCents(cost) : null]
              .filter(Boolean)
              .join(' · ')}
          </Text>
        )}
      </Box>
    </Box>
  );
}
