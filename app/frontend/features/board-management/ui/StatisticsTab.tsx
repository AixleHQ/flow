import AccessTimeIcon from '@mui/icons-material/AccessTime';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import HourglassEmptyIcon from '@mui/icons-material/HourglassEmpty';
import TokenIcon from '@mui/icons-material/Token';
import { Box, Card, Chip, Skeleton, Table, TableBody, TableCell, TableHead, TableRow, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

import { formatCostCents, formatDuration, formatTokens } from 'shared/lib';

import { useGetTaskStatisticsQuery } from '../api/boardApi';

const COLUMN_COLORS = [
  '#2196f3',
  '#9c27b0',
  '#4caf50',
  '#ff9800',
  '#e91e63',
  '#00bcd4',
  '#ff5722',
  '#3f51b5',
  '#8bc34a',
  '#ffc107',
];

const chartTooltipStyle = {
  backgroundColor: '#1a1a2e',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: '#fff',
};

// ─── Styles ──────────────────────────────────────────────────────────────────

const styles = {
  sectionTitle: {
    fontSize: '13px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    marginBottom: '12px',
    marginTop: '24px',
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(120px, 1fr))',
    gap: '12px',
    marginBottom: '8px',
  },
  statCard: {
    padding: '16px',
    backgroundColor: 'background.paper',
    borderRadius: '10px',
    border: '1px solid',
    borderColor: 'divider',
  },
  statLabel: {
    fontSize: '11px',
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.4px',
    marginBottom: '6px',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  statValue: {
    fontSize: '22px',
    fontWeight: 700,
    color: 'text.primary',
    lineHeight: 1.1,
  },
  card: {
    padding: '16px',
    backgroundColor: 'background.paper',
    borderRadius: '10px',
    border: '1px solid',
    borderColor: 'divider',
  },
  chartTitle: {
    fontSize: '13px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
  },
  tableRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '8px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  colorDot: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    flexShrink: 0,
  },
} satisfies Record<string, SxProps<Theme>>;

// ─── Component ───────────────────────────────────────────────────────────────

interface StatisticsTabProps {
  taskId: number;
  projectId: number;
}

