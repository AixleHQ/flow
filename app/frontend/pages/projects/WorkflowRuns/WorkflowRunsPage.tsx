import { Head, InfiniteScroll, router, usePage, usePoll } from '@inertiajs/react';
import { Badge, Box, Center, Group, Loader, Select, Table, Text, Tooltip } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useMemo } from 'react';

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

const STATE_CONFIG: Record<string, { label: string; color: string }> = {
  completed: { label: 'Completed', color: 'green' },
  running: { label: 'Running', color: 'blue' },
  paused: { label: 'Paused', color: 'yellow' },
  failed: { label: 'Failed', color: 'red' },
  cancelled: { label: 'Cancelled', color: 'gray' },
  pending: { label: 'Pending', color: 'gray' },
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

function formatDuration(start: string | null, end: string | null): string {
  if (!start) return '—';
  const s = new Date(start).getTime();
  const e = end ? new Date(end).getTime() : Date.now();
  const sec = Math.floor((e - s) / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  return `${min}m ${sec % 60}s`;
}

const ACTIVE_STATES = new Set(['running', 'paused', 'pending']);

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

  const hasActive = useMemo(() => runs.some((r) => ACTIVE_STATES.has(r.state)), [runs]);
  usePoll(10_000, { only: ['runs'] }, { autoStart: hasActive });

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
      <Group justify="space-between" mb="md">
        <Group gap="sm">
          <Select
            placeholder="Status"
            data={STATE_OPTIONS}
            value={filters.state_eq ?? null}
            onChange={(v) => onFilterChange('state_eq', v)}
            clearable
            size="sm"
            w={140}
          />
          <Select
            data={PER_PAGE_OPTIONS}
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
                {runs.map((run) => (
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
  const cfg = STATE_CONFIG[run.state] ?? { label: run.state, color: 'gray' };
  const runUrl = `/company/projects/${projectId}/workflow_runs/${run.id}`;

  return (
    <Table.Tr style={{ cursor: 'pointer' }} onClick={() => router.visit(runUrl)}>
      <Table.Td>
        <Badge
          color={cfg.color}
          size="sm"
          variant="outline"
          style={run.state === 'running' ? { animation: 'wfRunPulse 2s ease-in-out infinite' } : undefined}
        >
          {cfg.label}
        </Badge>
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
          {formatDuration(run.startedAt, run.completedAt)}
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
