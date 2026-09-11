import { Head, router } from '@inertiajs/react';
import { Select, TextInput } from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconSearch } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { SessionFeedTable, type SessionFeedRow } from 'shared/resources/sessions/SessionFeedTable';

import classes from './Index.module.css';

type ListType = 'all' | 'run' | 'solo';

interface Filters {
  type: ListType;
  search?: string;
  agentType?: string;
  status?: string;
  userId?: string;
}

type Props = {
  sessions: SessionFeedRow[];
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

const SESSIONS_URL = '/company/sessions';

const SessionsIndex = ({ sessions, filters, total, userOptions }: Props) => {
  const [searchValue, setSearchValue] = useState(filters.search ?? '');

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

      <SessionFeedTable
        sessions={sessions}
        resetKey={JSON.stringify(filters)}
        emptyLabel={hasFilters ? 'No sessions match these filters.' : 'No sessions yet'}
      />
    </AuthLayout>
  );
};

export default SessionsIndex;
