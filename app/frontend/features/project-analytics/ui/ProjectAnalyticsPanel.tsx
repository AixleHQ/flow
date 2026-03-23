import AccessTimeIcon from '@mui/icons-material/AccessTime';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import BusinessIcon from '@mui/icons-material/Business';
import FolderIcon from '@mui/icons-material/Folder';
import PersonIcon from '@mui/icons-material/Person';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import TokenIcon from '@mui/icons-material/Token';
import {
  Box,
  Card,
  Chip,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  Skeleton,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import type { AgentActivityData, AnalyticsPeriod, AnalyticsScope } from '../api/projectAnalyticsApi';
import { useGetAgentActivityQuery, useGetProjectAnalyticsQuery } from '../api/projectAnalyticsApi';

// ─── Static Data Generators ─────────────────────────────────────────────────

const generateDailyData = (days: number) => {
  const result = [];
  const now = new Date();
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const label = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    result.push({
      date: label,
      cost: +(Math.random() * 80 + 40).toFixed(2),
      tokens: Math.floor(Math.random() * 500000 + 200000),
    });
  }
  return result;
};

// ─── Agent Activity Helpers ───────────────────────────────────────────────────

const AGENT_COLORS = ['#2196f3', '#9c27b0', '#4caf50', '#ff9800', '#00bcd4', '#f44336', '#795548'];

const getAgentColor = (index: number) => AGENT_COLORS[index % AGENT_COLORS.length];

const buildActivityChartData = (data: AgentActivityData): Record<string, string | number>[] => {
  const dateMap: Record<string, Record<string, string | number>> = {};
  for (const point of data.activityOverTime) {
    const label = new Date(point.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    if (!dateMap[label]) dateMap[label] = { date: label };
    dateMap[label][point.agentType] = point.sessions;
  }
  return Object.values(dateMap);
};

const SESSION_SOURCE_DATA = [
  { name: 'From Workflows', value: 624, color: '#2196f3' },
  { name: 'Standalone', value: 418, color: '#4caf50' },
  { name: 'Board Tasks', value: 242, color: '#ff9800' },
];

const COST_DISTRIBUTION = [
  { range: '$0–$5', count: 312 },
  { range: '$5–$15', count: 487 },
  { range: '$15–$30', count: 241 },
  { range: '$30–$60', count: 143 },
  { range: '$60–$100', count: 72 },
  { range: '$100+', count: 29 },
];

const DURATION_DISTRIBUTION = [
  { range: '0–1 min', count: 198 },
  { range: '1–5 min', count: 413 },
  { range: '5–15 min', count: 387 },
  { range: '15–30 min', count: 164 },
  { range: '30–60 min', count: 87 },
  { range: '60+ min', count: 35 },
];

// ─── Styles ──────────────────────────────────────────────────────────────────

const styles = {
  container: {
    padding: '24px 0',
  },
  pageHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '32px',
    flexWrap: 'wrap',
    gap: '16px',
  },
  pageTitle: {
    fontSize: '24px',
    fontWeight: 700,
    color: 'text.primary',
    marginBottom: '4px',
  },
  pageSubtitle: {
    fontSize: '14px',
    color: 'text.secondary',
  },
  sectionTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
    marginTop: '32px',
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
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
    fontSize: '30px',
    fontWeight: 700,
    color: 'text.primary',
    lineHeight: 1.1,
    marginBottom: '4px',
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
  agentRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '10px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  agentDot: {
    width: 10,
    height: 10,
    borderRadius: '50%',
    flexShrink: 0,
  },
} satisfies Record<string, SxProps<Theme>>;

// ─── Sub-components ──────────────────────────────────────────────────────────

const ScopeSelector = ({ scope, onScope }: { scope: AnalyticsScope; onScope: (v: AnalyticsScope) => void }) => (
  <ToggleButtonGroup
    value={scope}
    exclusive
    onChange={(_, v) => v && onScope(v as AnalyticsScope)}
    size="small"
    sx={{ '& .MuiToggleButton-root': { textTransform: 'none', fontSize: '12px', px: 2 } }}
  >
    {[
      { value: 'user' as const, icon: <PersonIcon sx={{ fontSize: 14 }} />, label: 'User' },
      { value: 'project' as const, icon: <FolderIcon sx={{ fontSize: 14 }} />, label: 'Project' },
      { value: 'company' as const, icon: <BusinessIcon sx={{ fontSize: 14 }} />, label: 'Company' },
    ].map((item) => (
      <ToggleButton key={item.value} value={item.value}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          {item.icon}
          {item.label}
        </Box>
      </ToggleButton>
    ))}
  </ToggleButtonGroup>
);

const chartTooltipStyle = {
  backgroundColor: '#1a1a2e',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: '#fff',
};

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

// ─── Main Component ──────────────────────────────────────────────────────────

interface ProjectAnalyticsPanelProps {
  projectId?: number;
}

