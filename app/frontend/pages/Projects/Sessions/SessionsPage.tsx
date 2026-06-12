import { Head, InfiniteScroll, router, usePage } from '@inertiajs/react';
import { Badge, Box, Button, Center, Group, Loader, Select, Table, Text, Tooltip } from '@mantine/core';
import { IconExternalLink, IconPlus } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useSessionListCableUpdates } from 'shared/lib/hooks/useSessionListCableUpdates';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Session {
  id: number;
  sessionType: string;
  agentType: string | null;
  state: string;
  mode: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  createdAt: string;
  totalTokens: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costCents: number;
  models: string[] | null;
  userName: string | null;
  userEmail: string | null;
  projectName: string | null;
  artifactsReviewed: boolean | null;
  pendingArtifactsCount: number;
  initialPrompt: string | null;
}

type Filters = Record<string, string | undefined>;

type Props = {
  sessions: Session[];
  filters: Filters;
  perPage: number;
};

const AGENT_LABELS: Record<string, { label: string; color: string }> = {
  claude_code: { label: 'Claude Code', color: 'orange' },
  cursor_cli: { label: 'Cursor CLI', color: 'violet' },
  codex: { label: 'Codex', color: 'teal' },
  gemini_cli: { label: 'Gemini CLI', color: 'blue' },
};

const STATE_CONFIG: Record<string, { label: string; color: string }> = {
  not_started: { label: 'Pending', color: 'gray' },
  running: { label: 'Starting', color: 'blue' },
  ready: { label: 'Running', color: 'green' },
  finishing: { label: 'Finishing', color: 'yellow' },
  finished: { label: 'Finished', color: 'gray' },
  failed: { label: 'Failed', color: 'red' },
};

const SESSION_TYPE_LABELS: Record<string, string> = {
  agent_session: 'Standalone',
  workflow_step: 'Workflow step',
  auth_setup: 'Auth setup',
  tool_setup: 'Tool setup',
};

