import AccessTimeIcon from '@mui/icons-material/AccessTime';
import AccountTreeIcon from '@mui/icons-material/AccountTree';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import FolderIcon from '@mui/icons-material/Folder';
import PersonIcon from '@mui/icons-material/Person';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import TokenIcon from '@mui/icons-material/Token';
import {
  Autocomplete,
  Box,
  Card,
  Chip,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  Skeleton,
  TextField,
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

import { WorkflowCostsPanel } from 'features/workflow-cost-analytics';
import { formatCostCents, formatTokens } from 'shared/lib';

import type { AgentActivityData, AnalyticsPeriod, AnalyticsScope } from '../api/projectAnalyticsApi';
import {
  useGetAgentActivityQuery,
  useGetAnalyticsFilterOptionsQuery,
  useGetCostTokenUsageQuery,
  useGetProjectAnalyticsQuery,
  useGetSessionDurationDistributionQuery,
  useGetSessionSourceBreakdownQuery,
} from '../api/projectAnalyticsApi';

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

const SOURCE_COLORS = ['#2196f3', '#4caf50', '#ff9800', '#9c27b0', '#00bcd4', '#f44336'];

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

// ─── Main Component ──────────────────────────────────────────────────────────

interface ProjectAnalyticsPanelProps {
  projectId?: number;
}

const ProjectAnalyticsPanel = ({ projectId }: ProjectAnalyticsPanelProps) => {
  const [period, setPeriod] = useState<AnalyticsPeriod>('30d');
  const [scope, setScope] = useState<AnalyticsScope>('project');
  const [selectedTags, setSelectedTags] = useState<string[]>([]);
  const [selectedTaskType, setSelectedTaskType] = useState<string>('');

  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  const tickInterval = days <= 7 ? 0 : days <= 30 ? 4 : days <= 90 ? 9 : 29;

  const { data: filterOptions } = useGetAnalyticsFilterOptionsQuery(projectId!, { skip: !projectId });

  const filterParams = {
    tags: selectedTags.length > 0 ? selectedTags : undefined,
    taskType: selectedTaskType || undefined,
  };

  const {
    data: summary,
    isLoading,
    isError,
  } = useGetProjectAnalyticsQuery({ projectId: projectId!, scope, period, ...filterParams }, { skip: !projectId });

  const { data: agentActivity, isLoading: isAgentActivityLoading } = useGetAgentActivityQuery(
    { projectId: projectId!, scope, period, ...filterParams },
    { skip: !projectId },
  );

  const {
    data: sessionSourceData,
    isLoading: isSourceLoading,
    isError: isSourceError,
  } = useGetSessionSourceBreakdownQuery(
    { projectId: projectId!, scope, period, ...filterParams },
    { skip: !projectId },
  );

  const {
    data: durationData,
    isLoading: isDurationLoading,
    isError: isDurationError,
  } = useGetSessionDurationDistributionQuery(
    { projectId: projectId!, scope, period, ...filterParams },
    { skip: !projectId },
  );

  const {
    data: costTokenData,
    isLoading: isCostTokenLoading,
    isError: isCostTokenError,
  } = useGetCostTokenUsageQuery({ projectId: projectId!, scope, period, ...filterParams }, { skip: !projectId });

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
          <Autocomplete
            multiple
            size="small"
            options={filterOptions?.tags ?? []}
            value={selectedTags}
            onChange={(_, newValue) => setSelectedTags(newValue)}
            renderInput={(params) => (
              <TextField {...params} label="Tags" sx={{ backgroundColor: 'background.paper' }} />
            )}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip
                  label={option}
                  size="small"
                  {...getTagProps({ index })}
                  key={option}
                  sx={{ height: 18, fontSize: '11px' }}
                />
              ))
            }
            sx={{ minWidth: 180 }}
            disableCloseOnSelect
          />
          <FormControl size="small" sx={{ minWidth: 140 }}>
            <InputLabel>Task Type</InputLabel>
            <Select
              value={selectedTaskType}
              label="Task Type"
              onChange={(e) => setSelectedTaskType(e.target.value)}
              sx={{ backgroundColor: 'background.paper' }}
            >
              <MenuItem value="">All types</MenuItem>
              {(filterOptions?.taskTypes ?? []).map((type) => (
                <MenuItem key={type} value={type}>
                  {type.replace(/_/g, ' ')}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
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
      {isCostTokenError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load cost and token data. Please refresh to try again.
        </Typography>
      )}
      <Box sx={styles.twoCol}>
        {/* Cost over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Daily Cost</Typography>
          {isCostTokenLoading || !projectId ? (
            <Skeleton variant="rectangular" width="100%" height={220} sx={{ borderRadius: 1 }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={costTokenData?.timeSeries ?? []} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <defs>
                  <linearGradient id="grad-cost" x1="0" y1="0" x2="0" y2="1">
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
                  fill="url(#grad-cost)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Card>

        {/* Token usage over time */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.chartTitle}>Daily Token Consumption</Typography>
          {isCostTokenLoading || !projectId ? (
            <Skeleton variant="rectangular" width="100%" height={220} sx={{ borderRadius: 1 }} />
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={costTokenData?.timeSeries ?? []} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="grad-tokens" x1="0" y1="0" x2="0" y2="1">
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
                  fill="url(#grad-tokens)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Card>
      </Box>

      {/* ── Session Source Breakdown ──────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Session Source Breakdown</Typography>
      {isSourceError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load session source data. Please refresh to try again.
        </Typography>
      )}
      <Card sx={styles.card} elevation={0}>
        <Typography sx={styles.chartTitle}>Sessions by Origin</Typography>
        {isSourceLoading || !projectId ? (
          <Skeleton variant="rectangular" width="100%" height={200} sx={{ borderRadius: 1 }} />
        ) : (
          <Box sx={{ display: 'flex', gap: '24px', alignItems: 'center' }}>
            <ResponsiveContainer width="40%" height={200}>
              <PieChart>
                <Pie
                  data={(sessionSourceData?.sources ?? []).map((s) => ({ name: s.label, value: s.count }))}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  outerRadius={80}
                  paddingAngle={3}
                  label={({ percent }) => `${((percent ?? 0) * 100).toFixed(0)}%`}
                  labelLine={false}
                >
                  {(sessionSourceData?.sources ?? []).map((_, idx) => (
                    <Cell key={idx} fill={SOURCE_COLORS[idx % SOURCE_COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} sessions`]} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
              </PieChart>
            </ResponsiveContainer>
            <Box sx={{ flex: 1 }}>
              {(sessionSourceData?.sources ?? []).map((s, idx) => (
                <Box key={s.sessionType} sx={styles.agentRow}>
                  <Box sx={{ ...styles.agentDot, backgroundColor: SOURCE_COLORS[idx % SOURCE_COLORS.length] }} />
                  <Box sx={{ flex: 1 }}>
                    <Typography sx={{ fontSize: '13px', color: 'text.primary', fontWeight: 500 }}>{s.label}</Typography>
                    <Typography sx={{ fontSize: '11px', color: 'text.disabled' }}>{s.count} sessions</Typography>
                  </Box>
                </Box>
              ))}
            </Box>
          </Box>
        )}
      </Card>

      {/* ── Duration Distribution ─────────────────────────────────── */}
      <Typography sx={styles.sectionTitle}>Session Duration Distribution</Typography>
      {isDurationError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load session duration data. Please refresh to try again.
        </Typography>
      )}
      <Card sx={styles.card} elevation={0}>
        <Typography sx={styles.chartTitle}>Session Duration Histogram</Typography>
        {isDurationLoading || !projectId ? (
          <Skeleton variant="rectangular" width="100%" height={220} sx={{ borderRadius: 1 }} />
        ) : (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={durationData?.buckets ?? []} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" vertical={false} />
              <XAxis dataKey="range" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 12 }} />
              <Tooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${v} sessions`]} />
              <Bar dataKey="count" name="Sessions" fill="#9c27b0" radius={[4, 4, 0, 0]}>
                {(durationData?.buckets ?? []).map((_, idx) => (
                  <Cell key={idx} fill={`hsl(${280 - idx * 8}, 60%, ${55 - idx * 3}%)`} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </Card>

      {/* ── Workflow Costs ────────────────────────────────────────── */}
      <WorkflowCostsPanel
        projectId={projectId}
        scope={scope}
        period={period}
        tags={selectedTags.length > 0 ? selectedTags : undefined}
        taskType={selectedTaskType || undefined}
      />
    </Box>
  );
};

export default ProjectAnalyticsPanel;
