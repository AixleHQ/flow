import { Head, InfiniteScroll, router, usePage } from '@inertiajs/react';
import { Badge, Box, Button, Center, Group, Loader, Select, Table, Text, Tooltip } from '@mantine/core';
import { IconExternalLink, IconLock, IconPlus } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { useSessionListCableUpdates } from 'shared/lib/hooks/useSessionListCableUpdates';
import { AGENT_BRAND_COLORS } from 'shared/theme/vendorColors';
import { PageHeader } from 'shared/ui/PageHeader';
import { StatusBadge } from 'shared/ui/StatusBadge';

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
  // False when the owner's profile keeps this phase of their sessions private —
  // the row still reports what it cost, but it cannot be opened.
  viewable: boolean;
}

type Filters = Record<string, string | undefined>;

type Props = {
  sessions: Session[];
  filters: Filters;
  perPage: number;
};

// Labels only — the vendor dot next to them reads from AGENT_BRAND_COLORS.
const AGENT_LABELS: Record<string, { label: string }> = {
  claude_code: { label: 'Claude Code' },
  cursor_cli: { label: 'Cursor CLI' },
  codex: { label: 'Codex' },
  gemini_cli: { label: 'Gemini CLI' },
};

// Session lifecycle labels are domain-specific ("running" means the container
// is starting; "ready" means the agent is working), so the labels stay local —
// only the color comes from the shared tone map.
const STATE_CONFIG: Record<string, { label: string }> = {
  not_started: { label: 'Pending' },
  running: { label: 'Starting' },
  ready: { label: 'Running' },
  finishing: { label: 'Finishing' },
  finished: { label: 'Finished' },
  failed: { label: 'Failed' },
};

const SESSION_TYPE_LABELS: Record<string, string> = {
  agent_session: 'Standalone',
  workflow_step: 'Workflow step',
  auth_setup: 'Auth setup',
  tool_setup: 'Tool setup',
};

/**
 * Model identifiers arrive as full inference-profile ARNs or region-prefixed
 * ids. Printed raw they filled the column with
 * `arn:aws:bedrock:us-east-1:541894707537:application-inference-profi…` — all
 * prefix, no model. Keep the part that identifies the model; the full string
 * stays in the tooltip.
 */
function shortModelName(id: string): string {
  let name = id.includes('/') ? (id.split('/').pop() ?? id) : id;
  name = name.replace(/^(us|eu|apac|global)\./i, '');
  name = name.replace(/^(anthropic|openai|google|meta)\./i, '');
  name = name.replace(/-v\d+:\d+$/, '');
  name = name.replace(/-(\d{8})$/, '');
  return name;
}

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