function formatTokens(n: number): string {
  if (!n || n === 0) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function formatCost(cents: number): string {
  if (!cents || cents === 0) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function costColor(cents: number): string | undefined {
  if (!cents || cents === 0) return undefined;
  if (cents <= 100) return 'var(--mantine-color-green-5)';
  if (cents <= 500) return 'var(--mantine-color-yellow-5)';
  return 'var(--mantine-color-red-5)';
}

function formatDuration(startedAt: string | null, finishedAt: string | null, state: string): string {
  if (!startedAt) return '—';
  const start = new Date(startedAt);
  const end = finishedAt ? new Date(finishedAt) : state === 'running' || state === 'ready' ? new Date() : null;
  if (!end) return '—';
  const seconds = Math.round((end.getTime() - start.getTime()) / 1000);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

const AGENT_FILTER_OPTIONS = [
  { value: 'claude_code', label: 'Claude Code' },
  { value: 'cursor_cli', label: 'Cursor CLI' },
  { value: 'codex', label: 'Codex' },
  { value: 'gemini_cli', label: 'Gemini CLI' },
];

const STATE_FILTER_OPTIONS = [
  { value: 'running', label: 'Starting' },
  { value: 'ready', label: 'Running' },
  { value: 'finishing', label: 'Finishing' },
  { value: 'finished', label: 'Finished' },
  { value: 'failed', label: 'Failed' },
];

const PER_PAGE_OPTIONS = ['20', '50', '100'];

const CLICKABLE_STATES = new Set(['ready', 'finished', 'failed', 'cancelled', 'stopped']);

const SessionsPage = ({ sessions, filters, perPage }: Props) => {
  const { project } = usePage<{ props: { project: { id: number; name: string } } }>().props as unknown as {
    project: { id: number; name: string };
  };

  // Local map mirrors the InfiniteScroll-accumulated sessions prop.
  // Cable updates patch individual entries in-place without touching the rest,
  // so live state changes are visible across all loaded pages simultaneously.
  const [sessionMap, setSessionMap] = useState<Map<number, Session>>(() => {
    const map = new Map<number, Session>();
    for (const s of sessions) map.set(s.id, s);
    return map;
  });

  // Sync new pages loaded by InfiniteScroll into the map (append-only: cable
  // updates take precedence over Inertia prop data for existing entries).
  useEffect(() => {
    setSessionMap((prev) => {
      const newEntries = sessions.filter((s) => !prev.has(s.id));
      if (newEntries.length === 0) return prev;
      const map = new Map(prev);
      for (const s of newEntries) map.set(s.id, s);
      return map;
    });
  }, [sessions]);

  useSessionListCableUpdates({
    projectId: project.id,
    onUpdate: useCallback((updated) => {
      setSessionMap((prev) => {
        if (!prev.has(updated.id as number)) return prev;
        const map = new Map(prev);
        map.set(updated.id as number, updated as unknown as Session);
        return map;
      });
    }, []),
  });

  const displaySessions = useMemo(() => [...sessionMap.values()], [sessionMap]);

  const sessionsUrl = `/company/projects/${project.id}/sessions`;

  const navigate = useCallback(
    (q: Filters, newPerPage?: number) => {
      const pp = newPerPage ?? perPage;
      const queryParams = pp !== 20 ? { q, per_page: pp } : { q };
      router.get(sessionsUrl, queryParams as Record<string, string | number | Filters>, {
        preserveState: true,
        preserveScroll: true,
      });
    },
    [sessionsUrl, perPage],
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
      <Head title={`Sessions — ${project.name}`} />
      <Group justify="space-between" mb="md">
        <Group gap="sm">
          <Select
            placeholder="Agent"
            data={AGENT_FILTER_OPTIONS}
            value={filters.agent_type_eq ?? null}
            onChange={(v) => onFilterChange('agent_type_eq', v)}
            clearable
            size="sm"
            w={160}
          />
          <Select
            placeholder="Status"
            data={STATE_FILTER_OPTIONS}
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
            allowDeselect={true}
          />
        </Group>
        <Button size="sm" leftSection={<IconPlus size={16} />} component="a" href={`${sessionsUrl}/new`}>
          New Session
        </Button>
      </Group>

      {sessions.length === 0 ? (
        <Box py="xl" ta="center">
          <Text c="dimmed">{Object.keys(filters).length > 0 ? 'No sessions match filters' : 'No sessions yet'}</Text>
        </Box>
      ) : (
        <InfiniteScroll
          data="sessions"
          loading={() => (
            <Center py="md">
              <Loader size="sm" />
            </Center>
          )}
        >
          <Table.ScrollContainer minWidth={900}>
            <Table striped highlightOnHover verticalSpacing={6} fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>ID</Table.Th>
                  <Table.Th>Agent</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>User</Table.Th>
                  <Table.Th ta="right">Tokens</Table.Th>
                  <Table.Th ta="right">Cost</Table.Th>
                  <Table.Th>Models</Table.Th>
                  <Table.Th>Duration</Table.Th>
                  <Table.Th>Started</Table.Th>
                  <Table.Th w={40} />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {displaySessions.map((s) => (
                  <SessionRow key={s.id} session={s} projectId={project.id} />
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </InfiniteScroll>
      )}
    </>
  );
};

function SessionRow({ session: s, projectId }: { session: Session; projectId: number }) {
  const agent = AGENT_LABELS[s.agentType ?? ''] ?? { label: s.agentType ?? '—', color: 'gray' };
  const stateConfig = STATE_CONFIG[s.state] ?? { label: s.state, color: 'gray' };
  const typeLabel = SESSION_TYPE_LABELS[s.sessionType] ?? s.sessionType;

  const tokenBreakdown = [
    s.inputTokens > 0 && `in: ${formatTokens(s.inputTokens)}`,
    s.outputTokens > 0 && `out: ${formatTokens(s.outputTokens)}`,
    s.cacheReadTokens > 0 && `cache_r: ${formatTokens(s.cacheReadTokens)}`,
    s.cacheWriteTokens > 0 && `cache_w: ${formatTokens(s.cacheWriteTokens)}`,
  ]
    .filter(Boolean)
    .join(', ');

  const isClickable = CLICKABLE_STATES.has(s.state);
  const sessionUrl = `/company/projects/${projectId}/sessions/${s.id}`;

  return (
    <Table.Tr
      style={isClickable ? { cursor: 'pointer' } : undefined}
      onClick={isClickable ? () => router.visit(sessionUrl) : undefined}
    >
      <Table.Td>
        <Text size="xs" ff="monospace" c="dimmed">
          #{s.id}
        </Text>
      </Table.Td>
      <Table.Td>
        <Badge color={agent.color} size="sm" variant="filled">
          {agent.label}
        </Badge>
      </Table.Td>
      <Table.Td>
        <Text size="xs" c="dimmed">
          {typeLabel}
        </Text>
      </Table.Td>
      <Table.Td>
        <Group gap={4}>
          <Badge color={stateConfig.color} size="sm" variant="outline">
            {stateConfig.label}
          </Badge>
          {s.state === 'finished' && !s.artifactsReviewed && s.pendingArtifactsCount > 0 && (
            <Badge color="yellow" size="xs">
              {s.pendingArtifactsCount} pending
            </Badge>
          )}
        </Group>
      </Table.Td>
      <Table.Td>
        <Tooltip label={s.userEmail ?? ''} disabled={!s.userEmail}>
          <Text size="sm" truncate maw={120}>
            {s.userName ?? '—'}
          </Text>
        </Tooltip>
      </Table.Td>
      <Table.Td ta="right">
        <Tooltip label={tokenBreakdown || 'No token data'}>
          <Text size="xs" ff="monospace">
            {formatTokens(s.totalTokens)}
          </Text>
        </Tooltip>
      </Table.Td>
      <Table.Td ta="right">
        <Text size="xs" ff="monospace" fw={s.costCents > 0 ? 600 : 400} style={{ color: costColor(s.costCents) }}>
          {formatCost(s.costCents)}
        </Text>
      </Table.Td>
      <Table.Td>
        <Group gap={4} wrap="wrap">
          {(s.models ?? []).map((m) => (
            <Badge key={m} size="xs" variant="outline">
              {m}
            </Badge>
          ))}
        </Group>
      </Table.Td>
      <Table.Td>
        <Text size="xs" ff="monospace" c="dimmed">
          {formatDuration(s.startedAt, s.finishedAt, s.state)}
        </Text>
      </Table.Td>
      <Table.Td>
        <Tooltip label={s.startedAt ? new Date(s.startedAt).toLocaleString() : s.createdAt}>
          <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>
            {formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}
          </Text>
        </Tooltip>
      </Table.Td>
      <Table.Td>
        {isClickable && (
          <Tooltip label="Open session">
            <a href={sessionUrl} onClick={(e) => e.stopPropagation()}>
              <IconExternalLink size={16} />
            </a>
          </Tooltip>
        )}
      </Table.Td>
    </Table.Tr>
  );
}

setPageLayout(SessionsPage, persistentProjectLayout);

export default SessionsPage;
