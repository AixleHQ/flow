import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import {
  Box,
  Chip,
  FormControl,
  IconButton,
  InputLabel,
  MenuItem,
  Pagination,
  Select,
  Skeleton,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Tooltip,
  Typography,
} from '@mui/material';
import { formatDistanceToNow } from 'date-fns';
import type { FC } from 'react';
import React from 'react';

import type { AgentType, ITerminalSession, TerminalSessionState } from 'entities/terminal-session';
import { useListTerminalSessionsQuery } from 'shared/api';
import { Routes } from 'shared/routes';

export interface SessionHistoryWidgetProps {
  projectId?: number;
  /** Called when user clicks a session row */
  onSessionSelect?: (sessionId: number) => void;
}

const AGENT_LABELS: Record<AgentType, { label: string; color: string }> = {
  claude_code: { label: 'Claude Code', color: '#D97706' },
  cursor_cli: { label: 'Cursor CLI', color: '#7C3AED' },
  codex: { label: 'Codex', color: '#059669' },
  gemini_cli: { label: 'Gemini CLI', color: '#2563EB' },
};

const STATE_CONFIG: Record<
  TerminalSessionState,
  { label: string; color: 'default' | 'success' | 'error' | 'warning' | 'info' }
> = {
  not_started: { label: 'Pending', color: 'default' },
  running: { label: 'Starting', color: 'info' },
  ready: { label: 'Running', color: 'success' },
  finished: { label: 'Finished', color: 'default' },
  failed: { label: 'Failed', color: 'error' },
};

const SESSION_TYPE_LABELS: Record<string, string> = {
  agent_session: 'Standalone',
  workflow_step: 'Workflow step',
  auth_setup: 'Auth setup',
  tool_setup: 'Tool setup',
};