const ProjectAnalyticsPanel = ({ projectId }: ProjectAnalyticsPanelProps) => {
  const [period, setPeriod] = useState<AnalyticsPeriod>('30d');
  const [scope, setScope] = useState<AnalyticsScope>('project');

  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  const chartData = generateDailyData(days);
  const tickInterval = days <= 7 ? 0 : days <= 30 ? 4 : days <= 90 ? 9 : 29;

  const {
    data: summary,
    isLoading,
    isError,
  } = useGetProjectAnalyticsQuery({ projectId: projectId!, scope, period }, { skip: !projectId });

  const { data: agentActivity, isLoading: isAgentActivityLoading } = useGetAgentActivityQuery(
    { projectId: projectId!, scope, period },
    { skip: !projectId },
  );

  const activityChartData = agentActivity ? buildActivityChartData(agentActivity) : [];
  const agentTypes = agentActivity?.agentTypes ?? [];
  const sessionsByAgent = agentActivity?.sessionsByAgent ?? [];

  const statBlocks = summary
    ? [
        {
          label: 'Total Sessions',
          value: summary.totalSessions.toLocaleString(),
          icon: <AccessTimeIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Total Cost',
          value: formatCostCents(summary.totalCostCents),
          icon: <AttachMoneyIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Total Tokens',
          value: formatTokens(summary.totalTokens),
          icon: <TokenIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Avg Cost / Session',
          value: formatCostCents(summary.avgCostCentsPerSession),
          icon: <SmartToyIcon sx={{ fontSize: 14 }} />,
        },
        {
          label: 'Workflows Run',
          value: summary.workflowsRun.toLocaleString(),
          icon: <AccountTreeIcon sx={{ fontSize: 14 }} />,
        },
      ]
    : [];

  return (
    <Box sx={styles.container}>
      {/* Header */}
      <Box sx={styles.pageHeader}>
        <Box>
          <Typography sx={styles.pageTitle}>Analytics</Typography>
          <Typography sx={styles.pageSubtitle}>Agent activity, costs, and session insights</Typography>
        </Box>
        <Box sx={{ display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' }}>
          <ScopeSelector scope={scope} onScope={setScope} />
          <FormControl size="small" sx={{ minWidth: 130 }}>
            <InputLabel>Period</InputLabel>
            <Select
              value={period}
              label="Period"
              onChange={(e) => setPeriod(e.target.value as AnalyticsPeriod)}
              sx={{ backgroundColor: 'background.paper' }}
            >
              <MenuItem value="7d">Last 7 days</MenuItem>
              <MenuItem value="30d">Last 30 days</MenuItem>
              <MenuItem value="90d">Last 90 days</MenuItem>
              <MenuItem value="1y">Last year</MenuItem>
            </Select>
          </FormControl>
        </Box>
      </Box>

      {/* Summary Stats */}
      {isError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load analytics. Please refresh to try again.
        </Typography>
      )}
      <Box sx={styles.statsGrid}>
        {isLoading || !projectId
          ? Array.from({ length: 5 }).map((_, i) => (
              <Card key={i} sx={styles.statCard} elevation={0}>
                <Skeleton variant="text" width={100} height={16} sx={{ marginBottom: '8px' }} />
                <Skeleton variant="text" width={80} height={36} />
              </Card>
            ))
          : statBlocks.map((s) => (
              <Card key={s.label} sx={styles.statCard} elevation={0}>
                <Typography sx={styles.statLabel}>
                  {s.icon}
                  {s.label}
                </Typography>
                <Typography sx={styles.statValue}>{s.value}</Typography>
              </Card>
            ))}
      </Box>

      {/* ── Agent Activity ─────────────────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Agent Activity</Typography>
      <Box sx={styles.twoCol}>
        {/* Sessions per agent over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Sessions per Agent — Trend</Typography>
          {isAgentActivityLoading ? (
            <Skeleton variant="rectangular" width="100%" height={240} sx={{ borderRadius: 1 }} />
          ) : (
            <ResponsiveContainer width="100%" height={240}>
              <AreaChart data={activityChartData} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <defs>
                  {agentTypes.map((agentType, idx) => (
                    <linearGradient key={agentType} id={`grad-agent-${idx}`} x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor={getAgentColor(idx)} stopOpacity={0.25} />
                      <stop offset="95%" stopColor={getAgentColor(idx)} stopOpacity={0} />
                    </linearGradient>
                  ))}
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip contentStyle={chartTooltipStyle} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                {agentTypes.map((agentType, idx) => (
                  <Area
                    key={agentType}
                    type="monotone"
                    dataKey={agentType}
                    name={agentType}
                    stroke={getAgentColor(idx)}
                    fill={`url(#grad-agent-${idx})`}
                    strokeWidth={2}
                    dot={false}
                  />
                ))}
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Card>

        {/* Agent type breakdown */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Usage Breakdown by Agent Type</Typography>
          {isAgentActivityLoading ? (
            <Skeleton variant="rectangular" width="100%" height={200} sx={{ borderRadius: 1 }} />
          ) : (
            <Box sx={{ display: 'flex', gap: '24px', alignItems: 'center' }}>
              <ResponsiveContainer width="50%" height={200}>
                <PieChart>
                  <Pie
                    data={sessionsByAgent}
                    dataKey="sessions"
                    nameKey="agentType"
                    cx="50%"
                    cy="50%"
                    innerRadius={55}
                    outerRadius={85}
                    paddingAngle={3}
                  >
                    {sessionsByAgent.map((entry, idx) => (
                      <Cell key={entry.agentType} fill={getAgentColor(idx)} />
                    ))}
                  </Pie>
                  <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} sessions`]} />
                </PieChart>
              </ResponsiveContainer>
              <Box sx={{ flex: 1 }}>
                {sessionsByAgent.map((agent, idx) => (
                  <Box key={agent.agentType} sx={styles.agentRow}>
                    <Box sx={{ ...styles.agentDot, backgroundColor: getAgentColor(idx) }} />
                    <Box sx={{ flex: 1 }}>
                      <Typography sx={{ fontSize: '12px', color: 'text.primary', fontWeight: 500 }}>
                        {agent.agentType}
                      </Typography>
                      <Typography sx={{ fontSize: '11px', color: 'text.disabled' }}>
                        {agent.sessions} sessions
                      </Typography>
                    </Box>
                    <Chip
                      label={formatCostCents(agent.costCents)}
                      size="small"
                      sx={{ fontSize: '11px', height: 18, backgroundColor: 'background.elevated' }}
                    />
                  </Box>
                ))}
              </Box>
            </Box>
          )}
        </Card>
      </Box>

      {/* ── Cost & Token Usage ────────────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Cost & Token Usage</Typography>
      <Box sx={styles.twoCol}>
        {/* Cost over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Daily Cost</Typography>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={chartData} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <defs>
                <linearGradient id="grad-cost" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ff9800" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#ff9800" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `$${v}`} />
              <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`$${Number(v).toFixed(2)}`, 'Cost']} />
              <Area
                type="monotone"
                dataKey="cost"
                name="Cost"
                stroke="#ff9800"
                fill="url(#grad-cost)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Card>

        {/* Token usage over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Daily Token Consumption</Typography>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={chartData} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="grad-tokens" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#00bcd4" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#00bcd4" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip
                contentStyle={chartTooltipStyle}
                formatter={(v) => [`${(Number(v) / 1000).toFixed(0)}k`, 'Tokens']}
              />
              <Area
                type="monotone"
                dataKey="tokens"
                name="Tokens"
                stroke="#00bcd4"
                fill="url(#grad-tokens)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Card>
      </Box>

      {/* ── Session Source Breakdown ──────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Session Source Breakdown</Typography>
      <Box sx={{ ...styles.twoCol, gridTemplateColumns: '1fr 2fr' }}>
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Sessions by Origin</Typography>
          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie
                data={SESSION_SOURCE_DATA}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                outerRadius={80}
                paddingAngle={3}
                label={({ percent }) => `${((percent ?? 0) * 100).toFixed(0)}%`}
                labelLine={false}
              >
                {SESSION_SOURCE_DATA.map((entry) => (
                  <Cell key={entry.name} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} sessions`]} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
            </PieChart>
          </ResponsiveContainer>
        </Card>

        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          {/* Cost distribution */}
          <Card sx={styles.card} elevation={0}>
            <Typography sx={styles.chartTitle}>Cost per Run — Distribution</Typography>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={COST_DISTRIBUTION} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" vertical={false} />
                <XAxis dataKey="range" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} runs`]} />
                <Bar dataKey="count" name="Runs" fill="#2196f3" radius={[4, 4, 0, 0]}>
                  {COST_DISTRIBUTION.map((_, idx) => (
                    <Cell key={idx} fill={`hsl(${200 + idx * 12}, 70%, ${55 - idx * 4}%)`} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </Box>
      </Box>

      {/* ── Duration Distribution ─────────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Session Duration Distribution</Typography>
      <Card sx={styles.card} elevation={0}>
        <Typography sx={styles.chartTitle}>Session Duration Histogram</Typography>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={DURATION_DISTRIBUTION} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" vertical={false} />
            <XAxis dataKey="range" tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} />
            <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} sessions`]} />
            <Bar dataKey="count" name="Sessions" fill="#9c27b0" radius={[4, 4, 0, 0]}>
              {DURATION_DISTRIBUTION.map((_, idx) => (
                <Cell key={idx} fill={`hsl(${280 - idx * 8}, 60%, ${55 - idx * 3}%)`} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </Card>
    </Box>
  );
};

export default ProjectAnalyticsPanel;
