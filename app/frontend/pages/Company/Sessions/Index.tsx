import { Head, router } from '@inertiajs/react';
import { Select, TextInput } from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconSearch } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { SessionFeedTable, type SessionFeedRow } from 'shared/resources/sessions/SessionFeedTable';
import { AGENT_SELECT_OPTIONS } from 'shared/ui/agentRuntimes';
import {
  DateRangeFilter,
  formatListSort,
  isDefaultListSort,
  type ListSort,
  parseListSort,
} from 'shared/ui/list-controls';

import classes from './Index.module.css';

type ListType = 'all' | 'run' | 'solo';

interface Filters {
  type: ListType;
  search?: string;
  agentType?: string;
  status?: string;
  userId?: string;
  projectId?: string;
}

/** The ransack `q` the list honours: a date range and a sort. */
interface ListQuery {
  s?: string;
  createdFrom?: string;
  createdUntil?: string;
}

type Props = {
  sessions: SessionFeedRow[];
  filters: Filters;
  query?: ListQuery;
  total: number;
  userOptions: { id: number; name: string }[];
  projectOptions?: { id: number; name: string }[];
  cableStream?: string;
};

const NO_QUERY: ListQuery = {};
const NO_OPTIONS: { id: number; name: string }[] = [];

/** Router params for the list's `q`; the default sort stays out of the URL. */
function listQueryParams({ s, createdFrom, createdUntil }: ListQuery): Record<string, string> | null {
  const q: Record<string, string> = {};
  if (createdFrom) q.created_from = createdFrom;
  if (createdUntil) q.created_until = createdUntil;
  if (s && !isDefaultListSort(parseListSort(s))) q.s = s;
  return Object.keys(q).length > 0 ? q : null;
}

const TYPE_TABS: { value: ListType; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'run', label: 'Workflow runs' },
  { value: 'solo', label: 'Standalone' },
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

const SESSIONS_URL = '/company/sessions';

const SessionsIndex = ({
  sessions,
  filters,
  query = NO_QUERY,
  total,
  userOptions,
  projectOptions = NO_OPTIONS,
  cableStream,
}: Props) => {
  const [searchValue, setSearchValue] = useState(filters.search ?? '');
  const sort = parseListSort(query.s);

  const navigate = useCallback(
    (next: Partial<Filters>, nextQuery: Partial<ListQuery> = {}) => {
      const combined = { ...filters, ...next };
      const merged: Record<string, string | Record<string, string>> = {};
      for (const [key, value] of Object.entries(combined)) {
        if (value && !(key === 'type' && value === 'all')) {
          merged[key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`)] = String(value);
        }
      }
      const q = listQueryParams({ ...query, ...nextQuery });
      if (q) merged.q = q;
      router.get(SESSIONS_URL, merged, { preserveState: true, preserveScroll: true });
    },
    [filters, query],
  );

  const onSort = useCallback((next: ListSort) => navigate({}, { s: formatListSort(next) }), [navigate]);

  const debouncedSearch = useDebouncedCallback((value: string) => navigate({ search: value || undefined }), 350);

  const userSelectData = useMemo(() => userOptions.map((u) => ({ value: String(u.id), label: u.name })), [userOptions]);
  const projectSelectData = useMemo(
    () => projectOptions.map((p) => ({ value: String(p.id), label: p.name })),
    [projectOptions],
  );

  const hasFilters = !!(
    filters.search ||
    filters.agentType ||
    filters.status ||
    filters.userId ||
    filters.projectId ||
    query.createdFrom
  );

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
          data={AGENT_SELECT_OPTIONS}
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
        <Select
          placeholder="Project"
          aria-label="Filter by project"
          data={projectSelectData}
          value={filters.projectId ?? null}
          onChange={(v) => navigate({ projectId: v ?? undefined })}
          clearable
          searchable
          w={170}
        />
        <DateRangeFilter
          from={query.createdFrom}
          until={query.createdUntil}
          onChange={(createdFrom, createdUntil) => navigate({}, { createdFrom, createdUntil })}
        />
      </div>

      <SessionFeedTable
        sessions={sessions}
        cableStream={cableStream}
        sort={sort}
        onSort={onSort}
        resetKey={JSON.stringify([filters, query])}
        emptyLabel={hasFilters ? 'No sessions match these filters.' : 'No sessions yet'}
      />
    </AuthLayout>
  );
};

export default SessionsIndex;