function formatTokens(n: number): string {
  if (n === 0) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function formatCost(cents: number): string {
  if (cents === 0) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatDuration(
  startedAt: string | null,
  finishedAt: string | null,
  state: string,
): string {
  if (!startedAt) return '—';
  const start = new Date(startedAt);
  const end = finishedAt
    ? new Date(finishedAt)
    : state === 'running' || state === 'ready'
      ? new Date()
      : null;
  if (!end) return '—';
  const seconds = Math.round((end.getTime() - start.getTime()) / 1000);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

const AGENT_FILTER_OPTIONS: { value: AgentType; label: string }[] = [
  { value: 'claude_code', label: 'Claude Code' },
  { value: 'cursor_cli', label: 'Cursor CLI' },
  { value: 'codex', label: 'Codex' },
  { value: 'gemini_cli', label: 'Gemini CLI' },
];

const STATE_FILTER_OPTIONS: { value: TerminalSessionState; label: string }[] = [
  { value: 'running', label: 'Starting' },
  { value: 'ready', label: 'Running' },
  { value: 'finished', label: 'Finished' },
  { value: 'failed', label: 'Failed' },
];

const PER_PAGE = 20;

export const SessionHistoryWidget: FC<SessionHistoryWidgetProps> = ({ projectId, onSessionSelect }) => {
  const [page, setPage] = React.useState(1);
  const [agentFilter, setAgentFilter] = React.useState<AgentType | ''>('');
  const [stateFilter, setStateFilter] = React.useState<TerminalSessionState | ''>('');

  const { data, isLoading, isFetching } = useListTerminalSessionsQuery(
    {
      projectId,
      page,
      perPage: PER_PAGE,
      agentType: agentFilter || undefined,
      state: stateFilter || undefined,
    },
    { pollingInterval: 15_000 },
  );

  const sessions = data?.items ?? [];
  const totalPages = data?.meta?.totalPages ?? 1;
  const totalCount = data?.meta?.totalCount ?? 0;

  const handleAgentChange = (value: string) => {
    setAgentFilter(value as AgentType | '');
    setPage(1);
  };

  const handleStateChange = (value: string) => {
    setStateFilter(value as TerminalSessionState | '');
    setPage(1);
  };

  return (
    <Box sx={{ opacity: isFetching ? 0.7 : 1, transition: 'opacity 0.2s' }}>
      {/* Filters */}
      <Stack direction="row" spacing={1.5} sx={{ px: 2, py: 1.5 }} alignItems="center">
        <FormControl size="small" sx={{ minWidth: 140 }}>
          <InputLabel>Agent</InputLabel>
          <Select value={agentFilter} label="Agent" onChange={(e) => handleAgentChange(e.target.value)}>
            <MenuItem value="">All</MenuItem>
            {AGENT_FILTER_OPTIONS.map((o) => (
              <MenuItem key={o.value} value={o.value}>
                {o.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 130 }}>
          <InputLabel>Status</InputLabel>
          <Select value={stateFilter} label="Status" onChange={(e) => handleStateChange(e.target.value)}>
            <MenuItem value="">All</MenuItem>
            {STATE_FILTER_OPTIONS.map((o) => (
              <MenuItem key={o.value} value={o.value}>
                {o.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <Typography variant="caption" color="text.secondary" sx={{ ml: 'auto !important' }}>
          {totalCount} session{totalCount !== 1 ? 's' : ''}
        </Typography>
      </Stack>

      {isLoading ? (
        <Box sx={{ p: 2 }}>
          {[...Array(5)].map((_, i) => (
            <Skeleton key={i} height={52} sx={{ mb: 0.5 }} />
          ))}
        </Box>
      ) : sessions.length === 0 ? (
        <Box sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">
            {agentFilter || stateFilter ? 'No sessions match filters' : 'No sessions yet'}
          </Typography>
        </Box>
      ) : (
        <>
          <TableContainer>
            <Table size="small">
              <TableHead>
                <TableRow
                  sx={{
                    '& th': { fontWeight: 600, fontSize: 12, color: 'text.secondary', py: 1, whiteSpace: 'nowrap' },
                  }}
                >
                  <TableCell>ID</TableCell>
                  <TableCell>Agent</TableCell>
                  <TableCell>Type</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>User</TableCell>
                  {!projectId && <TableCell>Project</TableCell>}
                  <TableCell align="right">Tokens</TableCell>
                  <TableCell align="right">Cost</TableCell>
                  <TableCell>Models</TableCell>
                  <TableCell>Duration</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell />
                </TableRow>
              </TableHead>
              <TableBody>
                {sessions.map((s) => (
                  <SessionRow key={s.id} session={s} showProject={!projectId} onSelect={onSessionSelect} />
                ))}
              </TableBody>
            </Table>
          </TableContainer>

          {totalPages > 1 && (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 2 }}>
              <Pagination count={totalPages} page={page} onChange={(_, p) => setPage(p)} size="small" />
            </Box>
          )}
        </>
      )}
    </Box>
  );
};

// Need React import for useState

interface SessionRowProps {
  session: ITerminalSession;
  showProject: boolean;
  onSelect?: (id: number) => void;
}

const SessionRow: FC<SessionRowProps> = ({ session: s, showProject, onSelect }) => {
  const agent = AGENT_LABELS[s.agentType] ?? { label: s.agentType, color: '#666' };
  const stateConfig = STATE_CONFIG[s.state] ?? { label: s.state, color: 'default' as const };
  const typeLabel = SESSION_TYPE_LABELS[s.sessionType] ?? s.sessionType;

  const tokenBreakdown = [
    s.inputTokens > 0 && `in: ${formatTokens(s.inputTokens)}`,
    s.outputTokens > 0 && `out: ${formatTokens(s.outputTokens)}`,
    s.cacheReadTokens > 0 && `cache_r: ${formatTokens(s.cacheReadTokens)}`,
    s.cacheWriteTokens > 0 && `cache_w: ${formatTokens(s.cacheWriteTokens)}`,
  ]
    .filter(Boolean)
    .join(', ');

  return (
    <TableRow
      hover
      sx={{ cursor: onSelect ? 'pointer' : 'default', '& td': { py: 1, fontSize: 13 } }}
      onClick={() => onSelect?.(s.id)}
    >
      <TableCell>
        <Typography variant="body2" sx={{ fontFamily: 'monospace', fontSize: 12, color: 'text.secondary' }}>
          #{s.id}
        </Typography>
      </TableCell>
      <TableCell>
        <Chip
          label={agent.label}
          size="small"
          sx={{ bgcolor: agent.color, color: '#fff', fontWeight: 500, fontSize: 11, height: 22 }}
        />
      </TableCell>
      <TableCell>
        <Typography variant="body2" sx={{ fontSize: 12, color: 'text.secondary' }}>
          {typeLabel}
        </Typography>
      </TableCell>
      <TableCell>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          <Chip
            label={stateConfig.label}
            color={stateConfig.color}
            size="small"
            variant="outlined"
            sx={{ fontSize: 11, height: 22 }}
          />
          {s.state === 'finished' && !s.artifactsReviewed && (s.pendingArtifactsCount ?? 0) > 0 && (
            <Chip
              label={`${s.pendingArtifactsCount} pending`}
              color="warning"
              size="small"
              sx={{ fontSize: 10, height: 20 }}
            />
          )}
        </Box>
      </TableCell>
      <TableCell>
        <Tooltip title={s.userEmail ?? ''} arrow>
          <Typography variant="body2" noWrap sx={{ maxWidth: 120, fontSize: 13 }}>
            {s.userName ?? '—'}
          </Typography>
        </Tooltip>
      </TableCell>
      {showProject && (
        <TableCell>
          <Typography variant="body2" noWrap sx={{ maxWidth: 120, fontSize: 13, color: 'text.secondary' }}>
            {s.projectName ?? '—'}
          </Typography>
        </TableCell>
      )}
      <TableCell align="right">
        <Tooltip title={tokenBreakdown || 'No token data'} arrow>
          <Typography variant="body2" sx={{ fontFamily: 'monospace', fontSize: 12 }}>
            {formatTokens(s.totalTokens)}
          </Typography>
        </Tooltip>
      </TableCell>
      <TableCell align="right">
        <Typography
          variant="body2"
          sx={{ fontFamily: 'monospace', fontSize: 12, fontWeight: s.costCents > 0 ? 600 : 400 }}
        >
          {formatCost(s.costCents)}
        </Typography>
      </TableCell>
      <TableCell>
        <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap' }}>
          {(s.models ?? []).map((m) => (
            <Chip key={m} label={m} size="small" variant="outlined" sx={{ fontSize: 10, height: 20 }} />
          ))}
        </Box>
      </TableCell>
      <TableCell>
        <Typography variant="body2" sx={{ fontSize: 12, fontFamily: 'monospace', color: 'text.secondary' }}>
          {formatDuration(s.startedAt, s.finishedAt, s.state)}
        </Typography>
      </TableCell>
      <TableCell>
        <Tooltip title={s.startedAt ? new Date(s.startedAt).toLocaleString() : s.createdAt} arrow>
          <Typography variant="body2" sx={{ fontSize: 12, color: 'text.secondary', whiteSpace: 'nowrap' }}>
            {formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}
          </Typography>
        </Tooltip>
      </TableCell>
      <TableCell>
        {s.state === 'ready' && (
          <Tooltip title="Open session" arrow>
            <IconButton
              size="small"
              onClick={(e) => {
                e.stopPropagation();
                window.open(Routes.frontend.companySessionPath(String(s.id)), '_blank');
              }}
            >
              <OpenInNewIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        )}
      </TableCell>
    </TableRow>
  );
};
