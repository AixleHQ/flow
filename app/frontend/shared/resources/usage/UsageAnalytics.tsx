import { Deferred, usePage } from '@inertiajs/react';
import { Box, Divider, Grid, Group, Paper, SimpleGrid, Skeleton, Text, Title } from '@mantine/core';
import { IconChartBar, IconClock, IconCoin, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
import { useMemo } from 'react';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { formatCostCents, formatTokens } from 'shared/lib/formatUsage';
import { CHART_SERIES } from 'shared/theme/chartPalette';
import { ContributionHeatmap } from 'shared/ui/ContributionHeatmap';

/**
 * Cross-project agent activity for ONE person in ONE company: the heatmap,
 * the five headline numbers, the per-project split, the agent mix and the daily
 * cost/token curves.
 *
 * Lives in shared because two pages render exactly this block — the owner's own
 * Profile -> Usage, and a colleague's organization-visible profile at
 * /user/:id. Each panel reads its own deferred prop off usePage(), so a page
 * opts in simply by serving props under these names; the panels render nothing
 * until their prop arrives.
 */

export type Period = '7d' | '30d' | '90d' | '1y';

interface ProjectBreakdown {
  projectId: number | null;
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
interface AgentActivityData {
  sessionsByAgent: AgentSessionCount[];
}

interface CostTokenPoint {
  date: string;
  costCents: number;
  totalTokens: number;
}
interface CostTokenData {
  timeSeries: CostTokenPoint[];
}

interface HeatmapData {
  days: { date: string; count: number }[];
}

/** The deferred props each panel reads off the page it is rendered on. */
interface AnalyticsProps {
  summary?: SummaryData;
  agentActivity?: AgentActivityData;
  costToken?: CostTokenData;
  activityHeatmap?: HeatmapData;
}

const AGENT_COLORS = CHART_SERIES;
const PROJECT_COLORS = CHART_SERIES;
const getAgentColor = (i: number) => AGENT_COLORS[i % AGENT_COLORS.length];

export const PERIOD_OPTIONS = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' },
  { value: '1y', label: 'Last year' },
];

const chartTooltipStyle = {
  backgroundColor: 'var(--app-bg-default)',
  border: '1px solid var(--app-border-default)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--app-text-primary)',
};

function tickIntervalForPeriod(period: Period): number {
  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  return days <= 7 ? 0 : days <= 30 ? 4 : days <= 90 ? 9 : 29;
}

// --- Skeletons ---

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

// --- Panels ---

function HeatmapPanel() {
  const { activityHeatmap } = usePage<{ props: AnalyticsProps }>().props as unknown as AnalyticsProps;
  if (!activityHeatmap) return null;

  return (
    <Paper withBorder p={24} radius="md" bg="var(--app-bg-card)" mb="xl">
      <ContributionHeatmap days={activityHeatmap.days} />
    </Paper>
  );
}

function SummaryPanel() {
  const { summary } = usePage<{ props: AnalyticsProps }>().props as unknown as AnalyticsProps;
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
  const { summary } = usePage<{ props: AnalyticsProps }>().props as unknown as AnalyticsProps;
  if (!summary || !summary.projectBreakdowns || summary.projectBreakdowns.length === 0) return null;

  const { projectBreakdowns } = summary;
  const maxCost = projectBreakdowns.length > 0 ? Math.max(...projectBreakdowns.map((p) => p.costCents)) : 1;

  return (
    <Paper withBorder p={24} radius="md" mb="xl">
      <Title order={4} mb={4}>
        Per-Project Breakdown
      </Title>
      <Divider mb="md" />
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
        const color = PROJECT_COLORS[i % PROJECT_COLORS.length];
        const pct = maxCost > 0 ? (p.costCents / maxCost) * 100 : 0;
        return (
          <Box
            key={p.projectId ?? 'none'}
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
                style={{ width: '80%', height: 4, borderRadius: 2, backgroundColor: 'var(--app-bg-elevated)' }}
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

function AgentActivityPanel() {
  const { agentActivity } = usePage<{ props: AnalyticsProps }>().props as unknown as AnalyticsProps;
  if (!agentActivity) return null;

  const { sessionsByAgent } = agentActivity;

  return (
    <Paper withBorder p={24} radius="md" mb="xl">
      <Title order={4} mb={4}>
        Usage Breakdown by Agent Type
      </Title>
      <Divider mb="md" />
      <Group gap="lg" align="center">
        <Box style={{ width: '40%' }}>
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
                borderBottom: idx < sessionsByAgent.length - 1 ? '1px solid var(--app-border-default)' : undefined,
              }}
            >
              <Box w={10} h={10} style={{ borderRadius: '50%', backgroundColor: getAgentColor(idx), flexShrink: 0 }} />
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
  );
}

function CostTokenPanel({ tickInterval }: { tickInterval: number }) {
  const { costToken } = usePage<{ props: AnalyticsProps }>().props as unknown as AnalyticsProps;
  if (!costToken) return null;

  return (
    <Grid mb="xl" gap="md">
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p={24} radius="md">
          <Title order={4} mb={4}>
            Daily Cost
          </Title>
          <Divider mb="md" />
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={costToken.timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: -10 }}>
              <defs>
                <linearGradient id="usage-grad-cost" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--app-chart-1)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--app-chart-1)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
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
                stroke="var(--app-chart-1)"
                fill="url(#usage-grad-cost)"
                strokeWidth={2}
                dot={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Paper>
      </Grid.Col>
      <Grid.Col span={{ base: 12, md: 6 }}>
        <Paper withBorder p={24} radius="md">
          <Title order={4} mb={4}>
            Daily Token Consumption
          </Title>
          <Divider mb="md" />
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={costToken.timeSeries} margin={{ top: 4, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="usage-grad-tokens" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--app-chart-6)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--app-chart-6)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--app-border-subtle)" />
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
                stroke="var(--app-chart-6)"
                fill="url(#usage-grad-tokens)"
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

interface UsageAnalyticsProps {
  period: Period;
}

/** The whole analytics block, in the order the two pages show it. */
export function UsageAnalytics({ period }: UsageAnalyticsProps) {
  const tickInterval = useMemo(() => tickIntervalForPeriod(period), [period]);

  return (
    <>
      <Deferred data="activityHeatmap" fallback={<Skeleton height={140} radius="sm" mb="xl" />}>
        <HeatmapPanel />
      </Deferred>

      <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} mb="xl" spacing="md">
        <Deferred data="summary" fallback={<SummarySkeletons />}>
          <SummaryPanel />
        </Deferred>
      </SimpleGrid>

      <Deferred data="summary" fallback={<Skeleton height={200} radius="sm" mb="xl" />}>
        <ProjectBreakdownPanel />
      </Deferred>

      <Deferred
        data="agentActivity"
        fallback={
          <Box mb="xl">
            <ChartSkeleton height={200} />
          </Box>
        }
      >
        <AgentActivityPanel />
      </Deferred>

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
    </>
  );
}
