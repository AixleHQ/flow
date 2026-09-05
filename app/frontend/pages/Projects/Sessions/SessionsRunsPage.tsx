import { Head, InfiniteScroll, Link, router } from '@inertiajs/react';
import { Button, Center, Loader, Select, TextInput, Tooltip } from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import {
  IconChevronRight,
  IconExternalLink,
  IconLock,
  IconPlayerPlay,
  IconPlus,
  IconSearch,
} from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type RunListEntry from 'types/generated/RunListEntry';
import type SessionListEntry from 'types/generated/SessionListEntry';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { useSessionListCableUpdates } from 'shared/lib/hooks/useSessionListCableUpdates';
import { useWorkflowRunListCableUpdates } from 'shared/lib/hooks/useWorkflowRunListCableUpdates';
import { costColor, formatCost, formatDuration, formatTokens } from 'shared/lib/sessionFormat';
import { AgentLogo, agentLabel, ModeTag, StatusTag } from 'shared/ui/sessions';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import { NewSessionDrawer } from './NewSessionDrawer';
import { RunWorkflowDrawer } from './RunWorkflowDrawer';
import classes from './SessionsRunsPage.module.css';

/**
 * One row of the feed. A run carries its step sessions; a session carries the
 * privacy flag that decides whether the row can be opened at all.
 */
export type ListEntry = (SessionListEntry | RunListEntry) & {
  sessionType?: string;
  finishedAt?: string | null;
  viewable?: boolean;
  completedAt?: string | null;
  stepsCompleted?: number;
  stepsTotal?: number;
  sessions?: SessionListEntry[];
};

type ListType = 'all' | 'run' | 'solo';

interface Filters {
  type: ListType;
  search?: string;
  agentType?: string;
  status?: string;
  userId?: string;
}

export interface SessionsRunsPageProps {
  project: { id: number; name: string };
  entries: ListEntry[];
  filters: Filters;
  total: number;
  userOptions: { id: number; name: string }[];
}

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
  { value: 'grok', label: 'Grok' },
];

// One vocabulary over two state machines — see SessionsRunsFeed::STATUS_FILTERS.
const STATUS_OPTIONS = [
  { value: 'running', label: 'Running' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'pending', label: 'Pending' },
];

// A run's session is never opened straight from the list while it is still
// being provisioned — there is nothing to show yet.
const OPENABLE_SESSION_STATES = new Set(['queued', 'cancelled', 'ready', 'finished', 'failed', 'finishing']);

function entryKey(entry: ListEntry): string {
  return `${entry.kind}-${entry.id}`;
}

function stateLabel(entry: ListEntry): string {
  if (entry.kind === 'run') {
    return { completed: 'Completed', running: 'Running', failed: 'Failed', cancelled: 'Cancelled' }[entry.state] ?? '';
  }
  return (
    {
      queued: 'Queued',
      cancelled: 'Cancelled',
      ready: 'Running',
      running: 'Starting',
      finished: 'Finished',
      failed: 'Failed',
      not_started: 'Pending',
    }[entry.state] ?? ''
  );
}

