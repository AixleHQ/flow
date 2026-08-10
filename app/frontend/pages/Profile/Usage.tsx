import { Deferred, Head, router, usePage } from '@inertiajs/react';
import {
  Alert,
  Badge,
  Box,
  Grid,
  Group,
  Paper,
  Select,
  SimpleGrid,
  Skeleton,
  Table,
  Text,
  Tooltip,
} from '@mantine/core';
import { IconChartBar, IconClock, IconCoin, IconInfoCircle, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
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

import { AuthLayout } from 'layouts/AuthLayout';

import { CHART_SERIES } from 'shared/theme/chartPalette';
import { type SharedProps } from 'shared/ui';
import { ContributionHeatmap } from 'shared/ui/ContributionHeatmap';

type Period = '7d' | '30d' | '90d' | '1y';

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

interface Session {
  id: number;
  sessionType: string;
  agentType: string | null;
  state: string;
  startedAt: string | null;
  finishedAt: string | null;
  createdAt: string;
  totalTokens: number;
  costCents: number;
  models: string[] | null;
  projectName: string | null;
}

interface Props {
  period: Period;
  projectId?: string | null;
  viewerIsSelf: boolean;
  targetUser: { id: number; name: string | null; email: string };
  summary?: SummaryData;
  agentActivity?: AgentActivityData;
  costToken?: CostTokenData;
  activityHeatmap?: HeatmapData;
  sessions?: Session[];
}

const AGENT_COLORS = CHART_SERIES;
const PROJECT_COLORS = CHART_SERIES;
const getAgentColor = (i: number) => AGENT_COLORS[i % AGENT_COLORS.length];

const PERIOD_OPTIONS = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' },
  { value: '1y', label: 'Last year' },
];

const AGENT_LABELS: Record<string, { label: string; color: string }> = {
  claude_code: { label: 'Claude Code', color: 'orange' },
  cursor_cli: { label: 'Cursor CLI', color: 'violet' },
  codex: { label: 'Codex', color: 'teal' },
  gemini_cli: { label: 'Gemini CLI', color: 'blue' },
};

const STATE_CONFIG: Record<string, { label: string; color: string }> = {
  not_started: { label: 'Pending', color: 'gray' },
  running: { label: 'Starting', color: 'blue' },
  ready: { label: 'Running', color: 'green' },
  finishing: { label: 'Finishing', color: 'yellow' },
  finished: { label: 'Finished', color: 'gray' },
  failed: { label: 'Failed', color: 'red' },
};

const SESSION_TYPE_LABELS: Record<string, string> = {
  agent_session: 'Standalone',
  workflow_step: 'Workflow step',
  auth_setup: 'Auth setup',
  tool_setup: 'Tool setup',
};

