import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Box, Grid, Group, Paper, Select, SimpleGrid, Skeleton, Text } from '@mantine/core';
import { IconChartBar, IconClock, IconCoin, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
import { useMemo } from 'react';
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
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { AuthLayout } from 'layouts/AuthLayout';

type Scope = 'company' | 'user';
type Period = '7d' | '30d' | '90d' | '1y';

interface ProjectBreakdown {
  projectId: number;
  projectName: string;
  sessions: number;
  costCents: number;
  tokens: number;
}

interface SummaryData {
  totalSessions: number;
  totalCostCents: number;
  totalTokens: number;
  avgCostCentsPerSession: number;
  workflowsRun: number;
  projectBreakdowns: ProjectBreakdown[];
}

interface AgentSessionCount {
  agentType: string;
  sessions: number;
  costCents: number;
  tokens: number;
}
interface AgentActivityPoint {
  date: string;
  agentType: string;
  sessions: number;
}
interface AgentActivityData {
  agentTypes: string[];
  sessionsByAgent: AgentSessionCount[];
  activityOverTime: AgentActivityPoint[];
}

interface SourceRow {
  sessionType: string;
  label: string;
  count: number;
}
interface SourceData {
  sources: SourceRow[];
}

interface DurationBucket {
  range: string;
  count: number;
}
interface DurationData {
  buckets: DurationBucket[];
}

interface CostTokenPoint {
  date: string;
  costCents: number;
  totalTokens: number;
}
interface CostTokenData {
  timeSeries: CostTokenPoint[];
  totals: { totalCostCents: number; totalTokens: number; avgCostCentsPerSession: number };
}

interface WorkflowCostRow {
  workflowId: number;
  workflowName: string;
  totalCostCents: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  runCount: number;
  totalDurationSeconds: number;
  avgDurationSeconds: number;
}
interface WorkflowCostTotals {
  totalCostCents: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  workflowCount: number;
  avgCostCentsPerWorkflow: number;
}
interface WorkflowCostData {
  workflows: WorkflowCostRow[];
  timeSeries: { date: string; costCents: number; totalTokens: number }[];
  totals: WorkflowCostTotals;
}

interface Props {
  scope: Scope;
  period: Period;
  summary?: SummaryData;
  agentActivity?: AgentActivityData;
  sources?: SourceData;
  duration?: DurationData;
  costToken?: CostTokenData;
  workflowCosts?: WorkflowCostData;
}

const AGENT_COLORS = ['#2196f3', '#9c27b0', '#4caf50', '#ff9800', '#00bcd4', '#f44336', '#795548'];
const SOURCE_COLORS = ['#2196f3', '#4caf50', '#ff9800', '#9c27b0', '#00bcd4', '#f44336'];
const PROJECT_COLORS = [
  '#2196f3', '#9c27b0', '#4caf50', '#ff9800', '#e91e63',
  '#00bcd4', '#ff5722', '#3f51b5', '#8bc34a', '#ffc107',
];
const WORKFLOW_COLORS = PROJECT_COLORS;
const getAgentColor = (i: number) => AGENT_COLORS[i % AGENT_COLORS.length];

const PERIOD_OPTIONS = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' },
  { value: '1y', label: 'Last year' },
];

const chartTooltipStyle = {
  backgroundColor: '#1a1a2e',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: '#fff',
};

function formatCostCents(cents: number): string {
  const d = (cents ?? 0) / 100;
  if (d >= 1000) return `$${(d / 1000).toFixed(1)}k`;
  return `$${d.toFixed(2)}`;
}

