import { InfiniteScroll, Link, router } from '@inertiajs/react';
import { Center, Loader, Tooltip } from '@mantine/core';
import { IconExternalLink, IconLock } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useSessionListCableUpdates } from 'shared/lib/hooks/useSessionListCableUpdates';
import { costColor, formatCost, formatDuration, formatTokens } from 'shared/lib/sessionFormat';
import { companySessionPath, userPath } from 'shared/routes';
import { AgentLogo, agentLabel, ModeTag, StatusTag } from 'shared/ui/sessions';

import classes from './SessionFeedTable.module.css';

/** One row of a session-level Sessions & Runs list, as TerminalSessionResource serializes it. */
export interface SessionFeedRow {
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
  userId: number;
  userName: string | null;
  userEmail: string | null;
  projectId: number | null;
  projectName: string | null;
  artifactsReviewed: boolean | null;
  pendingArtifactsCount: number;
  initialPrompt: string | null;
  // False when the owner's profile keeps this phase of their sessions private —
  // the row still reports what it cost, but it cannot be opened.
  viewable: boolean;
}

// Sessions whose show page is worth opening (a live or completed run, not a
// half-provisioned one).
const OPENABLE_STATES = new Set(['queued', 'ready', 'finished', 'failed', 'cancelled', 'finishing']);

const SESSION_TYPE_LABEL: Record<string, string> = {
  agent_session: 'Standalone session',
  workflow_step: 'Workflow step',
};

const MAX_NAME_LENGTH = 80;

/**
 * A session has no title column. The first line of the prompt is what the
 * person asked for and how they recognise the row; a promptless (or redacted)
 * session falls back to the generic label the design shows for that case.
 */
function sessionName(s: SessionFeedRow): string {
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

interface Props {
  /** The page accumulated so far by InfiniteScroll. */
  sessions: SessionFeedRow[];
  /**
   * Changing this string throws away the accumulated rows instead of appending
   * to them — it is what tells a filtered list that the server answered a
   * different question. A list with no filters passes nothing.
   */
  resetKey?: string;
  /** False on a list that is already about one person: the column would repeat. */
  showUser?: boolean;
  emptyLabel?: string;
  /**
   * Where a row opens. Returning null means this viewer has no route to that
   * session — the row still shows what it cost, but it is not a link to a page
   * that would only redirect them back with "not authorized". Defaults to the
   * company session page, which is what the (admin-only) company feed uses.
   */
  sessionHref?: (session: SessionFeedRow) => string | null;
}

/**
 * The session-level Sessions & Runs list: the company-wide feed and one
 * member's slice of it on `/user/:id` are the same table with the same ruler.
 *
 * Live updates are the component's own business — it subscribes to
 * SessionListChannel and patches rows in place, so a state change shows up
 * across every page InfiniteScroll has loaded without a refetch.
 */
export function SessionFeedTable({
  sessions,
  resetKey = '',
  showUser = true,
  emptyLabel = 'No sessions yet',
  sessionHref = (session) => companySessionPath(session.id),
}: Props) {
  // Local map mirrors the InfiniteScroll-accumulated sessions prop. Cable
  // updates patch individual entries in-place without touching the rest, so
  // live state changes are visible across all loaded pages simultaneously.
  const [sessionMap, setSessionMap] = useState<Map<number, SessionFeedRow>>(() => {
    const map = new Map<number, SessionFeedRow>();
    for (const s of sessions) map.set(s.id, s);
    return map;
  });

  const prevResetKeyRef = useRef<string>(resetKey);

  useEffect(() => {
    const changed = resetKey !== prevResetKeyRef.current;
    prevResetKeyRef.current = resetKey;
    setSessionMap((prev) => {
      if (changed) {
        const map = new Map<number, SessionFeedRow>();
        for (const s of sessions) map.set(s.id, s);
        return map;
      }
      const newEntries = sessions.filter((s) => !prev.has(s.id));
      if (newEntries.length === 0) return prev;
      const map = new Map(prev);
      for (const s of newEntries) map.set(s.id, s);
      return map;
    });
  }, [sessions, resetKey]);

  useSessionListCableUpdates({
    onUpdate: useCallback((updated) => {
      setSessionMap((prev) => {
        if (!prev.has(updated.id as number)) return prev;
        const map = new Map(prev);
        map.set(updated.id as number, {
          ...prev.get(updated.id as number)!,
          ...(updated as unknown as SessionFeedRow),
        });
        return map;
      });
    }, []),
  });

  const displaySessions = useMemo(() => [...sessionMap.values()], [sessionMap]);

  if (sessions.length === 0) return <div className={classes.empty}>{emptyLabel}</div>;

  return (
    <InfiniteScroll
      data="sessions"
      loading={() => (
        <Center py="md">
          <Loader size="sm" />
        </Center>
      )}
    >
      <div className={classes.tableWrap}>
        <div
          className={showUser ? classes.table : `${classes.table} ${classes.noUser}`}
          role="table"
          aria-label="Sessions & Runs"
        >
          <div className={classes.thead}>
            <span>Status</span>
            <span>Name</span>
            <span>Agent</span>
            {showUser && <span>User</span>}
            <span>Project</span>
            <span className={classes.right}>Tokens</span>
            <span className={classes.right}>Cost</span>
            <span className={classes.right}>Duration</span>
            <span style={{ paddingLeft: 24 }}>Started</span>
            <span />
          </div>
          {displaySessions.map((s) => (
            <SessionRow key={s.id} session={s} showUser={showUser} href={sessionHref(s)} />
          ))}
        </div>
      </div>
    </InfiniteScroll>
  );
}

function SessionRow({
  session: s,
  showUser,
  href,
}: {
  session: SessionFeedRow;
  showUser: boolean;
  href: string | null;
}) {
  const openable = href !== null && s.viewable && OPENABLE_STATES.has(s.state);
  const isPrivate = !s.viewable;
  const typeLabel = SESSION_TYPE_LABEL[s.sessionType] ?? s.sessionType;
  const showsPending = s.state === 'finished' && !s.artifactsReviewed && s.pendingArtifactsCount > 0;

  return (
    <div
      className={openable ? classes.row : `${classes.row} ${classes.rowStatic}`}
      onClick={openable ? () => router.visit(href!) : undefined}
      tabIndex={openable ? 0 : undefined}
      onKeyDown={
        openable
          ? (e) => {
              if (e.key === 'Enter') router.visit(href!);
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

      {showUser && (
        <Tooltip label={s.userEmail ?? ''} disabled={!s.userEmail}>
          <span className={classes.user}>
            {s.userName ? (
              <Link href={userPath(s.userId)} className={classes.userLink} onClick={(e) => e.stopPropagation()}>
                {s.userName}
              </Link>
            ) : (
              '—'
            )}
          </span>
        </Tooltip>
      )}
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
            href={href!}
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
