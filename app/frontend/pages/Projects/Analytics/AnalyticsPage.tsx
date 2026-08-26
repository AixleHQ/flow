import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Box, Grid, Group, Paper, SegmentedControl, Select, SimpleGrid, Skeleton, Text } from '@mantine/core';
import {
  IconCalendarStats,
  IconChartAreaLine,
  IconChartBar,
  IconChartPie,
  IconClock,
  IconCoin,
  IconGitBranch,
  IconPlayerPlay,
  IconRobot,
  IconRoute,
} from '@tabler/icons-react';
import { type ComponentType, type ReactNode, useEffect, useMemo, useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from 'recharts';

import {
  AgentLogo,
  buildActivityChartData,
  centerLabelFontSize,
  CHART_ACCENT,
  CHART_NEUTRAL,
  CHART_TAUPE,
  ChartSkeleton,
  chartTooltipStyle,
  formatAxisDate,
  getAgentColor,
  type AgentActivityData,
  type Period,
  PERIOD_OPTIONS,
  ScopeBadge,
  sharePct,
  SummarySkeletons,
  tickIntervalForPeriod,
} from 'shared/analytics/chartHelpers';
import { formatCostCents, formatTokens } from 'shared/lib/formatUsage';
import { ContributionHeatmap } from 'shared/ui/ContributionHeatmap';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Participant {
  id: number;
  name: string | null;
  email: string;
}

interface HeatmapData {
  days: { date: string; count: number }[];
}

type Scope = 'project' | 'user';
type UsageScope = 'all' | 'workflows';

interface SummaryData {
  totalSessions: number;
  totalCostCents: number;
  totalTokens: number;
  avgCostCentsPerSession: number;
  workflowsRun: number;
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
  project: Project;
  scope: Scope;
  period: Period;
  participantId?: string | null;
  participants: Participant[];
  summary?: SummaryData;
  agentActivity?: AgentActivityData;
  sources?: SourceData;
  duration?: DurationData;
  costToken?: CostTokenData;
  workflowCosts?: WorkflowCostData;
  activityHeatmap?: HeatmapData;
}

// Same warm rota as AGENT_COLOR, applied by rank (highest-cost workflow first) so the
// per-workflow dot/bar/progress-bar color stays consistent across the table and both charts.
const WORKFLOW_PALETTE = [CHART_ACCENT, CHART_TAUPE, 'var(--app-chart-warm-2)', 'var(--app-chart-warm-3)'];
const getWorkflowColor = (index: number): string => WORKFLOW_PALETTE[index % WORKFLOW_PALETTE.length];

// Section heading with a leading muted icon, matching the design's `sec-head` pattern.
// `right` renders an optional control (e.g. a scope switcher) flush to the right edge.
function SectionHeading({
  icon: Icon,
  right,
  children,
}: {
  icon: ComponentType<{ size?: number; color?: string; stroke?: number }>;
  right?: ReactNode;
  children: ReactNode;
}) {
  return (
    <Group justify="space-between" mb="md" mt="xl">
      <Group gap={8}>
        <Icon size={16} color="var(--app-text-tertiary)" stroke={1.75} />
        <Text size="sm" fw={600}>
          {children}
        </Text>
      </Group>
      {right}
    </Group>
  );
}

// Small uppercase pill used to show the active data scope in a chart card's corner.
function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return '0s';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function navigateWithFilters(scope: string, period: string, participantId?: string | null) {
  router.get(
    window.location.pathname,
    { scope, period, ...(participantId ? { participant_id: participantId } : {}) },
    { preserveState: true, preserveScroll: true },
  );
}

// --- Skeleton blocks for deferred fallbacks ---

function WorkflowCostSkeletons() {
  return (
    <>
      <SimpleGrid cols={{ base: 2, sm: 4, md: 6 }} mb="xl" spacing="md">
        {Array.from({ length: 6 }).map((_, i) => (
          <Paper key={i} withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
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

// --- Data panels (read data from usePage) ---

function SummaryPanel() {
  const { summary } = usePage<{ props: Props }>().props as unknown as Props;
  if (!summary) return null;

  const statBlocks = [
    { label: 'Total Sessions', value: summary.totalSessions.toLocaleString(), icon: IconPlayerPlay },
    { label: 'Total Cost', value: formatCostCents(summary.totalCostCents), icon: IconCoin },
    { label: 'Total Tokens', value: formatTokens(summary.totalTokens), icon: IconChartBar },
    { label: 'Avg Cost / Session', value: formatCostCents(summary.avgCostCentsPerSession), icon: IconClock },
    { label: 'Workflows Run', value: summary.workflowsRun.toLocaleString(), icon: IconRoute },
  ];

  return (
    <>
      {statBlocks.map((s) => (
        <Paper key={s.label} withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
          <Group gap={6} mb={12}>
            <s.icon size={13} color="var(--app-text-tertiary)" />
            <Text c="dimmed" tt="uppercase" fw={600} style={{ fontSize: 10, letterSpacing: '0.06em' }}>
              {s.label}
            </Text>
          </Group>
          <Text fw={500} lh={1} style={{ fontSize: 24, letterSpacing: '-0.02em', fontFamily: 'var(--app-font-mono)' }}>
            {s.value}
          </Text>
        </Paper>
      ))}
    </>
  );
}

function AgentActivityPanel({ tickInterval }: { tickInterval: number }) {
  const { agentActivity } = usePage<{ props: Props }>().props as unknown as Props;
  if (!agentActivity) return null;

  const activityChartData = buildActivityChartData(agentActivity);
  const { agentTypes, sessionsByAgent } = agentActivity;
  const totalAgentSessions = sessionsByAgent.reduce((sum, a) => sum + a.sessions, 0);

  return (
    <Grid mb="xl" gap="md">
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" h="100%">
          <Text size="sm" fw={600} mb="md">
            Sessions per agent — trend
          </Text>
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={activityChartData} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} />
              <YAxis tick={{ fontSize: 11 }} />
              <RechartsTooltip contentStyle={chartTooltipStyle} />
              {agentTypes.map((agentType) => (
                <Line
                  key={agentType}
                  type="monotone"
                  dataKey={agentType}
                  name={agentType}
                  stroke={getAgentColor(agentType)}
                  strokeWidth={2}
                  dot={false}
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
          <Group gap="md" justify="flex-start" mt="xs" wrap="wrap">
            {agentTypes.map((agentType) => (
              <Group key={agentType} gap={6} wrap="nowrap">
                <Box w={12} h={2} style={{ borderRadius: 1, backgroundColor: getAgentColor(agentType) }} />
                <AgentLogo agentType={agentType} size={15} />
                <Text size="xs" c="dimmed">
                  {agentType}
                </Text>
              </Group>
            ))}
          </Group>
        </Paper>
      </Grid.Col>

      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" h="100%">
          <Text size="sm" fw={600} mb="md">
            Usage breakdown by agent type
          </Text>
          <Group gap={28} align="center" wrap="nowrap">
            <Box w={150} h={150} style={{ position: 'relative', flexShrink: 0 }}>
              <ResponsiveContainer width="100%" height={150}>
                <PieChart>
                  <Pie
                    data={sessionsByAgent}
                    dataKey="sessions"
                    nameKey="agentType"
                    cx="50%"
                    cy="50%"
                    innerRadius={42}
                    outerRadius={62}
                    paddingAngle={3}
                  >
                    {sessionsByAgent.map((entry) => (
                      <Cell key={entry.agentType} fill={getAgentColor(entry.agentType)} />
                    ))}
                  </Pie>
                  <RechartsTooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${Number(v)} sessions`]} />
                </PieChart>
              </ResponsiveContainer>
              <Box
                style={{
                  position: 'absolute',
                  inset: 0,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  pointerEvents: 'none',
                }}
              >
                <Text fw={500} lh={1.1} style={{ fontSize: centerLabelFontSize(totalAgentSessions) }}>
                  {totalAgentSessions.toLocaleString()}
                </Text>
                <Text c="dimmed" tt="uppercase" style={{ fontSize: 10, letterSpacing: '0.06em' }}>
                  sessions
                </Text>
              </Box>
            </Box>
            <Box style={{ flex: 1 }}>
              {sessionsByAgent.map((agent, idx) => (
                <Group
                  key={agent.agentType}
                  gap="sm"
                  py={8}
                  style={{
                    borderBottom: idx < sessionsByAgent.length - 1 ? '1px solid var(--app-border-default)' : undefined,
                  }}
                >
                  <Box
                    w={10}
                    h={10}
                    style={{ borderRadius: '50%', backgroundColor: getAgentColor(agent.agentType), flexShrink: 0 }}
                  />
                  <AgentLogo agentType={agent.agentType} />
                  <Box style={{ flex: 1 }}>
                    <Text size="xs" fw={500}>
                      {agent.agentType}
                    </Text>
                    <Text size="xs" c="dimmed">
                      {agent.sessions} {agent.sessions === 1 ? 'session' : 'sessions'} ·{' '}
                      {sharePct(agent.sessions, totalAgentSessions)}%
                    </Text>
                  </Box>
                  <Text fw={500} style={{ fontSize: 13, fontFamily: 'var(--app-font-mono)' }}>
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

function CostTokenPanel({ tickInterval, usageScope }: { tickInterval: number; usageScope: UsageScope }) {
  const { costToken, workflowCosts } = usePage<{ props: Props }>().props as unknown as Props;
  if (!costToken) return null;

  // All-sessions series buckets on terminal_sessions.created_at; workflow-only buckets on
  // workflow_runs.created_at — the same underlying spend can land on different dates when toggling.
  const scopeLabel = usageScope === 'workflows' ? 'Workflows only' : 'All sessions';
  const timeSeries = usageScope === 'workflows' ? (workflowCosts?.timeSeries ?? []) : costToken.timeSeries;

  return (
    <Grid mb="xl" gap="md">
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper
          withBorder
          px={20}
          py={18}
          radius="md"
          bg="var(--app-bg-card)"
          data-testid="daily-cost-panel"
          data-first-cost-cents={timeSeries[0]?.costCents ?? 0}
        >
          <Group justify="space-between" mb="md">
            <Text size="sm" fw={600}>
              Daily cost
            </Text>
            <ScopeBadge>{scopeLabel}</ScopeBadge>
          </Group>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <defs>
                <linearGradient id="grad-cost" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={CHART_ACCENT} stopOpacity={0.3} />
                  <stop offset="95%" stopColor={CHART_ACCENT} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} tickFormatter={formatAxisDate} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`} />
              <RechartsTooltip
                contentStyle={chartTooltipStyle}
                labelFormatter={formatAxisDate}
                formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
              />
              <Area
                type="monotone"
                dataKey="costCents"
                name="Cost"
                stroke={CHART_ACCENT}
                fill="url(#grad-cost)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Paper>
      </Grid.Col>
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
          <Group justify="space-between" mb="md">
            <Text size="sm" fw={600}>
              Daily token consumption
            </Text>
            <ScopeBadge>{scopeLabel}</ScopeBadge>
          </Group>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="grad-tokens" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={CHART_TAUPE} stopOpacity={0.3} />
                  <stop offset="95%" stopColor={CHART_TAUPE} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
              <XAxis dataKey="date" tick={{ fontSize: 11 }} interval={tickInterval} tickFormatter={formatAxisDate} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
              <RechartsTooltip
                contentStyle={chartTooltipStyle}
                labelFormatter={formatAxisDate}
                formatter={(v) => [formatTokens(Number(v)), 'Tokens']}
              />
              <Area
                type="monotone"
                dataKey="totalTokens"
                name="Tokens"
                stroke={CHART_TAUPE}
                fill="url(#grad-tokens)"
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

  const totalSessions = sources.sources.reduce((sum, s) => sum + s.count, 0);
  // Backend already orders rows by count DESC, so the first row is the dominant source.
  const topSource = sources.sources[0];

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" h="100%">
      <Text size="sm" fw={600} mb="md">
        Sessions by origin
      </Text>
      <Group gap={28} align="center" wrap="nowrap">
        <Box w={150} h={150} style={{ position: 'relative', flexShrink: 0 }}>
          <ResponsiveContainer width="100%" height={150}>
            <PieChart>
              <Pie
                data={sources.sources}
                dataKey="count"
                nameKey="label"
                cx="50%"
                cy="50%"
                innerRadius={42}
                outerRadius={62}
                paddingAngle={3}
              >
                {sources.sources.map((s, idx) => (
                  <Cell key={s.sessionType} fill={idx === 0 ? CHART_ACCENT : CHART_NEUTRAL} />
                ))}
              </Pie>
              <RechartsTooltip contentStyle={chartTooltipStyle} formatter={(v) => [`${Number(v)} sessions`]} />
            </PieChart>
          </ResponsiveContainer>
          {topSource && (
            <Box
              style={{
                position: 'absolute',
                inset: 0,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                pointerEvents: 'none',
              }}
            >
              <Text fw={500} lh={1.1} style={{ fontSize: 18, fontFamily: 'var(--app-font-mono)' }}>
                {sharePct(topSource.count, totalSessions)}%
              </Text>
              <Text
                c="dimmed"
                tt="uppercase"
                ta="center"
                lh={1.15}
                style={{ fontSize: 10, letterSpacing: '0.06em', maxWidth: 70, wordBreak: 'break-word' }}
              >
                {topSource.label}
              </Text>
            </Box>
          )}
        </Box>
        <Box style={{ flex: 1 }}>
          {sources.sources.map((s, idx) => (
            <Group
              key={s.sessionType}
              gap="sm"
              py={8}
              style={{
                borderBottom: idx < sources.sources.length - 1 ? '1px solid var(--app-border-default)' : undefined,
              }}
            >
              <Box
                w={10}
                h={10}
                style={{
                  borderRadius: '50%',
                  backgroundColor: idx === 0 ? CHART_ACCENT : CHART_NEUTRAL,
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
              <Text fw={500} style={{ fontSize: 13, fontFamily: 'var(--app-font-mono)' }}>
                {sharePct(s.count, totalSessions)}%
              </Text>
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
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" h="100%">
      <Text size="sm" fw={600} mb="md">
        Session duration distribution
      </Text>
      <ResponsiveContainer width="100%" height={220}>
        <BarChart data={duration.buckets} margin={{ top: 4, right: 8, bottom: 0, left: -10 }} barCategoryGap="35%">
          <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" vertical={false} />
          <XAxis dataKey="range" tick={{ fontSize: 11 }} />
          <YAxis tick={{ fontSize: 11 }} />
          <RechartsTooltip
            contentStyle={chartTooltipStyle}
            formatter={(v) => [`${Number(v)} sessions`]}
            cursor={false}
          />
          <Bar dataKey="count" name="Sessions" fill={CHART_ACCENT} radius={[4, 4, 0, 0]} maxBarSize={56} />
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
    { label: 'Avg Cost / Workflow', value: formatCostCents(wfTotals.avgCostCentsPerWorkflow) },
    { label: 'Avg Time / Workflow', value: formatDuration(avgTimePerWf) },
  ];

  return (
    <>
      <Paper withBorder radius="md" mb="xl" bg="var(--app-bg-card)" style={{ overflow: 'hidden' }}>
        <SimpleGrid cols={{ base: 2, sm: 3, md: 6 }} spacing={0}>
          {wfStatBlocks.map((s, i) => (
            <Box
              key={s.label}
              px={16}
              py={14}
              style={{ borderLeft: i === 0 ? undefined : '1px solid var(--app-border-default)' }}
            >
              <Text c="dimmed" tt="uppercase" fw={600} mb={8} style={{ fontSize: 10, letterSpacing: '0.06em' }}>
                {s.label}
              </Text>
              <Text fw={500} style={{ fontSize: 17, letterSpacing: '-0.01em', fontFamily: 'var(--app-font-mono)' }}>
                {s.value}
              </Text>
            </Box>
          ))}
        </SimpleGrid>
      </Paper>

      <Grid mb="xl" gap="md">
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
            <Text size="sm" fw={600} mb="md">
              Cost Over Time
            </Text>
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={wfTimeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
                <defs>
                  <linearGradient id="grad-wf-cost" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={CHART_ACCENT} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={CHART_ACCENT} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 11 }}
                  interval={wfTickInterval}
                  tickFormatter={formatAxisDate}
                />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  labelFormatter={formatAxisDate}
                  formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
                />
                <Area
                  type="monotone"
                  dataKey="costCents"
                  name="Cost"
                  stroke={CHART_ACCENT}
                  fill="url(#grad-wf-cost)"
                  strokeWidth={2}
                  dot={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
            <Text size="sm" fw={600} mb="md">
              Token Consumption Over Time
            </Text>
            <ResponsiveContainer width="100%" height={220}>
              <AreaChart data={wfTimeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="grad-wf-tokens" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={CHART_TAUPE} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={CHART_TAUPE} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 11 }}
                  interval={wfTickInterval}
                  tickFormatter={formatAxisDate}
                />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  labelFormatter={formatAxisDate}
                  formatter={(v) => [formatTokens(Number(v)), 'Tokens']}
                />
                <Area
                  type="monotone"
                  dataKey="totalTokens"
                  name="Tokens"
                  stroke={CHART_TAUPE}
                  fill="url(#grad-wf-tokens)"
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
          <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
            <Text size="sm" fw={600} mb="md">
              Cost per workflow
            </Text>
            <ResponsiveContainer width="100%" height={Math.max(150, wfWorkflows.length * 56 + 40)}>
              <BarChart
                data={wfWorkflows.map((w) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  costCents: w.totalCostCents,
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" horizontal={false} />
                <XAxis
                  type="number"
                  tick={{ fontSize: 11 }}
                  tickFormatter={(v: number) => `$${(v / 100).toFixed(0)}`}
                />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={140} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  itemStyle={{ color: 'var(--app-text-primary)' }}
                  formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
                  cursor={false}
                />
                <Bar dataKey="costCents" name="Cost" radius={[0, 4, 4, 0]} maxBarSize={28}>
                  {wfWorkflows.map((w, i) => (
                    <Cell key={w.workflowId} fill={getWorkflowColor(i)} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
            <Group justify="space-between" mb="md">
              <Text size="sm" fw={600}>
                Tokens per workflow
              </Text>
              <Group gap={14}>
                <Group gap={5}>
                  <Box w={9} h={9} style={{ borderRadius: 2, backgroundColor: CHART_TAUPE, flexShrink: 0 }} />
                  <Text c="dimmed" style={{ fontSize: 11 }}>
                    Input
                  </Text>
                </Group>
                <Group gap={5}>
                  <Box w={9} h={9} style={{ borderRadius: 2, backgroundColor: CHART_ACCENT, flexShrink: 0 }} />
                  <Text c="dimmed" style={{ fontSize: 11 }}>
                    Output
                  </Text>
                </Group>
              </Group>
            </Group>
            <ResponsiveContainer width="100%" height={Math.max(150, wfWorkflows.length * 56 + 40)}>
              <BarChart
                data={wfWorkflows.map((w) => ({
                  name: w.workflowName.length > 18 ? w.workflowName.slice(0, 16) + '…' : w.workflowName,
                  inputTokens: w.inputTokens,
                  outputTokens: w.outputTokens,
                }))}
                layout="vertical"
                margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} tickFormatter={(v: number) => formatTokens(v)} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={140} />
                <RechartsTooltip
                  contentStyle={chartTooltipStyle}
                  formatter={(v, name) => [formatTokens(Number(v)), name as string]}
                  cursor={false}
                />
                <Bar dataKey="inputTokens" name="Input" stackId="tokens" fill={CHART_TAUPE} maxBarSize={28} />
                <Bar
                  dataKey="outputTokens"
                  name="Output"
                  stackId="tokens"
                  fill={CHART_ACCENT}
                  radius={[0, 4, 4, 0]}
                  maxBarSize={28}
                />
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid.Col>
      </Grid>

      <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" mb="xl">
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
                borderBottom: '1px solid var(--app-border-default)',
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
              const color = getWorkflowColor(i);
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
                    borderBottom: i < wfWorkflows.length - 1 ? '1px solid var(--app-border-default)' : undefined,
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
                        backgroundColor: 'var(--app-bg-elevated)',
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

function HeatmapPanel() {
  const { activityHeatmap } = usePage<{ props: Props }>().props as unknown as Props;
  if (!activityHeatmap) return null;

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" mb="xl">
      <ContributionHeatmap days={activityHeatmap.days} />
    </Paper>
  );
}

// --- Main page ---

const AnalyticsPage = () => {
  const { project, scope, period, participantId, participants } = usePage<{ props: Props }>().props as unknown as Props;
  const tickInterval = useMemo(() => tickIntervalForPeriod(period), [period]);
  const [usageScope, setUsageScope] = useState<UsageScope>('all');

  useEffect(() => {
    setUsageScope('all');
  }, [period, scope, participantId]);

  const participantOptions = (participants ?? []).map((p) => ({
    value: String(p.id),
    label: p.name ?? p.email,
  }));

  return (
    <Box style={{ maxWidth: 1320, margin: '0 auto' }}>
      <Head title={`Analytics — ${project.name}`} />

      {/* Row 1: title only */}
      <PageHeader title="Analytics" subtitle="Agent activity, costs, and session insights" mb={16} />

      {/* Row 2: toolbar — tabs left, filters right */}
      <Group mb="xl" gap="sm" wrap="wrap">
        <SegmentedControl
          value={scope}
          onChange={(v) => navigateWithFilters(v, period, participantId)}
          data={[
            { label: 'Project', value: 'project' },
            { label: 'My Activity', value: 'user' },
          ]}
          size="sm"
        />
        <Group gap="sm" ml="auto">
          <Select
            placeholder="All participants"
            value={participantId ?? null}
            onChange={(v) => navigateWithFilters(scope, period, v)}
            data={participantOptions}
            clearable
            size="sm"
            w={180}
          />
          <Select
            value={period}
            onChange={(v) => navigateWithFilters(scope, v ?? '30d', participantId)}
            data={PERIOD_OPTIONS}
            size="sm"
            w={140}
          />
        </Group>
      </Group>

      {/* Summary Stats */}
      <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} mb="xl" spacing="sm">
        <Deferred data="summary" fallback={<SummarySkeletons />}>
          <SummaryPanel />
        </Deferred>
      </SimpleGrid>

      {/* Activity */}
      <SectionHeading icon={IconCalendarStats}>Activity</SectionHeading>
      <Deferred data="activityHeatmap" fallback={<Skeleton height={140} radius="sm" mb="xl" />}>
        <HeatmapPanel />
      </Deferred>

      {/* Agent Activity */}
      <SectionHeading icon={IconRobot}>Agent activity</SectionHeading>
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
      <SectionHeading
        icon={IconChartAreaLine}
        right={
          <SegmentedControl
            value={usageScope}
            onChange={(v) => setUsageScope(v as UsageScope)}
            data={[
              { label: 'All sessions', value: 'all' },
              { label: 'Workflows only', value: 'workflows' },
            ]}
            size="xs"
          />
        }
      >
        Cost & token usage
      </SectionHeading>
      <Deferred
        data={['costToken', 'workflowCosts']}
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
        <CostTokenPanel tickInterval={tickInterval} usageScope={usageScope} />
      </Deferred>

      {/* Session insights (merged: origin + duration) */}
      <SectionHeading icon={IconChartPie}>Session insights</SectionHeading>
      <Grid mb="xl" gap="md">
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Deferred data="sources" fallback={<ChartSkeleton height={200} />}>
            <SourcesPanel />
          </Deferred>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 6 }}>
          <Deferred data="duration" fallback={<ChartSkeleton height={220} />}>
            <DurationPanel />
          </Deferred>
        </Grid.Col>
      </Grid>

      {/* Workflow Costs */}
      <SectionHeading icon={IconGitBranch}>Workflow costs</SectionHeading>
      <Deferred data="workflowCosts" fallback={<WorkflowCostSkeletons />}>
        <WorkflowCostsPanel />
      </Deferred>
    </Box>
  );
};

setPageLayout(AnalyticsPage, persistentProjectLayout);

export default AnalyticsPage;