function formatTokens(n: number): string {
  if (!n) return '0';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return '0s';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function buildActivityChartData(data: AgentActivityData): Record<string, string | number>[] {
  const dateMap: Record<string, Record<string, string | number>> = {};
  for (const point of data.activityOverTime) {
    const label = new Date(point.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    if (!dateMap[label]) dateMap[label] = { date: label };
    dateMap[label][point.agentType] = point.sessions;
  }
  return Object.values(dateMap);
}

function tickIntervalForPeriod(period: Period): number {
  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  return days <= 7 ? 0 : days <= 30 ? 4 : days <= 90 ? 9 : 29;
}

function navigateWithFilters(scope: string, period: string) {
  router.get(window.location.pathname, { scope, period }, { preserveState: true, preserveScroll: true });
}

// --- Skeleton blocks ---

function SummarySkeletons() {
  return (
    <>
      {Array.from({ length: 5 }).map((_, i) => (
        <Paper key={i} withBorder p="lg" radius="md">
          <Skeleton height={14} width={100} mb={12} />
          <Skeleton height={38} width={90} />
        </Paper>
      ))}
    </>
  );
}

function ChartSkeleton({ height = 240 }: { height?: number }) {
  return <Skeleton height={height} radius="sm" />;
}

function WorkflowCostSkeletons() {
  return (
    <>
      <SimpleGrid cols={{ base: 2, sm: 4, md: 7 }} mb="xl" spacing="md">
        {Array.from({ length: 7 }).map((_, i) => (
          <Paper key={i} withBorder p="lg" radius="md">
            <Skeleton height={14} width={90} mb={10} />
            <Skeleton height={30} width={70} />
          </Paper>
        ))}
      </SimpleGrid>
      <Skeleton height={220} radius="sm" mb="xl" />
      <Skeleton height={220} radius="sm" mb="xl" />
    </>
  );
}

// --- Data panels ---

function SummaryPanel() {
  const { summary } = usePage<{ props: Props }>().props as unknown as Props;
  if (!summary) return null;

  const statBlocks = [
    { label: 'Total Sessions', value: summary.totalSessions.toLocaleString(), icon: IconPlayerPlay, color: 'blue' },
    { label: 'Total Cost', value: formatCostCents(summary.totalCostCents), icon: IconCoin, color: 'green' },
    { label: 'Total Tokens', value: formatTokens(summary.totalTokens), icon: IconChartBar, color: 'violet' },
    {
      label: 'Avg Cost / Session',
      value: formatCostCents(summary.avgCostCentsPerSession),
      icon: IconClock,
      color: 'orange',
    },
    { label: 'Workflows Run', value: summary.workflowsRun.toLocaleString(), icon: IconRoute, color: 'indigo' },
  ];

  return (
    <>
      {statBlocks.map((s) => (
        <Paper key={s.label} withBorder p="lg" radius="md">
          <Group gap={6} mb={12}>
            <s.icon size={14} color={`var(--mantine-color-${s.color}-5)`} />
            <Text size="xs" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
              {s.label}
            </Text>
          </Group>
          <Text fw={700} lh={1.1} style={{ fontSize: 30 }}>
            {s.value}
          </Text>
        </Paper>
      ))}
    </>
  );
}

function ProjectBreakdownPanel() {
  const { summary } = usePage<{ props: Props }>().props as unknown as Props;
  if (!summary || !summary.projectBreakdowns || summary.projectBreakdowns.length === 0) return null;

  const { projectBreakdowns } = summary;
  const maxCost = projectBreakdowns.length > 0 ? Math.max(...projectBreakdowns.map((p) => p.costCents)) : 1;

  return (
    <Paper withBorder p="md" radius="md" mb="xl">
      <Text size="sm" fw={600} mb="md">
        Per-Project Breakdown
      </Text>
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 100px 130px 120px',
          gap: 8,
          padding: '8px 0',
          borderBottom: '1px solid var(--mantine-color-dark-4)',
        }}
      >
        {['Project', 'Sessions', 'Cost', 'Tokens'].map((h) => (
          <Text key={h} size="xs" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
            {h}
          </Text>
        ))}
      </Box>
      {projectBreakdowns.map((p, i) => {
        const color = PROJECT_COLORS[i % PROJECT_COLORS.length];
        const pct = maxCost > 0 ? (p.costCents / maxCost) * 100 : 0;
        return (
          <Box
            key={p.projectId}
            style={{
              display: 'grid',
              gridTemplateColumns: '1fr 100px 130px 120px',
              gap: 8,
              alignItems: 'center',
              padding: '12px 0',
              borderBottom: i < projectBreakdowns.length - 1 ? '1px solid var(--mantine-color-dark-4)' : undefined,
            }}
          >
            <Box>
              <Group gap={8}>
                <Box w={10} h={10} style={{ borderRadius: '50%', backgroundColor: color, flexShrink: 0 }} />
                <Text size="sm" fw={500}>
                  {p.projectName}
                </Text>
              </Group>
              <Box
                mt={4}
                style={{
                  width: '80%',
                  height: 4,
                  borderRadius: 2,
                  backgroundColor: 'var(--mantine-color-dark-5)',
                }}
              >
                <Box style={{ height: 4, borderRadius: 2, backgroundColor: color, width: `${pct}%` }} />
              </Box>
            </Box>
            <Text size="sm" c="dimmed">
              {p.sessions.toLocaleString()}
            </Text>
            <Text size="sm" fw={600}>
              {formatCostCents(p.costCents)}
            </Text>
            <Text size="sm" c="dimmed">
              {formatTokens(p.tokens)}
            </Text>
          </Box>
        );
      })}
    </Paper>
  );
}

