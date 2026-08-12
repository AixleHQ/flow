import { Head, InfiniteScroll, router, usePage } from '@inertiajs/react';
import { Box, Center, Group, Loader, Select, Table, Text, Tooltip } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useWorkflowRunListCableUpdates } from 'shared/lib/hooks/useWorkflowRunListCableUpdates';
import { PageHeader } from 'shared/ui/PageHeader';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface WorkflowRun {
  id: number;
  workflowId: number;
  workflowName: string;
  state: string;
  mode: string;
  stepsCompleted: number;
  stepsTotal: number;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
}

type Filters = Record<string, string | undefined>;

type Props = {
  runs: WorkflowRun[];
  filters: Filters;
  perPage: number;
};

// Labels only — the color now comes from the shared tone map in StatusBadge, so
// `running` cannot be blue here and yellow somewhere else.
const STATE_LABELS: Record<string, string> = {
  completed: 'Completed',
  running: 'Running',
  paused: 'Paused',
  failed: 'Failed',
  cancelled: 'Cancelled',
  pending: 'Pending',
};

const MODE_LABELS: Record<string, string> = {
  interactive: 'Interactive',
  non_interactive: 'Auto-run',
  mixed: 'Custom',
};

const STATE_OPTIONS = [
  { value: 'running', label: 'Running' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'pending', label: 'Pending' },
];

const PER_PAGE_OPTIONS = ['20', '50', '100'];

const ACTIVE_STATES = new Set(['running', 'paused', 'pending']);

