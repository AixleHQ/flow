import { Head, router, usePage } from '@inertiajs/react';
import { Box, Progress, Text } from '@mantine/core';
import { IconCoin, IconLayoutKanban, IconPlayerPlay, IconRoute } from '@tabler/icons-react';
import type { CSSProperties } from 'react';
import { useEffect } from 'react';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Summary {
  sessionsLaunched: number;
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

const ACTIVITY_EVENT_COLORS: Record<string, string> = {
  task_created: '#00bcd4',
  task_moved: '#ff9800',
  task_updated: '#607d8b',
  task_deleted: '#f44336',
  comment_added: '#9c27b0',
  asset_attached: '#795548',
  workflow_triggered: '#2196f3',
  workflow_completed: '#4caf50',
  workflow_failed: '#f44336',
  workflow_cancelled: '#9e9e9e',
  session_started: '#2196f3',
  session_completed: '#4caf50',
  session_failed: '#f44336',
};

const WORKFLOW_STATUS_COLORS: Record<string, string> = {
  Completed: '#4caf50',
  'In Progress': '#2196f3',
  Failed: '#f44336',
  Queued: '#ff9800',
};

const s: Record<string, CSSProperties> = {
  pageHeader: {
    marginBottom: 32,
  },
  pageTitle: {
    fontSize: 24,
    fontWeight: 700,
    marginBottom: 4,
  },
  pageSubtitle: {
    fontSize: 14,
    color: 'var(--mantine-color-dimmed)',
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: 600,
    marginBottom: 16,
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
    gap: 16,
    marginBottom: 32,
  },
  statCard: {
    padding: 20,
    backgroundColor: 'var(--mantine-color-dark-7)',
    borderRadius: 12,
    border: '1px solid var(--mantine-color-dark-4)',
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  },
  statIconWrap: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    marginBottom: 4,
  },
  statLabel: {
    fontSize: 12,
    color: 'var(--mantine-color-dimmed)',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  statValue: {
    fontSize: 32,
    fontWeight: 700,
    lineHeight: 1.1,
  },
  twoCol: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 24,
    marginBottom: 32,
  },
  card: {
    padding: 24,
    backgroundColor: 'var(--mantine-color-dark-7)',
    borderRadius: 12,
    border: '1px solid var(--mantine-color-dark-4)',
  },
  activityItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
    padding: '10px 0',
    borderBottom: '1px solid var(--mantine-color-dark-4)',
  },
  activityItemLast: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
    padding: '10px 0',
  },
  activityDot: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    marginTop: 5,
    flexShrink: 0,
  },
  activityText: {
    fontSize: 13,
    lineHeight: 1.4,
  },
  activityTime: {
    fontSize: 11,
    color: 'var(--mantine-color-dimmed)',
    marginTop: 2,
  },
  progressRow: {
    marginBottom: 16,
  },
  progressRowLast: {
    marginBottom: 0,
  },
  progressLabel: {
    display: 'flex',
    justifyContent: 'space-between',
    marginBottom: 6,
  },
  progressLabelText: {
    fontSize: 13,
    color: 'var(--mantine-color-dimmed)',
  },
  progressLabelValue: {
    fontSize: 13,
    fontWeight: 500,
  },
  boardGrid: {
    padding: 24,
    backgroundColor: 'var(--mantine-color-dark-7)',
    borderRadius: 12,
    border: '1px solid var(--mantine-color-dark-4)',
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
    gap: 16,
  },
  boardCell: {
    textAlign: 'center',
    padding: 12,
    borderRadius: 8,
    backgroundColor: 'var(--mantine-color-dark-6)',
  },
  boardCellValue: {
    fontSize: 28,
    fontWeight: 700,
  },
  boardCellName: {
    fontSize: 12,
    color: 'var(--mantine-color-dimmed)',
    marginTop: 4,
  },
  boardCellTotal: {
    textAlign: 'center',
    padding: 12,
    borderRadius: 8,
    backgroundColor: 'var(--mantine-color-blue-7)',
  },
  boardCellTotalValue: {
    fontSize: 28,
    fontWeight: 700,
    color: 'white',
  },
  boardCellTotalName: {
    fontSize: 12,
    color: 'white',
    marginTop: 4,
    opacity: 0.85,
  },
};

const STAT_ICONS = [
  { Icon: IconPlayerPlay, color: 'var(--mantine-color-blue-5)' },
  { Icon: IconCoin, color: 'var(--mantine-color-green-5)' },
  { Icon: IconRoute, color: 'var(--mantine-color-indigo-5)' },
  { Icon: IconLayoutKanban, color: 'var(--mantine-color-yellow-5)' },
];