function AgentActivityPanel({ tickInterval }: { tickInterval: number }) {
  const { agentActivity } = usePage<{ props: Props }>().props as unknown as Props;
  if (!agentActivity) return null;

  const activityChartData = buildActivityChartData(agentActivity);
  const { agentTypes, sessionsByAgent } = agentActivity;

  return (
    <Grid mb="xl" gap="md">
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p="md" radius="md" h="100%">
          <Text size="sm" fw={600} mb="md">
            Sessions per Agent — Trend
          </Text>
          <ResponsiveContainer width="100%" height={240}>
            <AreaChart data={activityChartData} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <defs>
                {agentTypes.map((agentType, idx) => (
                  <linearGradient key={agentType} id={`cmp-grad-agent-${idx}`} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={getAgentColor(idx)} stopOpacity={0.25} />
                    <stop offset="95%" stopColor={getAgentColor(idx)} stopOpacity={0} />
                  </linearGradient>
                ))}
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} />
              <RechartsTooltip contentStyle={chartTooltipStyle} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              {agentTypes.map((agentType, idx) => (
                <Area
                  key={agentType}
                  type="monotone"
                  dataKey={agentType}
                  name={agentType}
                  stroke={getAgentColor(idx)}
                  fill={`url(#cmp-grad-agent-${idx})`}
                  strokeWidth={2}
                  dot={false}
                />
              ))}
            </AreaChart>
          </ResponsiveContainer>
        </Paper>
      </Grid.Col>

      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p="md" radius="md" h="100%">
          <Text size="sm" fw={600} mb="md">
            Usage Breakdown by Agent Type
          </Text>
          <Group gap="lg" align="center">
            <Box style={{ width: '50%' }}>
              <ResponsiveContainer width="100%" height={200}>
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
                  <RechartsTooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${Number(v)} sessions`]} />
                </PieChart>
              </ResponsiveContainer>
            </Box>
            <Box style={{ flex: 1 }}>
              {sessionsByAgent.map((agent, idx) => (
                <Group
                  key={agent.agentType}
                  gap="sm"
                  py={8}
                  style={{
                    borderBottom:
                      idx < sessionsByAgent.length - 1 ? '1px solid var(--mantine-color-dark-4)' : undefined,
                  }}
                >
                  <Box
                    w={10}
                    h={10}
                    style={{ borderRadius: '50%', backgroundColor: getAgentColor(idx), flexShrink: 0 }}
                  />
                  <Box style={{ flex: 1 }}>
                    <Text size="xs" fw={500}>
                      {agent.agentType}
                    </Text>
                    <Text size="xs" c="dimmed">
                      {agent.sessions} sessions
                    </Text>
                  </Box>
                  <Text size="xs" fw={500} c="dimmed">
                    {formatCostCents(agent.costCents)}
                  </Text>
                </Group>
              ))}
            </Box>
          </Group>
        </Paper>
      </Grid.Col>
    </Grid>
  );
}

function CostTokenPanel({ tickInterval }: { tickInterval: number }) {
  const { costToken } = usePage<{ props: Props }>().props as unknown as Props;
  if (!costToken) return null;

  return (
    <Grid mb="xl" gap="md">
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p="md" radius="md">
          <Text size="sm" fw={600} mb="md">
            Daily Cost
          </Text>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={costToken.timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <defs>
                <linearGradient id="cmp-grad-cost" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ff9800" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#ff9800" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`} />
              <RechartsTooltip
                contentStyle={chartTooltipStyle}
                formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
              />
              <Area
                type="monotone"
                dataKey="costCents"
                name="Cost"
                stroke="#ff9800"
                fill="url(#cmp-grad-cost)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Paper>
      </Grid.Col>
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p="md" radius="md">
          <Text size="sm" fw={600} mb="md">
            Daily Token Consumption
          </Text>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={costToken.timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="cmp-grad-tokens" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#00bcd4" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#00bcd4" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
              <RechartsTooltip
                contentStyle={chartTooltipStyle}
                formatter={(v) => [formatTokens(Number(v)), 'Tokens']}
              />
              <Area
                type="monotone"
                dataKey="totalTokens"
                name="Tokens"
                stroke="#00bcd4"
                fill="url(#cmp-grad-tokens)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Paper>
      </Grid.Col>
    </Grid>
  );
}

