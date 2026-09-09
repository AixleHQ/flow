import { Head, InfiniteScroll, Link, router } from '@inertiajs/react';
import { Center, Loader, Select, TextInput, Tooltip } from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconExternalLink, IconLock, IconSearch } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { useSessionListCableUpdates } from 'shared/lib/hooks/useSessionListCableUpdates';
import { costColor, formatCost, formatDuration, formatTokens } from 'shared/lib/sessionFormat';
import { companySessionPath } from 'shared/routes';
import { AgentLogo, agentLabel, ModeTag, StatusTag } from 'shared/ui/sessions';

import classes from './Index.module.css';

// Sessions whose show page is worth opening (a live or completed run, not a
// half-provisioned one). Mirrors the project Sessions & Runs list.
const OPENABLE_STATES = new Set(['queued', 'ready', 'finished', 'failed', 'cancelled', 'finishing']);

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
  costCents: number;
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

type ListType = 'all' | 'run' | 'solo';

interface Filters {
  type: ListType;
  search?: string;
  agentType?: string;
  status?: string;
  userId?: string;
}

type Props = {
  sessions: Session[];
  filters: Filters;
  total: number;
  userOptions: { id: number; name: string }[];
};

const TYPE_TABS: { value: ListType; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'run', label: 'Workflow runs' },
  { value: 'solo', label: 'Standalone' },
];

const AGENT_OPTIONS = [
  { value: 'claude_code', label: 'Claude Code' },
  { value: 'cursor_cli', label: 'Cursor CLI' },
  { value: 'codex', label: 'Codex' },
  { value: 'gemini_cli', label: 'Gemini CLI' },
  { value: 'antigravity_cli', label: 'Antigravity CLI' },
  { value: 'grok', label: 'Grok' },
];

// The shared status vocabulary — the four values the project feed exposes as
// filters. Internal states (Starting / Finishing / Queued) map onto these
// server-side; they are not offered as filter values.
const STATUS_OPTIONS = [
  { value: 'running', label: 'Running' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'pending', label: 'Pending' },
];

const SESSION_TYPE_LABEL: Record<string, string> = {
  agent_session: 'Standalone session',
  workflow_step: 'Workflow step',
};

const SESSIONS_URL = '/company/sessions';

const MAX_NAME_LENGTH = 80;

/**
 * A session has no title column. The first line of the prompt is what the
 * person asked for and how they recognise the row; a promptless (or redacted)
 * session falls back to the generic label the design shows for that case.
 */
function sessionName(s: Session): string {
  const firstLine = (s.initialPrompt ?? '').trim().split('\n')[0]?.trim() ?? '';
  if (!firstLine) return 'Interactive session';
  return firstLine.length > MAX_NAME_LENGTH ? `${firstLine.slice(0, MAX_NAME_LENGTH - 1)}…` : firstLine;
}

function stateLabel(state: string): string {
  return (
    {
      queued: 'Queued',
      cancelled: 'Cancelled',
      ready: 'Running',
      running: 'Starting',
      finishing: 'Finishing',
      finished: 'Finished',
      failed: 'Failed',
      not_started: 'Pending',
    }[state] ?? state
  );
}

