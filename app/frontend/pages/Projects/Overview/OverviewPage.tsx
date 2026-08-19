import { Head, router, usePage } from '@inertiajs/react';
import { Box, Button, RingProgress, Text } from '@mantine/core';
import { IconArrowRight, IconChecklist, IconCoin, IconGitBranch, IconPlayerPlay } from '@tabler/icons-react';
import { useEffect, useMemo } from 'react';

import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './OverviewPage.module.css';

interface Project {
  id: number;
  name: string;
}

interface Summary {
  sessionsLaunched: number;
  sessionsRunning: number;
  totalSpendCents: number;
  workflowsCount: number;
  boardTasksCount: number;
}

interface WorkflowRunStats {
  completed: number;
  inProgress: number;
  failed: number;
  queued: number;
  total: number;
}

interface BoardColumn {
  name: string;
  count: number;
}

interface BoardTaskDistribution {
  columns: BoardColumn[];
  total: number;
}

interface ActivityItem {
  eventType: string;
  description: string;
  actorName: string;
  occurredAt: string;
}

interface Props {
  project: Project;
  summary: Summary;
  workflowRunStats: WorkflowRunStats;
  boardTaskDistribution: BoardTaskDistribution;
  recentActivity: ActivityItem[];
}

function formatSpend(cents: number): string {
  const dollars = cents / 100;
  if (dollars >= 1000) return `$${(dollars / 1000).toFixed(1)}k`;
  return `$${dollars.toFixed(2)}`;
}