const OverviewPage = () => {
  const { project, summary, workflowRunStats, boardTaskDistribution, recentActivity } = usePage<{ props: Props }>()
    .props as unknown as Props;

  useEffect(() => {
    const interval = setInterval(() => {
      router.reload({
        preserveScroll: true,
        only: ['summary', 'workflowRunStats', 'boardTaskDistribution', 'recentActivity'],
      } as never);
    }, 60_000);
    return () => clearInterval(interval);
  }, []);

  const projectStats = [
    { label: 'Sessions Launched', value: (summary.sessionsLaunched ?? 0).toLocaleString() },
    { label: 'Total Spend', value: formatSpend(summary.totalSpendCents ?? 0) },
    { label: 'Workflows', value: (summary.workflowsCount ?? 0).toLocaleString() },
    { label: 'Board Tasks', value: (summary.boardTasksCount ?? 0).toLocaleString() },
  ];

  const workflowStatus = [
    {
      label: 'Completed',
      value: workflowRunStats.completed ?? 0,
      total: workflowRunStats.total ?? 0,
      color: WORKFLOW_STATUS_COLORS['Completed'],
    },
    {
      label: 'In Progress',
      value: workflowRunStats.inProgress ?? 0,
      total: workflowRunStats.total ?? 0,
      color: WORKFLOW_STATUS_COLORS['In Progress'],
    },
    {
      label: 'Failed',
      value: workflowRunStats.failed ?? 0,
      total: workflowRunStats.total ?? 0,
      color: WORKFLOW_STATUS_COLORS['Failed'],
    },
    {
      label: 'Queued',
      value: workflowRunStats.queued ?? 0,
      total: workflowRunStats.total ?? 0,
      color: WORKFLOW_STATUS_COLORS['Queued'],
    },
  ];

  return (
    <>
      <Head title={`Overview — ${project.name}`} />
      <Box>
        <Box style={s.pageHeader}>
          <Text style={s.pageTitle}>Project Overview</Text>
          <Text style={s.pageSubtitle}>Project activity at a glance</Text>
        </Box>

        <Text style={s.sectionTitle}>Project Summary</Text>
        <Box style={s.statsGrid}>
          {projectStats.map((stat, idx) => (
            <Box key={stat.label} style={s.statCard}>
              <Box style={s.statIconWrap}>
                {(() => {
                  const { Icon, color } = STAT_ICONS[idx];
                  return <Icon size={20} color={color} />;
                })()}
                <Text style={s.statLabel}>{stat.label}</Text>
              </Box>
              <Text style={s.statValue}>{stat.value}</Text>
            </Box>
          ))}
        </Box>

        <Box style={s.twoCol}>
          <Box style={s.card}>
            <Text style={s.sectionTitle}>Recent Activity</Text>
            {recentActivity.length === 0 ? (
              <Text style={{ fontSize: 13, color: 'var(--mantine-color-dimmed)', padding: '10px 0' }}>
                No recent activity found.
              </Text>
            ) : (
              recentActivity.map((item, idx) => (
                <Box key={idx} style={idx < recentActivity.length - 1 ? s.activityItem : s.activityItemLast}>
                  <Box
                    style={{
                      ...s.activityDot,
                      backgroundColor: ACTIVITY_EVENT_COLORS[item.eventType] ?? '#9e9e9e',
                    }}
                  />
                  <Box>
                    <Text style={s.activityText}>{item.description}</Text>
                    <Text style={s.activityTime}>
                      {item.actorName} · {formatRelativeTime(item.occurredAt)}
                    </Text>
                  </Box>
                </Box>
              ))
            )}
          </Box>

          <Box style={s.card}>
            <Text style={s.sectionTitle}>Workflow Runs</Text>
            {workflowStatus.map((item, idx) => (
              <Box key={item.label} style={idx < workflowStatus.length - 1 ? s.progressRow : s.progressRowLast}>
                <Box style={s.progressLabel}>
                  <Text style={s.progressLabelText}>{item.label}</Text>
                  <Text style={s.progressLabelValue}>
                    {item.value}{' '}
                    <Text span style={{ color: 'var(--mantine-color-dimmed)', fontWeight: 400 }}>
                      / {item.total}
                    </Text>
                  </Text>
                </Box>
                <Progress
                  value={item.total > 0 ? (item.value / item.total) * 100 : 0}
                  color={item.color}
                  size={6}
                  radius={3}
                />
              </Box>
            ))}
          </Box>
        </Box>

        <Text style={s.sectionTitle}>Board Task Distribution</Text>
        <Box style={s.boardGrid}>
          {(boardTaskDistribution.columns ?? []).map((col) => (
            <Box key={col.name} style={s.boardCell}>
              <Text style={s.boardCellValue}>{col.count}</Text>
              <Text style={s.boardCellName}>{col.name}</Text>
            </Box>
          ))}
          {(boardTaskDistribution.total ?? 0) > 0 && (
            <Box style={s.boardCellTotal}>
              <Text style={s.boardCellTotalValue}>{boardTaskDistribution.total}</Text>
              <Text style={s.boardCellTotalName}>Total</Text>
            </Box>
          )}
        </Box>
      </Box>
    </>
  );
};

setPageLayout(OverviewPage, persistentProjectLayout);

export default OverviewPage;
