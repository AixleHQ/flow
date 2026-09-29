import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Box, Grid, Group, Paper, SegmentedControl, Select, SimpleGrid, Skeleton, Text } from '@mantine/core';
import { useEffect, useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import {
  CHART_ACCENT,
  ChartSkeleton,
  type AgentActivityData,
  type Period,
  PERIOD_OPTIONS,
  SummarySkeletons,
  tickIntervalForPeriod,
} from 'shared/analytics/chartHelpers';
import {
  AgentActivityPanel,
  CostTokenPanel,
  type CostTokenData,
  type CostTokenPoint,
  type SourceData,
  SourcesPanel,
  SummaryPanel,
  type UsageScope,
} from 'shared/analytics/panels';
import { formatCostCents, formatTokens } from 'shared/lib/formatUsage';
import { PageHeader } from 'shared/ui/PageHeader';

type Scope = 'company' | 'user';

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

// --- Main page ---

const AnalyticsPage = () => {
  const { scope, period, summary, agentActivity, costToken, workflowCosts, sources } = usePage<{
    props: Props;
  }>().props as unknown as Props;
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
            <SummaryPanel summary={summary} />
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
          <AgentActivityPanel agentActivity={agentActivity} tickInterval={tickInterval} />
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
          <CostTokenPanel
            costToken={costToken}
            workflowCosts={workflowCosts}
            tickInterval={tickInterval}
            usageScope={usageScope}
          />
        </Deferred>

        {/* Session insights (company scope: origin only — no duration histogram) */}
        <Text size="md" fw={600} mb="md" mt="xl">
          Session insights
        </Text>
        <Deferred data="sources" fallback={<ChartSkeleton height={200} />}>
          <SourcesPanel sources={sources} paperProps={{ mb: 'xl' }} />
        </Deferred>
      </Box>
    </AuthLayout>
  );
};

export default AnalyticsPage;