// Mantine's raw green/yellow/red at shade 5 measure 1.6-2.4:1 on a light
// canvas, and cost is 12px monospace — the --app-*-fg tokens are AA in both
// schemes.
function costColor(cents: number): string | undefined {
  if (!cents || cents === 0) return undefined;
  if (cents <= 100) return 'var(--app-success-fg)';
  if (cents <= 500) return 'var(--app-warning-fg)';
  return 'var(--app-danger-fg)';
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
  const { canExecute } = useProjectPermissions();

  // Local map mirrors the InfiniteScroll-accumulated sessions prop.
  // Cable updates patch individual entries in-place without touching the rest,
  // so live state changes are visible across all loaded pages simultaneously.
  const [sessionMap, setSessionMap] = useState<Map<number, Session>>(() => {
    const map = new Map<number, Session>();
    for (const s of sessions) map.set(s.id, s);
    return map;
  });

  const prevFiltersRef = useRef<string>('');

  // Sync new pages loaded by InfiniteScroll into the map. On filter change,
  // reset the map to avoid showing stale entries from the previous filter.
  useEffect(() => {
    const filtersKey = JSON.stringify(filters);
    const filtersChanged = filtersKey !== prevFiltersRef.current;
    prevFiltersRef.current = filtersKey;

    setSessionMap((prev) => {
      // Filter change: reset the map to the new first page (stale entries from
      // the old filter must not survive a narrowed result set).
      if (filtersChanged) {
        const map = new Map<number, Session>();
        for (const s of sessions) map.set(s.id, s);
        return map;
      }
      // New InfiniteScroll page: append only entries not already present (cable
      // updates take precedence over Inertia prop data for existing entries).
      const newEntries = sessions.filter((s) => !prev.has(s.id));
      if (newEntries.length === 0) return prev;
      const map = new Map(prev);
      for (const s of newEntries) map.set(s.id, s);
      return map;
    });
  }, [sessions, filters]);

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
      <PageHeader
        title="Sessions"
        subtitle="Every agent run in this project, with the tokens and cost it spent."
        actions={
          canExecute && (
            <Button size="sm" leftSection={<IconPlus size={16} />} component="a" href={`${sessionsUrl}/new`}>
              New Session
            </Button>
          )
        }
      />
      <Group justify="space-between" mb="md">
        <Group gap="sm">
          <Select
            placeholder="Agent"
            aria-label="Filter by agent"
            data={AGENT_FILTER_OPTIONS}
            value={filters.agent_type_eq ?? null}
            onChange={(v) => onFilterChange('agent_type_eq', v)}
            clearable
            size="sm"
            w={160}
          />
          <Select
            placeholder="Status"
            aria-label="Filter by status"
            data={STATE_FILTER_OPTIONS}
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
            allowDeselect={true}
          />
        </Group>
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
                  <Table.Th miw={110}>Agent</Table.Th>
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
  const agent = AGENT_LABELS[s.agentType ?? ''] ?? { label: s.agentType ?? '—' };
  const stateConfig = STATE_CONFIG[s.state] ?? { label: s.state };
  const typeLabel = SESSION_TYPE_LABELS[s.sessionType] ?? s.sessionType;

  const tokenBreakdown = [
    s.inputTokens > 0 && `in: ${formatTokens(s.inputTokens)}`,
    s.outputTokens > 0 && `out: ${formatTokens(s.outputTokens)}`,
    s.cacheReadTokens > 0 && `cache_r: ${formatTokens(s.cacheReadTokens)}`,
    s.cacheWriteTokens > 0 && `cache_w: ${formatTokens(s.cacheWriteTokens)}`,
  ]
    .filter(Boolean)
    .join(', ');

  const isClickable = CLICKABLE_STATES.has(s.state) && s.viewable;
  const isPrivate = !s.viewable;
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
        {/* A vendor dot plus the plain label: the filled badge truncated to
            "CLAUD…" at 1440px, so the column said nothing. */}
        <Group gap={6} wrap="nowrap">
          <Box
            w={7}
            h={7}
            style={{
              borderRadius: '50%',
              backgroundColor: AGENT_BRAND_COLORS[s.agentType ?? ''] ?? 'var(--app-text-tertiary)',
              flexShrink: 0,
            }}
          />
          <Text size="xs" style={{ whiteSpace: 'nowrap' }}>
            {agent.label}
          </Text>
        </Group>
      </Table.Td>
      <Table.Td>
        <Text size="xs" c="dimmed">
          {typeLabel}
        </Text>
      </Table.Td>
      <Table.Td>
        <Group gap={4}>
          <StatusBadge state={s.state} tone={s.state === 'ready' ? 'running' : undefined} size="sm">
            {stateConfig.label}
          </StatusBadge>
          {s.state === 'finished' && !s.artifactsReviewed && s.pendingArtifactsCount > 0 && (
            <StatusBadge tone="warning" size="xs">
              {s.pendingArtifactsCount} pending
            </StatusBadge>
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
            <Tooltip key={m} label={m} multiline maw={420}>
              <Badge size="xs" variant="outline" style={{ textTransform: 'none' }}>
                {shortModelName(m)}
              </Badge>
            </Tooltip>
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
            <a href={sessionUrl} aria-label={`Open session #${s.id}`} onClick={(e) => e.stopPropagation()}>
              <IconExternalLink size={16} />
            </a>
          </Tooltip>
        )}
        {isPrivate && (
          <Tooltip label={`${s.userName ?? 'The owner'} keeps this session private`}>
            <IconLock size={16} aria-label={`Session #${s.id} is private`} color="var(--app-text-tertiary)" />
          </Tooltip>
        )}
      </Table.Td>
    </Table.Tr>
  );
}

setPageLayout(SessionsPage, persistentProjectLayout);

export default SessionsPage;