const SessionsRunsPage = ({ project, entries, filters, total, userOptions }: SessionsRunsPageProps) => {
  const { canExecute } = useProjectPermissions();
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const [newSessionOpen, setNewSessionOpen] = useState(false);
  const [runWorkflowOpen, setRunWorkflowOpen] = useState(false);
  const [searchValue, setSearchValue] = useState(filters.search ?? '');

  const [entryMap, setEntryMap] = useState<Map<string, ListEntry>>(() => {
    const map = new Map<string, ListEntry>();
    for (const e of entries) map.set(entryKey(e), e);
    return map;
  });

  const prevFiltersRef = useRef<string>('');

  // Sync new InfiniteScroll pages into the map. On filter change, reset the
  // map to the new first page — stale entries from the old filter must not
  // survive a narrowed result set.
  useEffect(() => {
    const filtersKey = JSON.stringify(filters);
    const filtersChanged = filtersKey !== prevFiltersRef.current;
    prevFiltersRef.current = filtersKey;

    setEntryMap((prev) => {
      if (filtersChanged) {
        const map = new Map<string, ListEntry>();
        for (const e of entries) map.set(entryKey(e), e);
        return map;
      }
      const newEntries = entries.filter((e) => !prev.has(entryKey(e)));
      if (newEntries.length === 0) return prev;
      const map = new Map(prev);
      for (const e of newEntries) map.set(entryKey(e), e);
      return map;
    });
  }, [entries, filters]);

  const onSessionUpdate = useCallback((session: Record<string, unknown>) => {
    setEntryMap((prev) => {
      const key = `session-${session.id}`;
      let map = prev;

      if (prev.has(key)) {
        map = new Map(prev).set(key, { ...prev.get(key)!, ...(session as unknown as ListEntry) });
      }

      // A step session lives nested under its run's `sessions` array, not as
      // its own top-level entry — patch it there too, or an expanded run's
      // child rows never see live updates.
      for (const [runKey, entry] of map) {
        if (entry.kind !== 'run' || !entry.sessions) continue;
        const index = entry.sessions.findIndex((s) => s.id === session.id);
        if (index === -1) continue;

        if (map === prev) map = new Map(prev);
        const sessions = [...entry.sessions];
        sessions[index] = { ...sessions[index], ...(session as unknown as SessionListEntry) };
        map.set(runKey, { ...entry, sessions });
      }

      return map;
    });
  }, []);

  const onRunUpdate = useCallback((run: Record<string, unknown>) => {
    setEntryMap((prev) => {
      const key = `run-${run.id}`;
      const existing = prev.get(key);
      if (!existing) return prev;
      return new Map(prev).set(key, { ...existing, ...(run as unknown as ListEntry) });
    });
  }, []);

  useSessionListCableUpdates({ projectId: project.id, onUpdate: onSessionUpdate });
  useWorkflowRunListCableUpdates({ projectId: project.id, onUpdate: onRunUpdate });

  const orderedEntries = useMemo(() => Array.from(entryMap.values()), [entryMap]);

  const listUrl = `/company/projects/${project.id}/sessions`;

  const navigate = useCallback(
    (next: Partial<Filters>) => {
      const merged: Record<string, string> = {};
      const combined = { ...filters, ...next };
      for (const [key, value] of Object.entries(combined)) {
        if (value) merged[key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`)] = String(value);
      }
      router.get(listUrl, merged, { preserveState: true, preserveScroll: true });
    },
    [filters, listUrl],
  );

  const debouncedSearch = useDebouncedCallback((value: string) => navigate({ search: value }), 350);

  const toggleExpanded = useCallback((id: number) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const hasFilters = !!(filters.search || filters.agentType || filters.status || filters.userId);

  // "All" offers both create actions; each filtered tab offers only its own.
  const showRunWorkflow = canExecute && filters.type !== 'solo';
  const showNewSession = canExecute && filters.type !== 'run';

  const userSelectData = useMemo(() => userOptions.map((u) => ({ value: String(u.id), label: u.name })), [userOptions]);

  return (
    <>
      <Head title={`Sessions & Runs — ${project.name}`} />

      <header className={classes.head}>
        <div>
          <h1 className={classes.title}>Sessions &amp; Runs</h1>
          <p className={classes.subtitle}>Every agent session and workflow run in this project, in one place.</p>
        </div>
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
          <div className={classes.actions}>
            {showRunWorkflow && (
              <Button
                variant="light"
                leftSection={<IconPlayerPlay size={14} />}
                onClick={() => setRunWorkflowOpen(true)}
              >
                Run workflow
              </Button>
            )}
            {showNewSession && (
              <Button leftSection={<IconPlus size={14} />} onClick={() => setNewSessionOpen(true)}>
                New Session
              </Button>
            )}
          </div>
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
          w={140}
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
          w={160}
        />
      </div>

      {entries.length === 0 ? (
        <div className={classes.empty}>
          {hasFilters ? 'No sessions match these filters.' : 'Nothing has run in this project yet.'}
        </div>
      ) : (
        <InfiniteScroll
          data="entries"
          loading={() => (
            <Center py="md">
              <Loader size="sm" />
            </Center>
          )}
        >
          <div className={classes.tableWrap}>
            <div className={classes.table}>
              <div className={classes.thead}>
                <span />
                <span>Status</span>
                <span>Name</span>
                <span>Agent</span>
                <span>User</span>
                <span className={classes.right}>Tokens</span>
                <span className={classes.right}>Cost</span>
                <span className={classes.right}>Duration</span>
                <span style={{ paddingLeft: 24 }}>Started</span>
                <span />
              </div>
              {orderedEntries.map((entry) => (
                <EntryRow
                  key={`${entry.kind}-${entry.id}`}
                  entry={entry}
                  projectId={project.id}
                  expanded={expanded.has(entry.id)}
                  onToggle={toggleExpanded}
                />
              ))}
            </div>
          </div>
        </InfiniteScroll>
      )}

      <NewSessionDrawer projectId={project.id} opened={newSessionOpen} onClose={() => setNewSessionOpen(false)} />
      <RunWorkflowDrawer projectId={project.id} opened={runWorkflowOpen} onClose={() => setRunWorkflowOpen(false)} />
    </>
  );
};

function EntryRow({
  entry,
  projectId,
  expanded,
  onToggle,
}: {
  entry: ListEntry;
  projectId: number;
  expanded: boolean;
  onToggle: (id: number) => void;
}) {
  const isRun = entry.kind === 'run';
  const href = isRun
    ? `/company/projects/${projectId}/workflow_runs/${entry.id}`
    : `/company/projects/${projectId}/sessions/${entry.id}`;
  const openable = isRun || (entry.viewable !== false && OPENABLE_SESSION_STATES.has(entry.state));
  const childSessions = entry.sessions ?? [];
  const finishedAt = isRun ? entry.completedAt : entry.finishedAt;

  return (
    <>
      <div
        className={openable ? classes.row : `${classes.row} ${classes.rowStatic}`}
        onClick={openable ? () => router.visit(href) : undefined}
        role={openable ? 'link' : undefined}
        tabIndex={openable ? 0 : undefined}
        onKeyDown={
          openable
            ? (e) => {
                if (e.key === 'Enter') router.visit(href);
              }
            : undefined
        }
      >
        {isRun && childSessions.length > 0 ? (
          <button
            type="button"
            className={expanded ? `${classes.caret} ${classes.caretOpen}` : classes.caret}
            aria-expanded={expanded}
            aria-label={expanded ? `Collapse ${entry.name}` : `Expand ${entry.name}`}
            onClick={(e) => {
              e.stopPropagation();
              onToggle(entry.id);
            }}
          >
            <IconChevronRight size={15} />
          </button>
        ) : (
          <span />
        )}

        <StatusTag state={entry.state}>{stateLabel(entry) || undefined}</StatusTag>

        <div className={classes.name}>
          <div className={classes.nameTitle}>{entry.name}</div>
          <div className={classes.nameSub}>
            #{entry.id}
            <span className={classes.nameSubSep}>·</span>
            {isRun ? 'Run' : 'Standalone session'}
            {isRun && (
              <>
                <span className={classes.nameSubSep}>·</span>
                {entry.stepsCompleted}/{entry.stepsTotal} steps
              </>
            )}
          </div>
        </div>

        <div className={classes.agent}>
          <AgentLogo agentType={entry.agentType} size={18} />
          <span className={classes.agentLabel}>{agentLabel(entry.agentType)}</span>
          <ModeTag mode={entry.mode} />
        </div>

        <span className={classes.user}>{entry.userName ?? '—'}</span>
        <span className={`${classes.num} ${classes.right}`}>{formatTokens(entry.totalTokens)}</span>
        <span className={`${classes.num} ${classes.right}`} style={{ color: costColor(entry.costCents) }}>
          {formatCost(entry.costCents)}
        </span>
        <span className={`${classes.num} ${classes.right}`}>
          {formatDuration(entry.startedAt, finishedAt, entry.state)}
        </span>
        <span className={classes.ago}>
          {formatDistanceToNow(new Date(entry.startedAt ?? entry.createdAt), { addSuffix: true })}
        </span>

        {openable ? (
          <Tooltip label={isRun ? 'Open run' : 'Open session'}>
            <Link
              href={href}
              className={classes.link}
              aria-label={`Open ${isRun ? 'run' : 'session'} #${entry.id}`}
              onClick={(e) => e.stopPropagation()}
            >
              <IconExternalLink size={15} />
            </Link>
          </Tooltip>
        ) : (
          <Tooltip label={`${entry.userName ?? 'The owner'} keeps this session private`}>
            <span className={classes.link}>
              <IconLock size={15} aria-label={`Session #${entry.id} is private`} />
            </span>
          </Tooltip>
        )}
      </div>

      {isRun && expanded && childSessions.length > 0 && (
        <div className={classes.subRows}>
          {childSessions.map((child) => {
            const childHref = `/company/projects/${projectId}/sessions/${child.id}`;
            const childOpenable = OPENABLE_SESSION_STATES.has(child.state);
            return (
              <div
                key={child.id}
                className={classes.subRow}
                onClick={childOpenable ? () => router.visit(childHref) : undefined}
              >
                <span />
                <StatusTag state={child.state}>{stateLabel(child) || undefined}</StatusTag>
                <div className={classes.name}>
                  <div className={classes.nameTitle}>{child.name}</div>
                </div>
                <div className={classes.agent}>
                  <AgentLogo agentType={child.agentType} size={16} />
                  <span className={classes.agentLabel}>{agentLabel(child.agentType)}</span>
                </div>
                <span />
                <span className={`${classes.num} ${classes.right} ${classes.dim}`}>
                  {formatTokens(child.totalTokens)}
                </span>
                <span className={`${classes.num} ${classes.right} ${classes.dim}`}>{formatCost(child.costCents)}</span>
                <span className={`${classes.num} ${classes.right} ${classes.dim}`}>
                  {formatDuration(child.startedAt, child.finishedAt, child.state)}
                </span>
                <span />
                {childOpenable ? (
                  <Link
                    href={childHref}
                    className={classes.link}
                    aria-label={`Open session #${child.id}`}
                    onClick={(e) => e.stopPropagation()}
                  >
                    <IconExternalLink size={15} />
                  </Link>
                ) : (
                  <span />
                )}
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}

setPageLayout(SessionsRunsPage, persistentProjectLayout);

export default SessionsRunsPage;