function formatRelativeTime(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const diffSec = Math.floor(diffMs / 1000);
  if (diffSec < 60) return `${diffSec}s ago`;
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin} min ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr} hr ago`;
  return `${Math.floor(diffHr / 24)} d ago`;
}

// The activity feed encodes outcome, not category: created/moved/updated are
// neutral, completions are success, failures are danger.
const ACTIVITY_EVENT_COLORS: Record<string, string> = {
  task_created: 'var(--app-chart-6)',
  task_moved: 'var(--app-chart-4)',
  task_updated: 'var(--app-text-tertiary)',
  task_deleted: 'var(--app-text-tertiary)',
  comment_added: 'var(--app-chart-5)',
  asset_attached: 'var(--app-chart-7)',
  workflow_triggered: 'var(--app-chart-2)',
  workflow_completed: 'var(--app-success-fg)',
  workflow_failed: 'var(--app-danger-fg)',
  workflow_cancelled: 'var(--app-text-tertiary)',
  session_started: 'var(--app-chart-2)',
  session_completed: 'var(--app-success-fg)',
  session_failed: 'var(--app-danger-fg)',
  gate_reconciled: 'var(--app-chart-4)',
  gate_stale: 'var(--app-danger-fg)',
};

// Status semantics for workflow runs (issue #522 handoff note): green = success
// only, red = failed, amber = live/in-progress only, neutral = queued/backlog.
const RUN_STATUS_COLOR = {
  completed: 'var(--app-success-fg)',
  failed: 'var(--app-danger-fg)',
  inProgress: 'var(--app-warning-fg)',
  queued: 'var(--app-text-tertiary)',
} as const;

// Neutral-to-green ramp for board columns, per the handoff note. Column
// semantics are project-defined, so "Done" is detected by name; everything
// else cycles through the warm-neutral ramp by position.
const BOARD_NEUTRAL_RAMP = ['var(--app-chart-warm-1)', 'var(--app-chart-warm-2)', 'var(--app-chart-warm-3)'];

function boardColumnColor(name: string, index: number): string {
  if (/done/i.test(name)) return 'var(--app-success-fg)';
  return BOARD_NEUTRAL_RAMP[index % BOARD_NEUTRAL_RAMP.length];
}

// One muted tone for all four KPI icons: the number is the signal, the icon
// just names the metric.
const KPI_ICON_COLOR = 'var(--app-text-tertiary)';

/**
 * Fold consecutive identical events into one row.
 *
 * The feed is ordered by time, and agent work produces runs of the same event —
 * ten rows of "Session completed with claude_code" told you nothing that one row
 * with a count would not. Only *consecutive* duplicates collapse, so the
 * chronology stays intact.
 */
function groupActivity<T extends { eventType: string; description: string; actorName: string; occurredAt: string }>(
  items: T[],
): (T & { count: number })[] {
  const out: (T & { count: number })[] = [];
  for (const item of items) {
    const prev = out[out.length - 1];
    if (prev && prev.description === item.description && prev.actorName === item.actorName) {
      prev.count += 1;
      continue;
    }
    out.push({ ...item, count: 1 });
  }
  return out;
}

const OverviewPage = () => {
  const { project, summary, workflowRunStats, boardTaskDistribution, recentActivity } = usePage<{ props: Props }>()
    .props as unknown as Props;

  useEffect(() => {
    const interval = setInterval(() => {
      router.reload({
        preserveScroll: true,
        only: ['summary', 'workflow_run_stats', 'board_task_distribution', 'recent_activity'],
      } as never);
    }, 60_000);
    return () => clearInterval(interval);
  }, []);

  const groupedActivity = useMemo(() => groupActivity(recentActivity ?? []), [recentActivity]);

  const { completed, failed, inProgress, queued, total } = workflowRunStats;
  // Success rate excludes runs that haven't settled yet (in-progress/queued),
  // per the handoff note: completed ÷ (completed + failed).
  const settled = completed + failed;
  const successRate = settled > 0 ? Math.round((completed / settled) * 100) : 0;
  const runSections = [
    { value: total > 0 ? (completed / total) * 100 : 0, color: RUN_STATUS_COLOR.completed },
    { value: total > 0 ? (failed / total) * 100 : 0, color: RUN_STATUS_COLOR.failed },
    { value: total > 0 ? (inProgress / total) * 100 : 0, color: RUN_STATUS_COLOR.inProgress },
    { value: total > 0 ? (queued / total) * 100 : 0, color: RUN_STATUS_COLOR.queued },
  ];
  const runLegend = [
    { label: 'Completed', value: completed, color: RUN_STATUS_COLOR.completed },
    { label: 'Failed', value: failed, color: RUN_STATUS_COLOR.failed },
    { label: 'In Progress', value: inProgress, color: RUN_STATUS_COLOR.inProgress },
    { label: 'Queued', value: queued, color: RUN_STATUS_COLOR.queued },
  ];

  const avgPerSessionCents = summary.sessionsLaunched > 0 ? summary.totalSpendCents / summary.sessionsLaunched : null;

  const boardColumns = boardTaskDistribution.columns ?? [];
  const maxColumnCount = Math.max(1, ...boardColumns.map((c) => c.count));

  return (
    <>
      <Head title={`Overview — ${project.name}`} />
      <Box>
        <PageHeader title="Project Overview" subtitle="Current and overall project activity" />

        <Box className={classes.kpiRow}>
          <Box className={classes.kpiCard}>
            <Box className={classes.kpiTop}>
              <IconPlayerPlay size={15} color={KPI_ICON_COLOR} />
              <Text className={classes.kpiLabel}>Sessions Launched</Text>
            </Box>
            <Text className={classes.kpiValue}>{summary.sessionsLaunched.toLocaleString()}</Text>
            <Text className={classes.kpiDelta}>
              <span className={classes.liveDot} /> {summary.sessionsRunning} running now
            </Text>
          </Box>

          <Box className={classes.kpiCard}>
            <Box className={classes.kpiTop}>
              <IconCoin size={15} color={KPI_ICON_COLOR} />
              <Text className={classes.kpiLabel}>Total Spend</Text>
            </Box>
            <Text className={`${classes.kpiValue} ${classes.kpiValueMono}`}>
              {formatSpend(summary.totalSpendCents)}
            </Text>
            {avgPerSessionCents != null && (
              <Text className={classes.kpiDelta}>{formatSpend(avgPerSessionCents)} avg per session</Text>
            )}
          </Box>

          <Box className={classes.kpiCard}>
            <Box className={classes.kpiTop}>
              <IconGitBranch size={15} color={KPI_ICON_COLOR} />
              <Text className={classes.kpiLabel}>Workflows</Text>
            </Box>
            <Text className={classes.kpiValue}>{summary.workflowsCount.toLocaleString()}</Text>
            <Text className={classes.kpiDelta}>All active</Text>
          </Box>

          <Box className={classes.kpiCard}>
            <Box className={classes.kpiTop}>
              <IconChecklist size={15} color={KPI_ICON_COLOR} />
              <Text className={classes.kpiLabel}>Board Tasks</Text>
            </Box>
            <Text className={classes.kpiValue}>{summary.boardTasksCount.toLocaleString()}</Text>
          </Box>
        </Box>

        <Box className={classes.twoCol}>
          <Box className={classes.panel}>
            <Box className={classes.panelHead}>
              <Text className={classes.sectionTitle}>Recent Activity</Text>
            </Box>
            {groupedActivity.length === 0 ? (
              <Text className={classes.emptyState}>No recent activity found.</Text>
            ) : (
              <Box className={classes.actList}>
                {groupedActivity.map((item, idx) => (
                  <Box key={idx} className={idx < groupedActivity.length - 1 ? classes.actItem : classes.actItemLast}>
                    <Box
                      className={classes.actDot}
                      style={{ backgroundColor: ACTIVITY_EVENT_COLORS[item.eventType] ?? 'var(--app-text-tertiary)' }}
                    />
                    <Box className={classes.actBody}>
                      <Text className={classes.actTxt}>
                        {item.description}
                        {item.count > 1 && (
                          <Text span c="var(--app-text-tertiary)" fw={600}>
                            {' '}
                            &times;{item.count}
                          </Text>
                        )}
                      </Text>
                      <Text className={classes.actMeta}>
                        {item.actorName} · {formatRelativeTime(item.occurredAt)}
                      </Text>
                    </Box>
                  </Box>
                ))}
              </Box>
            )}
          </Box>

          <Box className={classes.panel}>
            <Box className={classes.panelHead}>
              <Text className={classes.sectionTitle}>Workflow Runs</Text>
              <Button
                variant="subtle"
                size="compact-xs"
                rightSection={<IconArrowRight size={13} />}
                onClick={() => router.visit(`/company/projects/${project.id}/workflow_runs`)}
              >
                Open Runs
              </Button>
            </Box>
            <Box className={classes.runsBody}>
              <RingProgress
                size={130}
                thickness={13}
                sections={runSections}
                label={
                  <Box className={classes.donutCenter}>
                    <Text className={classes.donutNum}>{successRate}%</Text>
                    <Text className={classes.donutCap}>Success</Text>
                  </Box>
                }
              />
              <Box className={classes.runsInfo}>
                <Text className={classes.rhTotal}>
                  <Text span className={classes.rhTotalValue}>
                    {total}
                  </Text>{' '}
                  total runs
                </Text>
                <Text className={classes.rhNote}>
                  Success rate is completed ÷ settled runs.
                  {failed > 0 && ` ${failed} failure${failed === 1 ? '' : 's'} need review.`}
                </Text>
                <Box className={classes.legend}>
                  {runLegend.map((item) => (
                    <Box key={item.label} className={classes.legRow}>
                      <span className={classes.legDot} style={{ background: item.color }} />
                      <span className={classes.legName}>{item.label}</span>
                      <span className={classes.legVal}>{item.value}</span>
                      <span className={classes.legPct}>{total > 0 ? Math.round((item.value / total) * 100) : 0}%</span>
                    </Box>
                  ))}
                </Box>
              </Box>
            </Box>
          </Box>
        </Box>

        <Box className={classes.panel}>
          <Box className={classes.panelHead} style={{ marginBottom: 14 }}>
            <Text className={classes.sectionTitle}>Board Task Distribution</Text>
            <Button
              variant="subtle"
              size="compact-xs"
              rightSection={<IconArrowRight size={13} />}
              onClick={() => router.visit(`/company/projects/${project.id}/board`)}
            >
              Open board
            </Button>
          </Box>
          <Box className={classes.hbarList}>
            {boardColumns.map((col, idx) => (
              <Box key={col.name} className={classes.hbarRow}>
                <Text className={classes.hbarName}>{col.name}</Text>
                <Box className={classes.hbarTrack}>
                  <Box
                    className={classes.hbarFill}
                    style={{
                      width: `${(col.count / maxColumnCount) * 100}%`,
                      background: boardColumnColor(col.name, idx),
                    }}
                  />
                </Box>
                <Text className={classes.hbarCount}>{col.count}</Text>
              </Box>
            ))}
          </Box>
        </Box>
      </Box>
    </>
  );
};

setPageLayout(OverviewPage, persistentProjectLayout);

export default OverviewPage;