function formatDuration(start: string | null, end: string | null, state: string): string {
  if (!start) return '—';
  // Only tick against "now" while the run is actually still going. A cancelled
  // run has a start and no end, and counting to now rendered "8487m 25s".
  if (!end && !ACTIVE_STATES.has(state)) return '—';
  const s = new Date(start).getTime();
  const e = end ? new Date(end).getTime() : Date.now();
  const sec = Math.floor((e - s) / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  return `${min}m ${sec % 60}s`;
}

const pulseKeyframes = `
@keyframes wfRunPulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.8; transform: scale(1.05); }
}
`;

const WorkflowRunsPage = ({ runs, filters, perPage }: Props) => {
  const { project } = usePage<{ props: { project: { id: number; name: string } } }>().props as unknown as {
    project: { id: number; name: string };
  };

  const [runMap, setRunMap] = useState<Map<number, WorkflowRun>>(() => {
    const m = new Map<number, WorkflowRun>();
    runs.forEach((r) => m.set(r.id, r));
    return m;
  });

  // Accumulate pages loaded by InfiniteScroll into the local map.
  useEffect(() => {
    setRunMap((prev) => {
      const next = new Map(prev);
      runs.forEach((r) => next.set(r.id, r));
      return next;
    });
  }, [runs]);

  // Live cable updates: update existing runs in-place without reloading pages.
  const onUpdate = useCallback((run: Record<string, unknown>) => {
    setRunMap((prev) => {
      const id = run.id as number;
      if (!prev.has(id)) return prev;
      return new Map(prev).set(id, { ...prev.get(id)!, ...(run as unknown as WorkflowRun) });
    });
  }, []);

  useWorkflowRunListCableUpdates({ projectId: project.id, onUpdate });

  // Preserve insertion order: runMap is keyed by id in the order pages arrived.
  const orderedRuns = useMemo(() => Array.from(runMap.values()), [runMap]);

  const runsUrl = `/company/projects/${project.id}/workflow_runs`;

  const navigate = useCallback(
    (q: Filters, newPerPage?: number) => {
      const pp = newPerPage ?? perPage;
      const queryParams = pp !== 20 ? { q, per_page: pp } : { q };
      router.get(runsUrl, queryParams as Record<string, string | number | Filters>, {
        preserveState: true,
        preserveScroll: true,
      });
    },
    [runsUrl, perPage],
  );

  const onFilterChange = useCallback(
    (key: string, value: string | null) => {
      const q = { ...filters };
      if (value) {
        q[key] = value;
      } else {
        delete q[key];
      }
      navigate(q);
    },
    [filters, navigate],
  );

  const onPerPageChange = useCallback(
    (value: string | null) => {
      navigate(filters, value ? Number(value) : 20);
    },
    [filters, navigate],
  );

  return (
    <>
      <Head title={`Workflow Runs — ${project.name}`} />
      <style dangerouslySetInnerHTML={{ __html: pulseKeyframes }} />
      <PageHeader title="Runs" subtitle="Workflow executions for this project, newest first." />
      <Group justify="space-between" mb="md">
        <Group gap="sm">
          <Select
            placeholder="Status"
            aria-label="Filter by status"
            data={STATE_OPTIONS}
            value={filters.state_eq ?? null}
            onChange={(v) => onFilterChange('state_eq', v)}
            clearable
            size="sm"
            w={140}
          />
          <Select
            data={PER_PAGE_OPTIONS}
            aria-label="Rows per page"
            value={String(perPage)}
            onChange={onPerPageChange}
            size="sm"
            w={80}
            allowDeselect={false}
          />
        </Group>
      </Group>

      {runs.length === 0 ? (
        <Box py="xl" ta="center">
          <Text c="dimmed">{Object.keys(filters).length > 0 ? 'No runs match filter' : 'No workflow runs yet'}</Text>
        </Box>
      ) : (
        <InfiniteScroll
          data="runs"
          loading={() => (
            <Center py="md">
              <Loader size="sm" />
            </Center>
          )}
        >
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover verticalSpacing={6} fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Workflow</Table.Th>
                  <Table.Th>Mode</Table.Th>
                  <Table.Th>Steps</Table.Th>
                  <Table.Th>Duration</Table.Th>
                  <Table.Th>Started</Table.Th>
                  <Table.Th w={40} />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {orderedRuns.map((run) => (
                  <RunRow key={run.id} run={run} projectId={project.id} />
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </InfiniteScroll>
      )}
    </>
  );
};

function RunRow({ run, projectId }: { run: WorkflowRun; projectId: number }) {
  const label = STATE_LABELS[run.state] ?? run.state;
  const runUrl = `/company/projects/${projectId}/workflow_runs/${run.id}`;

  return (
    <Table.Tr style={{ cursor: 'pointer' }} onClick={() => router.visit(runUrl)}>
      <Table.Td>
        <StatusBadge
          state={run.state}
          style={run.state === 'running' ? { animation: 'wfRunPulse 2s ease-in-out infinite' } : undefined}
        >
          {label}
        </StatusBadge>
      </Table.Td>
      <Table.Td>
        <Text size="sm" fw={500}>
          {run.workflowName}
        </Text>
        <Text size="xs" ff="monospace" c="dimmed">
          #{run.id}
        </Text>
      </Table.Td>
      <Table.Td>
        <Text size="xs">{MODE_LABELS[run.mode] ?? run.mode}</Text>
      </Table.Td>
      <Table.Td>
        <Text size="xs" ff="monospace">
          {run.stepsCompleted}/{run.stepsTotal}
        </Text>
      </Table.Td>
      <Table.Td>
        <Text size="xs" ff="monospace" c="dimmed">
          {formatDuration(run.startedAt, run.completedAt, run.state)}
        </Text>
      </Table.Td>
      <Table.Td>
        <Tooltip label={run.createdAt ? new Date(run.createdAt).toLocaleString() : ''}>
          <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>
            {formatDistanceToNow(new Date(run.createdAt), { addSuffix: true })}
          </Text>
        </Tooltip>
      </Table.Td>
      <Table.Td>
        <Tooltip label="Open run">
          <IconExternalLink size={16} style={{ opacity: 0.5 }} />
        </Tooltip>
      </Table.Td>
    </Table.Tr>
  );
}

setPageLayout(WorkflowRunsPage, persistentProjectLayout);

export default WorkflowRunsPage;
