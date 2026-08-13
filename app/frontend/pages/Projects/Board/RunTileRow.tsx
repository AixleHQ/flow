import { router } from '@inertiajs/react';
import { ActionIcon, Box, Group, Text, Tooltip } from '@mantine/core';
import { IconExternalLink, IconTerminal2 } from '@tabler/icons-react';
import type { ReactNode } from 'react';

import { NeutralStatusChip } from './NeutralStatusChip';
import { runSessionId, type TaskWorkflowRun } from './taskRuns';

// One run, rendered as a single compact row: state chip, a link to the run page, a
// caller-supplied trailing slot, and the jump-into-the-session control. Shared by the
// Details tab's "Latest run" block and the Runs tab's history so the two tiles cannot
// drift apart — the only intentional difference is what goes in `trailing` (the run's
// timestamp in the Runs tab, a "View runs" button on the Details tab).
export function RunTileRow({
  run,
  projectId,
  trailing,
}: {
  run: TaskWorkflowRun;
  projectId: number;
  trailing?: ReactNode;
}) {
  const sessionId = runSessionId(run);

  return (
    <Group justify="space-between" wrap="nowrap" gap="xs">
      <NeutralStatusChip state={run.state} />
      <Text
        component="a"
        href={`/company/projects/${projectId}/workflow_runs/${run.id}`}
        target="_blank"
        rel="noopener"
        size="xs"
        c="brand"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 4,
          flex: 1,
          minWidth: 0,
          textDecoration: 'none',
        }}
      >
        <Box component="span" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {run.workflowName ?? 'Workflow run'}
        </Box>
        <IconExternalLink size={11} style={{ flexShrink: 0 }} />
      </Text>
      {trailing}
      {sessionId != null && (
        <Tooltip label={`Open session #${sessionId}`}>
          <ActionIcon
            variant="subtle"
            size="xs"
            aria-label={`Open session #${sessionId}`}
            style={{ flexShrink: 0 }}
            onClick={() => router.visit(`/company/projects/${projectId}/sessions/${sessionId}`)}
          >
            <IconTerminal2 size={13} />
          </ActionIcon>
        </Tooltip>
      )}
    </Group>
  );
}
