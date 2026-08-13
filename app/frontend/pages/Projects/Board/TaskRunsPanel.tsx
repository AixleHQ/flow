import { Box, Button, Group, Stack, Tabs, Text } from '@mantine/core';
import { IconRefresh } from '@tabler/icons-react';

import { formatDateTime } from 'shared/lib/formatDate';

import { formatCostCents } from './boardFormat';
import { RunStepTimeline } from './RunStepTimeline';
import { RunTileRow } from './RunTileRow';
import type { TaskWorkflowRun } from './taskRuns';

// The task drawer's "Runs" tab: totals across the task's runs, then the run history —
// each entry the shared run tile, with the latest run also carrying its step timeline.
export function TaskRunsPanel({
  runs,
  projectId,
  canRetry,
  retrying,
  onRetry,
}: {
  runs: TaskWorkflowRun[];
  projectId: number;
  canRetry: boolean;
  retrying: boolean;
  onRetry: () => void;
}) {
  const latestRunId = runs[0]?.id;
  const succeeded = runs.filter((r) => r.state === 'completed' || r.state === 'succeeded').length;

  return (
    <Tabs.Panel value="runs" p="md" style={{ flex: 1, overflow: 'auto' }}>
      <Stack gap="md">
        {runs.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="xl">
            No runs yet.
          </Text>
        ) : (
          <>
            {/* Totals row */}
            <Group gap="lg" wrap="wrap">
              <Box>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                  Runs
                </Text>
                <Text size="sm" fw={600}>
                  {runs.length}
                </Text>
              </Box>
              <Box>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                  Success rate
                </Text>
                <Text size="sm" fw={600}>
                  {Math.round((succeeded / runs.length) * 100)}%
                </Text>
              </Box>
              {runs.some((r) => r.totalCostCents != null) && (
                <Box>
                  <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                    Total cost
                  </Text>
                  <Text size="sm" ff="monospace" fw={600}>
                    {formatCostCents(runs.reduce((s, r) => s + (r.totalCostCents ?? 0), 0))}
                  </Text>
                </Box>
              )}
            </Group>

            {/* Run history */}
            <Stack gap={4}>
              {runs.map((run) => (
                <Box key={run.id} p="xs" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
                  <RunTileRow
                    run={run}
                    projectId={projectId}
                    trailing={
                      <Text size="xs" c="dimmed" style={{ flexShrink: 0 }}>
                        {formatDateTime(run.createdAt)}
                      </Text>
                    }
                  />

                  {/* Step timeline for first (latest) run */}
                  {run.id === latestRunId && (run.steps ?? []).length > 0 && (
                    <RunStepTimeline steps={run.steps ?? []} />
                  )}

                  {/* Retry in Runs tab for failed run (AC-56) — retry runs the column's bound
                      workflow, so the caller hides it when the task's column has none */}
                  {run.state === 'failed' && canRetry && (
                    <Box mt="xs">
                      <Button
                        size="compact-xs"
                        variant="outline"
                        color="red"
                        leftSection={<IconRefresh size={11} />}
                        loading={retrying}
                        onClick={onRetry}
                      >
                        Retry run
                      </Button>
                    </Box>
                  )}
                </Box>
              ))}
            </Stack>
          </>
        )}
      </Stack>
    </Tabs.Panel>
  );
}
