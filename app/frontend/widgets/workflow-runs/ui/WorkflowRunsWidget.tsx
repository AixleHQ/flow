import AccessTimeIcon from '@mui/icons-material/AccessTime';
import CancelIcon from '@mui/icons-material/Cancel';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import PauseCircleFilledIcon from '@mui/icons-material/PauseCircleFilled';
import PlayCircleFilledIcon from '@mui/icons-material/PlayCircleFilled';
import {
  Box,
  Chip,
  FormControl,
  IconButton,
  InputLabel,
  MenuItem,
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
import { useMemo, useState, type FC } from 'react';

import { useGetWorkflowRunsQuery } from 'features/workflow-execution/api/workflowRunsApi';
import type { WorkflowRun } from 'features/workflow-execution/lib/types';
import { Routes } from 'shared/routes';

export interface WorkflowRunsWidgetProps {
  projectId: number;
  onRunSelect?: (runId: number) => void;
}

type RunState = WorkflowRun['state'];
type RunMode = WorkflowRun['mode'];

const STATE_CONFIG: Record<
  RunState,
  { label: string; color: 'success' | 'error' | 'warning' | 'info' | 'default'; icon: React.ReactNode }
> = {
  completed: { label: 'Completed', color: 'success', icon: <CheckCircleIcon sx={{ fontSize: 14 }} /> },
  running: { label: 'Running', color: 'info', icon: <PlayCircleFilledIcon sx={{ fontSize: 14 }} /> },
  paused: { label: 'Paused', color: 'warning', icon: <PauseCircleFilledIcon sx={{ fontSize: 14 }} /> },
  failed: { label: 'Failed', color: 'error', icon: <ErrorIcon sx={{ fontSize: 14 }} /> },
  cancelled: { label: 'Cancelled', color: 'default', icon: <CancelIcon sx={{ fontSize: 14 }} /> },
  pending: { label: 'Pending', color: 'default', icon: <AccessTimeIcon sx={{ fontSize: 14 }} /> },
};

const MODE_LABELS: Record<RunMode, string> = {
  interactive: 'Interactive',
  non_interactive: 'Auto-run',
  mixed: 'Custom',
};

const STATE_OPTIONS: { value: RunState; label: string }[] = [
  { value: 'running', label: 'Running' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'pending', label: 'Pending' },
];

function formatDuration(start: string | null, end: string | null): string {
  if (!start) return '—';
  const s = new Date(start).getTime();
  const e = end ? new Date(end).getTime() : Date.now();
  const sec = Math.floor((e - s) / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  return `${min}m ${sec % 60}s`;
}

export const WorkflowRunsWidget: FC<WorkflowRunsWidgetProps> = ({ projectId, onRunSelect }) => {
  const [stateFilter, setStateFilter] = useState<RunState | ''>('');
  const { data: runs, isLoading, isFetching } = useGetWorkflowRunsQuery({ projectId }, { pollingInterval: 10_000 });

  const filtered = useMemo(() => {
    const sorted = [...(runs ?? [])].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    if (!stateFilter) return sorted;
    return sorted.filter((r) => r.state === stateFilter);
  }, [runs, stateFilter]);

  return (
    <Box sx={{ opacity: isFetching ? 0.7 : 1, transition: 'opacity 0.2s' }}>
      <Stack direction="row" spacing={1.5} sx={{ px: 2, py: 1.5 }} alignItems="center">
        <FormControl size="small" sx={{ minWidth: 130 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={stateFilter}
            label="Status"
            onChange={(e) => {
              setStateFilter(e.target.value as RunState | '');
            }}
          >
            <MenuItem value="">All</MenuItem>
            {STATE_OPTIONS.map((o) => (
              <MenuItem key={o.value} value={o.value}>
                {o.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
        <Typography variant="caption" color="text.secondary" sx={{ ml: 'auto !important' }}>
          {filtered.length} run{filtered.length !== 1 ? 's' : ''}
        </Typography>
      </Stack>

      {isLoading ? (
        <Box sx={{ p: 2 }}>
          {[...Array(5)].map((_, i) => (
            <Skeleton key={i} height={52} sx={{ mb: 0.5 }} />
          ))}
        </Box>
      ) : filtered.length === 0 ? (
        <Box sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">
            {stateFilter ? 'No runs match filter' : 'No workflow runs yet'}
          </Typography>
        </Box>
      ) : (
        <TableContainer>
          <Table size="small">
            <TableHead>
              <TableRow
                sx={{ '& th': { fontWeight: 600, fontSize: 12, color: 'text.secondary', py: 1, whiteSpace: 'nowrap' } }}
              >
                <TableCell>Status</TableCell>
                <TableCell>Workflow</TableCell>
                <TableCell>Mode</TableCell>
                <TableCell>Steps</TableCell>
                <TableCell>Duration</TableCell>
                <TableCell>Started</TableCell>
                <TableCell />
              </TableRow>
            </TableHead>
            <TableBody>
              {filtered.map((run) => (
                <RunRow key={run.id} run={run} projectId={projectId} onSelect={onRunSelect} />
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Box>
  );
};

interface RunRowProps {
  run: WorkflowRun;
  projectId: number;
  onSelect?: (id: number) => void;
}

const RunRow: FC<RunRowProps> = ({ run, projectId, onSelect }) => {
  const cfg = STATE_CONFIG[run.state];
  const completed = run.stepRuns.filter((s) => s.state === 'completed').length;
  const total = run.stepRuns.length;

  return (
    <TableRow hover sx={{ cursor: 'pointer', '& td': { py: 1, fontSize: 13 } }} onClick={() => onSelect?.(run.id)}>
      <TableCell>
        <Chip
          icon={cfg.icon as React.ReactElement}
          label={cfg.label}
          color={cfg.color}
          size="small"
          variant="outlined"
          sx={{ fontSize: 11, height: 22 }}
        />
      </TableCell>
      <TableCell>
        <Typography sx={{ fontSize: 13, fontWeight: 500 }}>{run.workflowName}</Typography>
        <Typography sx={{ fontSize: 11, color: 'text.secondary', fontFamily: 'monospace' }}>#{run.id}</Typography>
      </TableCell>
      <TableCell>
        <Typography sx={{ fontSize: 12 }}>{MODE_LABELS[run.mode]}</Typography>
      </TableCell>
      <TableCell>
        <Typography sx={{ fontSize: 12, fontFamily: 'monospace' }}>
          {completed}/{total}
        </Typography>
      </TableCell>
      <TableCell>
        <Typography sx={{ fontSize: 12, fontFamily: 'monospace', color: 'text.secondary' }}>
          {formatDuration(run.startedAt, run.completedAt)}
        </Typography>
      </TableCell>
      <TableCell>
        <Tooltip title={run.createdAt ? new Date(run.createdAt).toLocaleString() : ''} arrow>
          <Typography sx={{ fontSize: 12, color: 'text.secondary', whiteSpace: 'nowrap' }}>
            {formatDistanceToNow(new Date(run.createdAt), { addSuffix: true })}
          </Typography>
        </Tooltip>
      </TableCell>
      <TableCell>
        {(run.state === 'running' || run.state === 'paused') && (
          <Tooltip title="Open run" arrow>
            <IconButton
              size="small"
              onClick={(e) => {
                e.stopPropagation();
                window.open(Routes.frontend.workflowRunPath(String(projectId), String(run.id)), '_blank');
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
