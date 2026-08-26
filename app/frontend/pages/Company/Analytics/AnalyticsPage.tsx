import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Box, Grid, Group, Paper, SegmentedControl, Select, SimpleGrid, Skeleton, Text } from '@mantine/core';
import { IconChartBar, IconClock, IconCoin, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
import { useEffect, useMemo, useState } from 'react';
import {
  Area,
  AreaChart,
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

import { AuthLayout } from 'layouts/AuthLayout';

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
import { PageHeader } from 'shared/ui/PageHeader';

type Scope = 'company' | 'user';
type UsageScope = 'all' | 'workflows';

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

interface SourceRow {
  sessionType: string;
  label: string;
  count: number;
}
interface SourceData {
  sources: SourceRow[];
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

// Only the time series is fetched here — unlike the project page, there's no per-workflow
// breakdown table on this page, just the "Workflows only" scope for the Cost & Token charts.
interface WorkflowCostData {
  timeSeries: CostTokenPoint[];
}

interface Props {
  scope: Scope;
  period: Period;
  summary?: SummaryData;
  agentActivity?: AgentActivityData;
  sources?: SourceData;
  costToken?: CostTokenData;
  workflowCosts?: WorkflowCostData;
}

function navigateWithFilters(scope: string, period: string) {
  router.get(window.location.pathname, { scope, period }, { preserveState: true, preserveScroll: true });
}

// --- Data panels ---

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

function ProjectBreakdownPanel() {
  const { summary } = usePage<{ props: Props }>().props as unknown as Props;
  if (!summary || !summary.projectBreakdowns || summary.projectBreakdowns.length === 0) return null;

  const { projectBreakdowns } = summary;
  const maxCost = projectBreakdowns.length > 0 ? Math.max(...projectBreakdowns.map((p) => p.costCents)) : 1;

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" mb="xl">
      <Text size="sm" fw={600} mb="md">
        Per-Project Breakdown
      </Text>
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 100px 130px 120px',
          gap: 8,
          padding: '8px 0',
          borderBottom: '1px solid var(--app-border-default)',
        }}
      >
        {['Project', 'Sessions', 'Cost', 'Tokens'].map((h) => (
          <Text key={h} size="xs" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
            {h}
          </Text>
        ))}
      </Box>
      {projectBreakdowns.map((p, i) => {
        const color = CHART_ACCENT;
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
              borderBottom: i < projectBreakdowns.length - 1 ? '1px solid var(--app-border-default)' : undefined,
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
                  backgroundColor: 'var(--app-bg-elevated)',
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
                <linearGradient id="cmp-grad-cost" x1="0" y1="0" x2="0" y2="1">
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
                fill="url(#cmp-grad-cost)"
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
                <linearGradient id="cmp-grad-tokens" x1="0" y1="0" x2="0" y2="1">
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

  const totalSessions = sources.sources.reduce((sum, s) => sum + s.count, 0);
  // Backend already orders rows by count DESC, so the first row is the dominant source.
  const topSource = sources.sources[0];

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" mb="xl">
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

// --- Main page ---

const AnalyticsPage = () => {
  const { scope, period } = usePage<{ props: Props }>().props as unknown as Props;
  const tickInterval = useMemo(() => tickIntervalForPeriod(period), [period]);
  const [usageScope, setUsageScope] = useState<UsageScope>('all');
  const pageSubtitle =
    scope === 'user'
      ? 'Your agent activity, costs, and session insights across the company'
      : 'Company-wide agent activity, costs, and session insights';

  useEffect(() => {
    setUsageScope('all');
  }, [period, scope]);

  return (
    <AuthLayout>
      <Head title="Company Analytics" />

      <Box style={{ maxWidth: 1320, margin: '0 auto' }}>
        {/* Row 1: title only */}
        <PageHeader title="Analytics" subtitle={pageSubtitle} mb={16} />

        {/* Row 2: toolbar — scope tabs left, period filter right */}
        <Group mb="xl" gap="sm" wrap="wrap">
          <SegmentedControl
            value={scope}
            onChange={(v) => navigateWithFilters(v, period)}
            data={[
              { label: 'Company', value: 'company' },
              { label: 'My activity', value: 'user' },
            ]}
            size="sm"
          />
          <Group gap="sm" ml="auto">
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
        <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} mb="xl" spacing="sm">
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
          Agent activity
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
        <Group justify="space-between" mb="md" mt="xl">
          <Text size="md" fw={600}>
            Cost & token usage
          </Text>
          <SegmentedControl
            value={usageScope}
            onChange={(v) => setUsageScope(v as UsageScope)}
            data={[
              { label: 'All sessions', value: 'all' },
              { label: 'Workflows only', value: 'workflows' },
            ]}
            size="xs"
          />
        </Group>
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

        {/* Session insights (company scope: origin only — no duration histogram) */}
        <Text size="md" fw={600} mb="md" mt="xl">
          Session insights
        </Text>
        <Deferred data="sources" fallback={<ChartSkeleton height={200} />}>
          <SourcesPanel />
        </Deferred>
      </Box>
    </AuthLayout>
  );
};

export default AnalyticsPage;