const SessionsIndex = ({ sessions, filters, total, userOptions }: Props) => {
  const [searchValue, setSearchValue] = useState(filters.search ?? '');

  // Local map mirrors the InfiniteScroll-accumulated sessions prop. Cable
  // updates patch individual entries in-place without touching the rest, so
  // live state changes are visible across all loaded pages simultaneously.
  const [sessionMap, setSessionMap] = useState<Map<number, Session>>(() => {
    const map = new Map<number, Session>();
    for (const s of sessions) map.set(s.id, s);
    return map;
  });

  const prevFiltersRef = useRef<string>('');

  // Accumulate pages loaded by InfiniteScroll; reset the map when filters change.
  useEffect(() => {
    const filtersKey = JSON.stringify(filters);
    const filtersChanged = filtersKey !== prevFiltersRef.current;
    prevFiltersRef.current = filtersKey;
    setSessionMap((prev) => {
      if (filtersChanged) {
        const map = new Map<number, Session>();
        for (const s of sessions) map.set(s.id, s);
        return map;
      }
      const newEntries = sessions.filter((s) => !prev.has(s.id));
      if (newEntries.length === 0) return prev;
      const map = new Map(prev);
      for (const s of newEntries) map.set(s.id, s);
      return map;
    });
  }, [sessions, filters]);

  useSessionListCableUpdates({
    onUpdate: useCallback((updated) => {
      setSessionMap((prev) => {
        if (!prev.has(updated.id as number)) return prev;
        const map = new Map(prev);
        map.set(updated.id as number, { ...prev.get(updated.id as number)!, ...(updated as unknown as Session) });
        return map;
      });
    }, []),
  });

  const displaySessions = useMemo(() => [...sessionMap.values()], [sessionMap]);

  const navigate = useCallback(
    (next: Partial<Filters>) => {
      const combined = { ...filters, ...next };
      const merged: Record<string, string> = {};
      for (const [key, value] of Object.entries(combined)) {
        if (value && !(key === 'type' && value === 'all')) {
          merged[key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`)] = String(value);
        }
      }
      router.get(SESSIONS_URL, merged, { preserveState: true, preserveScroll: true });
    },
    [filters],
  );

  const debouncedSearch = useDebouncedCallback((value: string) => navigate({ search: value || undefined }), 350);

  const userSelectData = useMemo(() => userOptions.map((u) => ({ value: String(u.id), label: u.name })), [userOptions]);

  const hasFilters = !!(filters.search || filters.agentType || filters.status || filters.userId);

  return (
    <AuthLayout>
      <Head title="Sessions & Runs" />

      <header className={classes.head}>
        <h1 className={classes.title}>Sessions &amp; Runs</h1>
        <p className={classes.subtitle}>Every agent session and workflow run across the company, in one place.</p>
      </header>

      <div className={classes.typebar}>
        <div className={classes.seg} role="tablist" aria-label="Filter by type">
          {TYPE_TABS.map((tab) => (
            <button
              key={tab.value}
              type="button"
              role="tab"
              aria-selected={filters.type === tab.value}
              className={filters.type === tab.value ? `${classes.segButton} ${classes.segButtonOn}` : classes.segButton}
              onClick={() => navigate({ type: tab.value })}
            >
              {tab.label}
            </button>
          ))}
        </div>
        <div className={classes.typebarRight}>
          <span className={classes.count}>
            {total} {total === 1 ? 'entry' : 'entries'}
          </span>
        </div>
      </div>

      <div className={classes.filters}>
        <TextInput
          placeholder="Search by name…"
          aria-label="Search by name"
          leftSection={<IconSearch size={14} />}
          value={searchValue}
          w={220}
          onChange={(e) => {
            setSearchValue(e.currentTarget.value);
            debouncedSearch(e.currentTarget.value);
          }}
        />
        <Select
          placeholder="Agent"
          aria-label="Filter by agent"
          data={AGENT_OPTIONS}
          value={filters.agentType ?? null}
          onChange={(v) => navigate({ agentType: v ?? undefined })}
          clearable
          w={150}
        />
        <Select
          placeholder="Status"
          aria-label="Filter by status"
          data={STATUS_OPTIONS}
          value={filters.status ?? null}
          onChange={(v) => navigate({ status: v ?? undefined })}
          clearable
          w={140}
        />
        <Select
          placeholder="User"
          aria-label="Filter by user"
          data={userSelectData}
          value={filters.userId ?? null}
          onChange={(v) => navigate({ userId: v ?? undefined })}
          clearable
          searchable
          w={170}
        />
      </div>

      {sessions.length === 0 ? (
        <div className={classes.empty}>{hasFilters ? 'No sessions match these filters.' : 'No sessions yet'}</div>
      ) : (
        <InfiniteScroll
          data="sessions"
          loading={() => (
            <Center py="md">
              <Loader size="sm" />
            </Center>
          )}
        >
          <div className={classes.tableWrap}>
            <div className={classes.table} role="table" aria-label="Sessions & Runs">
              <div className={classes.thead}>
                <span>Status</span>
                <span>Name</span>
                <span>Agent</span>
                <span>User</span>
                <span>Project</span>
                <span className={classes.right}>Tokens</span>
                <span className={classes.right}>Cost</span>
                <span className={classes.right}>Duration</span>
                <span style={{ paddingLeft: 24 }}>Started</span>
                <span />
              </div>
              {displaySessions.map((s) => (
                <SessionRow key={s.id} session={s} />
              ))}
            </div>
          </div>
        </InfiniteScroll>
      )}
    </AuthLayout>
  );
};

function SessionRow({ session: s }: { session: Session }) {
  const openable = s.viewable && OPENABLE_STATES.has(s.state);
  const isPrivate = !s.viewable;
  const href = companySessionPath(s.id);
  const typeLabel = SESSION_TYPE_LABEL[s.sessionType] ?? s.sessionType;
  const showsPending = s.state === 'finished' && !s.artifactsReviewed && s.pendingArtifactsCount > 0;

  return (
    <div
      className={openable ? classes.row : `${classes.row} ${classes.rowStatic}`}
      onClick={openable ? () => router.visit(href) : undefined}
      tabIndex={openable ? 0 : undefined}
      onKeyDown={
        openable
          ? (e) => {
              if (e.key === 'Enter') router.visit(href);
            }
          : undefined
      }
    >
      <span className={classes.status}>
        <StatusTag state={s.state}>{stateLabel(s.state)}</StatusTag>
        {showsPending && <span className={classes.pending}>{s.pendingArtifactsCount} pending</span>}
      </span>

      <div className={classes.name}>
        <div className={classes.nameTitle}>{sessionName(s)}</div>
        <div className={classes.nameSub}>
          #{s.id}
          <span className={classes.nameSubSep}>·</span>
          {typeLabel}
        </div>
      </div>

      <div className={classes.agent}>
        <AgentLogo agentType={s.agentType} size={18} />
        <span className={classes.agentLabel}>{agentLabel(s.agentType)}</span>
        <ModeTag mode={s.mode} />
      </div>

      <Tooltip label={s.userEmail ?? ''} disabled={!s.userEmail}>
        <span className={classes.user}>{s.userName ?? '—'}</span>
      </Tooltip>
      <span className={classes.project}>{s.projectName ?? '—'}</span>

      <span className={`${classes.num} ${classes.right}`}>{formatTokens(s.totalTokens)}</span>
      <span className={`${classes.num} ${classes.right}`} style={{ color: costColor(s.costCents) }}>
        {formatCost(s.costCents)}
      </span>
      <span className={`${classes.num} ${classes.right}`}>{formatDuration(s.startedAt, s.finishedAt, s.state)}</span>
      <span className={classes.ago}>
        <Tooltip label={s.startedAt ? new Date(s.startedAt).toLocaleString() : new Date(s.createdAt).toLocaleString()}>
          <span>{formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}</span>
        </Tooltip>
      </span>

      {openable ? (
        <Tooltip label="Open session">
          <Link
            href={href}
            className={classes.link}
            aria-label={`Open session #${s.id}`}
            onClick={(e) => e.stopPropagation()}
          >
            <IconExternalLink size={15} />
          </Link>
        </Tooltip>
      ) : isPrivate ? (
        <Tooltip label={`${s.userName ?? 'The owner'} keeps this session private`}>
          <span className={classes.link}>
            <IconLock size={15} aria-label={`Session #${s.id} is private`} />
          </span>
        </Tooltip>
      ) : (
        <span />
      )}
    </div>
  );
}

export default SessionsIndex;
