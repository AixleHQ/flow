import { Box, Grid, Group, Paper, type PaperProps, Text } from '@mantine/core';
import { IconChartBar, IconClock, IconCoin, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
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

import { formatCostCents, formatTokens } from 'shared/lib/formatUsage';

import {
  AgentLogo,
  buildActivityChartData,
  centerLabelFontSize,
  CHART_ACCENT,
  CHART_NEUTRAL,
  CHART_TAUPE,
  chartTooltipStyle,
  formatAxisDate,
  getAgentColor,
  type AgentActivityData,
  ScopeBadge,
  sharePct,
} from './chartHelpers';

// The panels the company and project analytics pages share. They were two
// byte-for-byte copies; each page now hands them its own props.

export type UsageScope = 'all' | 'workflows';

export interface AnalyticsSummary {
  totalSessions: number;
  totalCostCents: number;
  totalTokens: number;
  avgCostCentsPerSession: number;
  workflowsRun: number;
}

export interface SourceRow {
  sessionType: string;
  label: string;
  count: number;
}

export interface SourceData {
  sources: SourceRow[];
}

export interface CostTokenPoint {
  date: string;
  costCents: number;
  totalTokens: number;
}

export interface CostTokenData {
  timeSeries: CostTokenPoint[];
  totals: { totalCostCents: number; totalTokens: number; avgCostCentsPerSession: number };
}

export function SummaryPanel({ summary }: { summary?: AnalyticsSummary }) {
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

export function AgentActivityPanel({
  agentActivity,
  tickInterval,
}: {
  agentActivity?: AgentActivityData;
  tickInterval: number;
}) {
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

export function CostTokenPanel({
  costToken,
  workflowCosts,
  tickInterval,
  usageScope,
}: {
  costToken?: CostTokenData;
  workflowCosts?: { timeSeries: CostTokenPoint[] };
  tickInterval: number;
  usageScope: UsageScope;
}) {
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

export function SourcesPanel({ sources, paperProps }: { sources?: SourceData; paperProps?: PaperProps }) {
  if (!sources) return null;

  const totalSessions = sources.sources.reduce((sum, s) => sum + s.count, 0);
  // Backend already orders rows by count DESC, so the first row is the dominant source.
  const topSource = sources.sources[0];

  return (
    <Paper withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)" {...paperProps}>
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