export const StatisticsTab = ({ taskId, projectId }: StatisticsTabProps) => {
  const { data, isLoading, isError } = useGetTaskStatisticsQuery({ projectId, taskId });

  if (isLoading) {
    return (
      <Box sx={{ pt: 1 }}>
        <Box sx={styles.statsGrid}>
          {Array.from({ length: 3 }).map((_, i) => (
            <Card key={i} sx={styles.statCard} elevation={0}>
              <Skeleton variant="text" width={80} height={14} sx={{ mb: 1 }} />
              <Skeleton variant="text" width={60} height={26} />
            </Card>
          ))}
        </Box>
        <Skeleton variant="rectangular" height={180} sx={{ borderRadius: '10px', mt: 3 }} />
      </Box>
    );
  }

  if (isError || !data) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 120 }}>
        <Typography sx={{ fontSize: '13px', color: 'error.main' }}>
          Failed to load statistics. Please try again.
        </Typography>
      </Box>
    );
  }

  const { workflowBreakdowns, costTotals, tokenTotals, timeTotals, waitStats } = data;

  const pendingWaits = waitStats.filter((w) => w.status === 'pending');
  const resolvedWaits = waitStats.filter((w) => w.status === 'resolved');

  const summaryStats = [
    {
      label: 'Total Cost',
      value: formatCostCents(costTotals.totalCostCents),
      icon: <AttachMoneyIcon sx={{ fontSize: 12 }} />,
    },
    {
      label: 'Total Tokens',
      value: formatTokens(tokenTotals.totalTokens),
      icon: <TokenIcon sx={{ fontSize: 12 }} />,
    },
    {
      label: 'Total Run Time',
      value: formatDuration(timeTotals.totalDurationSeconds),
      icon: <AccessTimeIcon sx={{ fontSize: 12 }} />,
    },
  ];

  return (
    <Box sx={{ pt: 1 }}>
      {/* ── Summary stats ─────────────────────────────────────── */}
      <Box sx={styles.statsGrid}>
        {summaryStats.map((s) => (
          <Card key={s.label} sx={styles.statCard} elevation={0}>
            <Typography sx={styles.statLabel}>
              {s.icon}
              {s.label}
            </Typography>
            <Typography sx={styles.statValue}>{s.value}</Typography>
          </Card>
        ))}
      </Box>

      {/* ── Breakdown by Workflow ──────────────────────────────── */}
      {workflowBreakdowns.length > 0 && (
        <>
          <Typography sx={styles.sectionTitle}>Breakdown by Workflow</Typography>
          <Card sx={styles.card} elevation={0}>
            <Typography sx={styles.chartTitle}>Cost per Workflow</Typography>
            <ResponsiveContainer width="100%" height={Math.max(workflowBreakdowns.length * 36, 80)}>
              <BarChart
                data={workflowBreakdowns.map((b, i) => ({
                  name: b.workflowName.length > 20 ? b.workflowName.slice(0, 18) + '…' : b.workflowName,
                  costCents: b.costCents,
                  color: COLUMN_COLORS[i % COLUMN_COLORS.length],
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => formatCostCents(Number(v))} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={110} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [formatCostCents(Number(v)), 'Cost']} />
                <Bar dataKey="costCents" radius={[0, 4, 4, 0]}>
                  {workflowBreakdowns.map((_, i) => (
                    <Cell key={i} fill={COLUMN_COLORS[i % COLUMN_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>

            <Table size="small" sx={{ mt: 2 }}>
              <TableHead>
                <TableRow>
                  <TableCell sx={{ fontSize: '11px', color: 'text.secondary', fontWeight: 600 }}>Workflow</TableCell>
                  <TableCell align="right" sx={{ fontSize: '11px', color: 'text.secondary', fontWeight: 600 }}>
                    Cost
                  </TableCell>
                  <TableCell align="right" sx={{ fontSize: '11px', color: 'text.secondary', fontWeight: 600 }}>
                    Tokens
                  </TableCell>
                  <TableCell align="right" sx={{ fontSize: '11px', color: 'text.secondary', fontWeight: 600 }}>
                    Run Time
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {workflowBreakdowns.map((b, i) => (
                  <TableRow key={b.workflowId}>
                    <TableCell sx={{ fontSize: '12px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <Box sx={{ ...styles.colorDot, backgroundColor: COLUMN_COLORS[i % COLUMN_COLORS.length] }} />
                      {b.workflowName}
                    </TableCell>
                    <TableCell align="right" sx={{ fontSize: '12px' }}>
                      {formatCostCents(b.costCents)}
                    </TableCell>
                    <TableCell align="right" sx={{ fontSize: '12px' }}>
                      {formatTokens(b.totalTokens)}
                    </TableCell>
                    <TableCell align="right" sx={{ fontSize: '12px' }}>
                      {formatDuration(b.durationSeconds)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        </>
      )}

      {/* ── Waits ──────────────────────────────────────────────── */}
      {waitStats.length > 0 && (
        <>
          <Typography sx={styles.sectionTitle}>
            Waits
            <Box component="span" sx={{ ml: 1, fontWeight: 400, fontSize: '11px', color: 'text.disabled' }}>
              {pendingWaits.length} pending · {resolvedWaits.length} resolved
            </Box>
          </Typography>
          <Card sx={styles.card} elevation={0}>
            {waitStats.map((wait) => (
              <Box key={wait.id} sx={styles.tableRow}>
                {wait.status === 'resolved' ? (
                  <CheckCircleOutlineIcon sx={{ fontSize: 14, color: 'success.main', flexShrink: 0 }} />
                ) : (
                  <HourglassEmptyIcon sx={{ fontSize: 14, color: 'warning.main', flexShrink: 0 }} />
                )}
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography sx={{ fontSize: '12px', color: 'text.primary', fontWeight: 500 }}>
                    {wait.waitType.replace(/_/g, ' ')}
                  </Typography>
                  {wait.durationSeconds !== null && (
                    <Typography sx={{ fontSize: '11px', color: 'text.disabled' }}>
                      Resolved in {formatDuration(wait.durationSeconds)}
                    </Typography>
                  )}
                </Box>
                <Chip
                  label={wait.status}
                  size="small"
                  sx={{
                    fontSize: '10px',
                    height: 18,
                    backgroundColor: wait.status === 'resolved' ? 'success.dark' : 'warning.dark',
                    color: '#fff',
                  }}
                />
              </Box>
            ))}
          </Card>
        </>
      )}

      <Box sx={{ height: 16 }} />
    </Box>
  );
};
