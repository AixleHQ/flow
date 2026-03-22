import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import TokenIcon from '@mui/icons-material/Token';
import { Box, Card, Chip, Skeleton, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import type { AnalyticsPeriod, AnalyticsScope } from 'features/project-analytics/api/projectAnalyticsApi';

import { useGetWorkflowCostAnalyticsQuery } from '../api/workflowCostAnalyticsApi';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatCostCents(cents: number): string {
  const dollars = cents / 100;
  if (dollars >= 1000) return `$${(dollars / 1000).toFixed(1)}k`;
  return `$${dollars.toFixed(2)}`;
}

function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(0)}k`;
  return tokens.toLocaleString();
}

const WORKFLOW_COLORS = [
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
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
    marginTop: '32px',
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
    gap: '16px',
    marginBottom: '8px',
  },
  statCard: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  statLabel: {
    fontSize: '12px',
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    marginBottom: '8px',
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  statValue: {
    fontSize: '28px',
    fontWeight: 700,
    color: 'text.primary',
    lineHeight: 1.1,
  },
  card: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  chartTitle: {
    fontSize: '15px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '20px',
  },
  twoCol: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '24px',
  },
  tableRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '12px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  colorDot: {
    width: 10,
    height: 10,
    borderRadius: '50%',
    flexShrink: 0,
  },
  progressBarBg: {
    height: '4px',
    borderRadius: '2px',
    backgroundColor: 'background.elevated',
    marginTop: '4px',
  },
} satisfies Record<string, SxProps<Theme>>;

// ─── Component ───────────────────────────────────────────────────────────────

interface WorkflowCostsPanelProps {
  projectId?: number;
  scope: AnalyticsScope;
  period: AnalyticsPeriod;
}

const WorkflowCostsPanel = ({ projectId, scope, period }: WorkflowCostsPanelProps) => {
  const { data, isLoading, isError } = useGetWorkflowCostAnalyticsQuery(
    { projectId: projectId!, scope, period },
    { skip: !projectId },
  );

  const totals = data?.totals;
  const workflows = data?.workflows ?? [];
  const timeSeries = data?.timeSeries ?? [];

  const maxCost = workflows.length > 0 ? workflows[0].totalCostCents : 1;

  const tickInterval = timeSeries.length <= 7 ? 0 : timeSeries.length <= 30 ? 4 : timeSeries.length <= 90 ? 8 : 1;

  const summaryStats = totals
    ? [
        {
          label: 'Total Cost',
          value: formatCostCents(totals.totalCostCents),
          icon: <AttachMoneyIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Total Tokens',
          value: formatTokens(totals.totalTokens),
          icon: <TokenIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Input Tokens',
          value: formatTokens(totals.inputTokens),
          icon: <TokenIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Output Tokens',
          value: formatTokens(totals.outputTokens),
          icon: <TokenIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Workflows',
          value: totals.workflowCount.toLocaleString(),
          icon: null,
        },
        {
          label: 'Avg Cost / Workflow',
          value: formatCostCents(totals.avgCostCentsPerWorkflow),
          icon: <AttachMoneyIcon sx={{ fontSize: 14 }} />,
        },
      ]
    : [];

  return (
    <>
      {/* ── Section Title ─────────────────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Workflow Costs</Typography>

      {isError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load workflow cost data. Please refresh to try again.
        </Typography>
      )}

      {/* ── Summary Stats ─────────────────────────────────────────── */}
      <Box sx={styles.statsGrid}>
        {isLoading || !projectId
          ? Array.from({ length: 6 }).map((_, i) => (
              <Card key={i} sx={styles.statCard} elevation={0}>
                <Skeleton variant="text" width={100} height={16} sx={{ marginBottom: '8px' }} />
                <Skeleton variant="text" width={80} height={34} />
              </Card>
            ))
          : summaryStats.map((s) => (
              <Card key={s.label} sx={styles.statCard} elevation={0}>
                <Typography sx={styles.statLabel}>
                  {s.icon}
                  {s.label}
                </Typography>
                <Typography sx={styles.statValue}>{s.value}</Typography>
              </Card>
            ))}
      </Box>

      {/* ── Charts ────────────────────────────────────────────────── */}
      <Box sx={{ ...styles.twoCol, marginTop: '24px' }}>
        {/* Cost trend over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Cost Over Time</Typography>
          {isLoading || !projectId ? (
            <Skeleton variant="rectangular" height={220} sx={{ borderRadius: '8px' }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <defs>
                  <linearGradient id="grad-wf-cost" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#ff9800" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#ff9800" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `$${(v / 100).toFixed(0)}`} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [formatCostCents(Number(v)), 'Cost']} />
                <Area
                  type="monotone"
                  dataKey="costCents"
                  name="Cost"
                  stroke="#ff9800"
                  fill="url(#grad-wf-cost)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Card>

        {/* Token trend over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Token Consumption Over Time</Typography>
          {isLoading || !projectId ? (
            <Skeleton variant="rectangular" height={220} sx={{ borderRadius: '8px' }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="grad-wf-tokens" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#00bcd4" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#00bcd4" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => formatTokens(Number(v))} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [formatTokens(Number(v)), 'Tokens']} />
                <Area
                  type="monotone"
                  dataKey="totalTokens"
                  name="Tokens"
                  stroke="#00bcd4"
                  fill="url(#grad-wf-tokens)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Card>
      </Box>

      {/* ── Per-Workflow Breakdown ─────────────────────────────────── */}
      <Box sx={{ ...styles.twoCol, marginTop: '24px' }}>
        {/* Bar chart: cost per workflow */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Cost per Workflow</Typography>
          {isLoading || !projectId ? (
            <Skeleton variant="rectangular" height={220} sx={{ borderRadius: '8px' }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart
                data={workflows.map((w, i) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  costCents: w.totalCostCents,
                  color: WORKFLOW_COLORS[i % WORKFLOW_COLORS.length],
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => `$${(v / 100).toFixed(0)}`} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={100} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [formatCostCents(Number(v)), 'Cost']} />
                <Bar dataKey="costCents" name="Cost" radius={[0, 4, 4, 0]}>
                  {workflows.map((_, i) => (
                    <Cell key={i} fill={WORKFLOW_COLORS[i % WORKFLOW_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}
        </Card>

        {/* Bar chart: tokens per workflow */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Tokens per Workflow</Typography>
          {isLoading || !projectId ? (
            <Skeleton variant="rectangular" height={220} sx={{ borderRadius: '8px' }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart
                data={workflows.map((w, i) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  inputTokens: w.inputTokens,
                  outputTokens: w.outputTokens,
                  color: WORKFLOW_COLORS[i % WORKFLOW_COLORS.length],
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v) => formatTokens(Number(v))} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={100} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v, name) => [formatTokens(Number(v)), name]} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="inputTokens" name="Input" stackId="tokens" fill="#2196f3" radius={[0, 0, 0, 0]} />
                <Bar dataKey="outputTokens" name="Output" stackId="tokens" fill="#9c27b0" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </Card>
      </Box>

      {/* ── Workflow Detail Table ──────────────────────────────────── */}
      <Card sx={{ ...styles.card, marginTop: '24px' }} elevation={0}>
        <Typography sx={styles.chartTitle}>Workflow Breakdown</Typography>
        {isLoading || !projectId ? (
          Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} variant="text" height={48} sx={{ marginBottom: '4px' }} />
          ))
        ) : workflows.length === 0 ? (
          <Typography sx={{ fontSize: '13px', color: 'text.secondary', py: 2, textAlign: 'center' }}>
            No workflow runs in the selected period.
          </Typography>
        ) : (
          <>
            {/* Header */}
            <Box
              sx={{
                display: 'grid',
                gridTemplateColumns: '1fr 120px 100px 100px 100px 80px',
                gap: '8px',
                padding: '8px 0',
                borderBottom: '1px solid',
                borderColor: 'divider',
                mb: 0.5,
              }}
            >
              {['Workflow', 'Total Cost', 'Input Tokens', 'Output Tokens', 'Total Tokens', 'Runs'].map((h) => (
                <Typography
                  key={h}
                  sx={{ fontSize: '11px', color: 'text.secondary', textTransform: 'uppercase', letterSpacing: '0.4px' }}
                >
                  {h}
                </Typography>
              ))}
            </Box>
            {workflows.map((w, i) => {
              const color = WORKFLOW_COLORS[i % WORKFLOW_COLORS.length];
              const pct = maxCost > 0 ? (w.totalCostCents / maxCost) * 100 : 0;
              return (
                <Box key={w.workflowId} sx={styles.tableRow}>
                  <Box
                    sx={{
                      display: 'grid',
                      gridTemplateColumns: '1fr 120px 100px 100px 100px 80px',
                      gap: '8px',
                      width: '100%',
                      alignItems: 'center',
                    }}
                  >
                    <Box>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <Box sx={{ ...styles.colorDot, backgroundColor: color }} />
                        <Typography sx={{ fontSize: '13px', color: 'text.primary', fontWeight: 500 }}>
                          {w.workflowName}
                        </Typography>
                      </Box>
                      <Box sx={{ ...styles.progressBarBg, width: '80%' }}>
                        <Box
                          sx={{
                            height: '4px',
                            borderRadius: '2px',
                            backgroundColor: color,
                            width: `${pct}%`,
                          }}
                        />
                      </Box>
                    </Box>
                    <Typography sx={{ fontSize: '13px', color: 'text.primary', fontWeight: 600 }}>
                      {formatCostCents(w.totalCostCents)}
                    </Typography>
                    <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                      {formatTokens(w.inputTokens)}
                    </Typography>
                    <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                      {formatTokens(w.outputTokens)}
                    </Typography>
                    <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                      {formatTokens(w.totalTokens)}
                    </Typography>
                    <Chip
                      label={w.runCount}
                      size="small"
                      sx={{ fontSize: '11px', height: 20, backgroundColor: 'background.elevated' }}
                    />
                  </Box>
                </Box>
              );
            })}
          </>
        )}
      </Card>
    </>
  );
};

export default WorkflowCostsPanel;