function SourcesPanel() {
  const { sources } = usePage<{ props: Props }>().props as unknown as Props;
  if (!sources) return null;

  const pieData = sources.sources.map((s) => ({ name: s.label, value: s.count }));

  return (
    <Paper withBorder p="md" radius="md" mb="xl">
      <Text size="sm" fw={600} mb="md">
        Sessions by Origin
      </Text>
      <Group gap="lg" align="center">
        <Box style={{ width: '40%' }}>
          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie
                data={pieData}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                outerRadius={80}
                paddingAngle={3}
                label={({ percent = 0 }: { percent?: number }) => `${(percent * 100).toFixed(0)}%`}
                labelLine={false}
              >
                {pieData.map((_, idx) => (
                  <Cell key={idx} fill={SOURCE_COLORS[idx % SOURCE_COLORS.length]} />
                ))}
              </Pie>
              <RechartsTooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${Number(v)} sessions`]} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
            </PieChart>
          </ResponsiveContainer>
        </Box>
        <Box style={{ flex: 1 }}>
          {sources.sources.map((s, idx) => (
            <Group
              key={s.sessionType}
              gap="sm"
              py={8}
              style={{
                borderBottom: idx < sources.sources.length - 1 ? '1px solid var(--mantine-color-dark-4)' : undefined,
              }}
            >
              <Box
                w={10}
                h={10}
                style={{
                  borderRadius: '50%',
                  backgroundColor: SOURCE_COLORS[idx % SOURCE_COLORS.length],
                  flexShrink: 0,
                }}
              />
              <Box style={{ flex: 1 }}>
                <Text size="sm" fw={500}>
                  {s.label}
                </Text>
                <Text size="xs" c="dimmed">
                  {s.count} sessions
                </Text>
              </Box>
            </Group>
          ))}
        </Box>
      </Group>
    </Paper>
  );
}

function DurationPanel() {
  const { duration } = usePage<{ props: Props }>().props as unknown as Props;
  if (!duration) return null;

  return (
    <Paper withBorder p="md" radius="md" mb="xl">
      <Text size="sm" fw={600} mb="md">
        Session Duration Histogram
      </Text>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={duration.buckets} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" vertical={false} />
          <XAxis dataKey="range" tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} />
          <RechartsTooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${Number(v)} sessions`]} />
          <Bar dataKey="count" name="Sessions" fill="#9c27b0" radius={[4, 4, 0, 0]}>
            {duration.buckets.map((_, idx) => (
              <Cell key={idx} fill={`hsl(${280 - idx * 8}, 60%, ${55 - idx * 3}%)`} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </Paper>
  );
}

function WorkflowCostsPanel() {
  const { workflowCosts } = usePage<{ props: Props }>().props as unknown as Props;
  if (!workflowCosts) return null;

  const { totals: wfTotals, workflows: wfWorkflows, timeSeries: wfTimeSeries } = workflowCosts;
  const wfMaxCost = wfWorkflows.length > 0 ? Math.max(...wfWorkflows.map((w) => w.totalCostCents)) : 1;
  const wfTickInterval = wfTimeSeries.length <= 14 ? 0 : wfTimeSeries.length <= 30 ? 4 : 8;
  const totalRuns = wfWorkflows.reduce((sum, w) => sum + w.runCount, 0);
  const totalSecs = wfWorkflows.reduce((sum, w) => sum + w.totalDurationSeconds, 0);
  const avgTimePerWf = totalRuns > 0 ? Math.round(totalSecs / totalRuns) : 0;

  const wfStatBlocks = [
    { label: 'Total Cost', value: formatCostCents(wfTotals.totalCostCents) },
    { label: 'Total Tokens', value: formatTokens(wfTotals.totalTokens) },
    { label: 'Input Tokens', value: formatTokens(wfTotals.inputTokens) },
    { label: 'Output Tokens', value: formatTokens(wfTotals.outputTokens) },
    { label: 'Workflows', value: wfTotals.workflowCount.toLocaleString() },
    { label: 'Avg Cost / Workflow', value: formatCostCents(wfTotals.avgCostCentsPerWorkflow) },
    { label: 'Avg Time / Workflow', value: formatDuration(avgTimePerWf) },
  ];

  return (
    <>
      <SimpleGrid cols={{ base: 2, sm: 4, md: 7 }} mb="xl" spacing="md">
        {wfStatBlocks.map((s) => (
          <Paper key={s.label} withBorder p="lg" radius="md">
            <Text size="xs" c="dimmed" tt="uppercase" mb={10} style={{ letterSpacing: 0.5 }}>
              {s.label}
            </Text>
            <Text fw={700} lh={1.1} style={{ fontSize: 28 }}>
              {s.value}
            </Text>
          </Paper>
        ))}
      </SimpleGrid>

      <Grid mb="xl" gap="md">
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder p="md" radius="md">
            <Text size="sm" fw={600} mb="md">
              Cost Over Time
            </Text>
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={wfTimeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <defs>
                  <linearGradient id="cmp-grad-wf-cost" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#ff9800" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#ff9800" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={wfTickInterval} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
                />
                <Area
                  type="monotone"
                  dataKey="costCents"
                  name="Cost"
                  stroke="#ff9800"
                  fill="url(#cmp-grad-wf-cost)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder p="md" radius="md">
            <Text size="sm" fw={600} mb="md">
              Token Consumption Over Time
            </Text>
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={wfTimeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="cmp-grad-wf-tokens" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#00bcd4" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#00bcd4" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={wfTickInterval} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  formatter={(v) => [formatTokens(Number(v)), 'Tokens']}
                />
                <Area
                  type="monotone"
                  dataKey="totalTokens"
                  name="Tokens"
                  stroke="#00bcd4"
                  fill="url(#cmp-grad-wf-tokens)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
      </Grid>

      <Grid mb="xl" gap="md">
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder p="md" radius="md">
            <Text size="sm" fw={600} mb="md">
              Cost per Workflow
            </Text>
            <ResponsiveContainer width="100%" height={Math.max(220, wfWorkflows.length * 36)}>
              <BarChart
                data={wfWorkflows.map((w, i) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  costCents: w.totalCostCents,
                  color: WORKFLOW_COLORS[i % WORKFLOW_COLORS.length],
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                <XAxis
                  type="number"
                  tick={{ fontSize: 11 }}
                  tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`}
                />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={110} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
                />
                <Bar dataKey="costCents" name="Cost" radius={[0, 4, 4, 0]}>
                  {wfWorkflows.map((_, i) => (
                    <Cell key={i} fill={WORKFLOW_COLORS[i % WORKFLOW_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder p="md" radius="md">
            <Text size="sm" fw={600} mb="md">
              Tokens per Workflow
            </Text>
            <ResponsiveContainer width="100%" height={Math.max(220, wfWorkflows.length * 36)}>
              <BarChart
                data={wfWorkflows.map((w) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  inputTokens: w.inputTokens,
                  outputTokens: w.outputTokens,
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={110} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  formatter={(v, name) => [formatTokens(Number(v)), name as string]}
                />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="inputTokens" name="Input" stackId="tokens" fill="#2196f3" />
                <Bar dataKey="outputTokens" name="Output" stackId="tokens" fill="#9c27b0" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
      </Grid>

      <Paper withBorder p="md" radius="md" mb="xl">
        <Text size="sm" fw={600} mb="md">
          Workflow Breakdown
        </Text>
        {wfWorkflows.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="md">
            No workflow runs in the selected period.
          </Text>
        ) : (
          <>
            <Box
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr 120px 100px 100px 100px 80px 90px 90px',
                gap: 8,
                padding: '8px 0',
                borderBottom: '1px solid var(--mantine-color-dark-4)',
              }}
            >
              {[
                'Workflow',
                'Total Cost',
                'Input Tokens',
                'Output Tokens',
                'Total Tokens',
                'Runs',
                'Avg Time',
                'Total Time',
              ].map((h) => (
                <Text key={h} size="xs" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
                  {h}
                </Text>
              ))}
            </Box>
            {wfWorkflows.map((w, i) => {
              const color = WORKFLOW_COLORS[i % WORKFLOW_COLORS.length];
              const pct = wfMaxCost > 0 ? (w.totalCostCents / wfMaxCost) * 100 : 0;
              return (
                <Box
                  key={w.workflowId}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 120px 100px 100px 100px 80px 90px 90px',
                    gap: 8,
                    alignItems: 'center',
                    padding: '12px 0',
                    borderBottom: i < wfWorkflows.length - 1 ? '1px solid var(--mantine-color-dark-4)' : undefined,
                  }}
                >
                  <Box>
                    <Group gap={8}>
                      <Box w={10} h={10} style={{ borderRadius: '50%', backgroundColor: color, flexShrink: 0 }} />
                      <Text size="sm" fw={500}>
                        {w.workflowName}
                      </Text>
                    </Group>
                    <Box
                      mt={4}
                      style={{
                        width: '80%',
                        height: 4,
                        borderRadius: 2,
                        backgroundColor: 'var(--mantine-color-dark-5)',
                      }}
                    >
                      <Box style={{ height: 4, borderRadius: 2, backgroundColor: color, width: `${pct}%` }} />
                    </Box>
                  </Box>
                  <Text size="sm" fw={600}>
                    {formatCostCents(w.totalCostCents)}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {formatTokens(w.inputTokens)}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {formatTokens(w.outputTokens)}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {formatTokens(w.totalTokens)}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {w.runCount}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {formatDuration(w.avgDurationSeconds)}
                  </Text>
                  <Text size="sm" c="dimmed">
                    {formatDuration(w.totalDurationSeconds)}
                  </Text>
                </Box>
              );
            })}
          </>
        )}
      </Paper>
    </>
  );
}

// --- Main page ---

const AnalyticsPage = () => {
  const { scope, period } = usePage<{ props: Props }>().props as unknown as Props;
  const tickInterval = useMemo(() => tickIntervalForPeriod(period), [period]);

  return (
    <AuthLayout>
      <Head title="Company Analytics" />

      <Group justify="space-between" mb="xl" wrap="wrap">
        <Box>
          <Text size="xl" fw={700}>
            Analytics
          </Text>
          <Text size="sm" c="dimmed">
            Company-wide agent activity, costs, and session insights
          </Text>
        </Box>
        <Group gap="sm">
          <Select
            value={period}
            onChange={(v) => navigateWithFilters(scope, v ?? '30d')}
            data={PERIOD_OPTIONS}
            size="sm"
            w={140}
          />
        </Group>
      </Group>

      {/* Summary Stats */}
      <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} mb="xl" spacing="md">
        <Deferred data="summary" fallback={<SummarySkeletons />}>
          <SummaryPanel />
        </Deferred>
      </SimpleGrid>

      {/* Per-Project Breakdown */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Projects Overview
      </Text>
      <Deferred data="summary" fallback={<Skeleton height={200} radius="sm" mb="xl" />}>
        <ProjectBreakdownPanel />
      </Deferred>

      {/* Agent Activity */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Agent Activity
      </Text>
      <Deferred
        data="agentActivity"
        fallback={
          <Grid mb="xl" gap="md">
            <Grid.Col span={{ base: 12, md: 6 }}>
              <ChartSkeleton />
            </Grid.Col>
            <Grid.Col span={{ base: 12, md: 6 }}>
              <ChartSkeleton height={200} />
            </Grid.Col>
          </Grid>
        }
      >
        <AgentActivityPanel tickInterval={tickInterval} />
      </Deferred>

      {/* Cost & Token Usage */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Cost & Token Usage
      </Text>
      <Deferred
        data="costToken"
        fallback={
          <Grid mb="xl" gap="md">
            <Grid.Col span={{ base: 12, md: 6 }}>
              <ChartSkeleton height={220} />
            </Grid.Col>
            <Grid.Col span={{ base: 12, md: 6 }}>
              <ChartSkeleton height={220} />
            </Grid.Col>
          </Grid>
        }
      >
        <CostTokenPanel tickInterval={tickInterval} />
      </Deferred>

      {/* Session Source Breakdown */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Session Source Breakdown
      </Text>
      <Deferred data="sources" fallback={<ChartSkeleton height={200} />}>
        <SourcesPanel />
      </Deferred>

      {/* Session Duration Distribution */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Session Duration Distribution
      </Text>
      <Deferred data="duration" fallback={<ChartSkeleton height={220} />}>
        <DurationPanel />
      </Deferred>

      {/* Workflow Costs */}
      <Text size="md" fw={600} mb="md" mt="xl">
        Workflow Costs
      </Text>
      <Deferred data="workflowCosts" fallback={<WorkflowCostSkeletons />}>
        <WorkflowCostsPanel />
      </Deferred>
    </AuthLayout>
  );
};

export default AnalyticsPage;