const chartTooltipStyle = {
  backgroundColor: 'var(--app-bg-default)',
  border: '1px solid var(--app-border-default)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--app-text-primary)',
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
  const { activityHeatmap } = usePage<{ props: Props }>().props as unknown as Props;
  if (!activityHeatmap) return null;

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" mb="xl">
      <ContributionHeatmap days={activityHeatmap.days} />
    </Paper>
  );
}

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
  const { agentActivity } = usePage<{ props: Props }>().props as unknown as Props;
  if (!agentActivity) return null;

  const { sessionsByAgent } = agentActivity;

  return (
    <Paper withBorder p="md" radius="md" mb="xl">
      <Text size="sm" fw={600} mb="md">
        Usage Breakdown by Agent Type
      </Text>
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
        <Paper withBorder p="md" radius="md">
          <Text size="sm" fw={600} mb="md">
            Daily Token Consumption
          </Text>
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

function sessionTokenFmt(n: number): string {
  if (!n || n === 0) return '—';
  return formatTokens(n);
}

function SessionsPanel() {
  const { sessions } = usePage<{ props: Props }>().props as unknown as Props;
  if (!sessions) return null;

  if (sessions.length === 0) {
    return (
      <Box py="xl" ta="center" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
        <Text c="dimmed">No sessions yet</Text>
      </Box>
    );
  }

  return (
    <Table.ScrollContainer minWidth={800}>
      <Table striped highlightOnHover verticalSpacing={6} fz="sm">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>ID</Table.Th>
            <Table.Th>Agent</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Project</Table.Th>
            <Table.Th ta="right">Tokens</Table.Th>
            <Table.Th ta="right">Cost</Table.Th>
            <Table.Th>Started</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {sessions.map((s) => {
            const agent = AGENT_LABELS[s.agentType ?? ''] ?? { label: s.agentType ?? '—', color: 'gray' };
            const stateConfig = STATE_CONFIG[s.state] ?? { label: s.state, color: 'gray' };
            const typeLabel = SESSION_TYPE_LABELS[s.sessionType] ?? s.sessionType;
            return (
              <Table.Tr key={s.id}>
                <Table.Td>
                  <Text size="xs" ff="monospace" c="dimmed">
                    #{s.id}
                  </Text>
                </Table.Td>
                <Table.Td>
                  <Badge color={agent.color} size="sm" variant="filled">
                    {agent.label}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Text size="xs" c="dimmed">
                    {typeLabel}
                  </Text>
                </Table.Td>
                <Table.Td>
                  <Badge color={stateConfig.color} size="sm" variant="outline">
                    {stateConfig.label}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Text size="sm" truncate maw={120} c="dimmed">
                    {s.projectName ?? '—'}
                  </Text>
                </Table.Td>
                <Table.Td ta="right">
                  <Text size="xs" ff="monospace">
                    {sessionTokenFmt(s.totalTokens)}
                  </Text>
                </Table.Td>
                <Table.Td ta="right">
                  <Text size="xs" ff="monospace" fw={s.costCents > 0 ? 600 : 400}>
                    {s.costCents > 0 ? `$${(s.costCents / 100).toFixed(2)}` : '—'}
                  </Text>
                </Table.Td>
                <Table.Td>
                  <Tooltip label={s.startedAt ? new Date(s.startedAt).toLocaleString() : s.createdAt}>
                    <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>
                      {formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}
                    </Text>
                  </Tooltip>
                </Table.Td>
              </Table.Tr>
            );
          })}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

// --- Main page ---

const UsagePage = () => {
  const { period, viewerIsSelf, targetUser } = usePage<{ props: Props }>().props as unknown as Props;
  // Shared props (not this page's Props): only label the company when the user
  // actually belongs to more than one, so single-company users see no change.
  const { currentUser } = usePage<SharedProps>().props;
  const companyName = (currentUser?.memberships?.length ?? 0) > 1 ? currentUser?.currentCompany?.name : null;
  const tickInterval = useMemo(() => tickIntervalForPeriod(period), [period]);

  const navigate = (nextPeriod: string) => {
    router.get(
      window.location.pathname,
      {
        period: nextPeriod,
        ...(viewerIsSelf ? {} : { user_id: targetUser.id }),
      },
      { preserveState: true, preserveScroll: true },
    );
  };

  return (
    <AuthLayout>
      <Head title="Usage" />

      {/* Matches the Account tab's content width so the two tabs don't jump
          width when switching between them. */}
      <Box maw={1120} mx="auto">
        <Group justify="space-between" mb="xl" wrap="wrap">
          <Box>
            <Text size="xl" fw={700}>
              Usage
            </Text>
            <Text size="sm" c="dimmed">
              {/* Usage is always a CURRENT-COMPANY slice (see ProfileController#usage).
                  For someone who belongs to several companies, an unlabelled total
                  reads as "everything", so name the company being shown. */}
              Cross-project agent activity, costs, and sessions
              {companyName ? ` in ${companyName}` : ''}
            </Text>
          </Box>
          <Group gap="sm">
            <Select value={period} onChange={(v) => navigate(v ?? '30d')} data={PERIOD_OPTIONS} size="sm" w={140} />
          </Group>
        </Group>

        {!viewerIsSelf && (
          <Alert icon={<IconInfoCircle size={16} />} color="blue" mb="xl">
            Viewing {targetUser.name ?? targetUser.email}&apos;s usage
          </Alert>
        )}

        {/* Contribution heatmap */}
        <Deferred data="activityHeatmap" fallback={<Skeleton height={140} radius="sm" mb="xl" />}>
          <HeatmapPanel />
        </Deferred>

        {/* Summary stats */}
        <SimpleGrid cols={{ base: 2, sm: 3, md: 5 }} mb="xl" spacing="md">
          <Deferred data="summary" fallback={<SummarySkeletons />}>
            <SummaryPanel />
          </Deferred>
        </SimpleGrid>

        {/* Per-project breakdown */}
        <Text size="md" fw={600} mb="md" mt="xl">
          Projects Overview
        </Text>
        <Deferred data="summary" fallback={<Skeleton height={200} radius="sm" mb="xl" />}>
          <ProjectBreakdownPanel />
        </Deferred>

        {/* Agent activity */}
        <Text size="md" fw={600} mb="md" mt="xl">
          Agent Activity
        </Text>
        <Deferred data="agentActivity" fallback={<ChartSkeleton height={200} />}>
          <AgentActivityPanel />
        </Deferred>

        {/* Cost & token usage */}
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

        {/* Sessions list */}
        <Text size="md" fw={600} mb="md" mt="xl">
          Sessions
        </Text>
        <Deferred data="sessions" fallback={<Skeleton height={200} radius="sm" />}>
          <SessionsPanel />
        </Deferred>
      </Box>
    </AuthLayout>
  );
};

export default UsagePage;
