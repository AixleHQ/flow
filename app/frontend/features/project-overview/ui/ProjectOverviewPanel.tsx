import AccountCircleIcon from '@mui/icons-material/AccountCircle';
import WorkflowsIcon from '@mui/icons-material/AccountTree';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import FolderIcon from '@mui/icons-material/Folder';
import PlayCircleIcon from '@mui/icons-material/PlayCircle';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import ViewKanbanIcon from '@mui/icons-material/ViewKanban';
import { Box, Button, Card, Chip, Divider, LinearProgress, Skeleton, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

import { useGetBoardTaskDistributionQuery } from '../api/boardTaskDistributionApi';
import { useGetPlatformSummaryQuery } from '../api/platformSummaryApi';
import { useGetRecentActivityQuery } from '../api/recentActivityApi';
import { useGetTopAgentsBySessionsQuery } from '../api/topAgentsBySessionsApi';
import { useGetWorkflowRunStatsQuery } from '../api/workflowRunStatsApi';

const styles = {
  container: {
    padding: '24px 0',
  },
  pageHeader: {
    marginBottom: '32px',
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
  },
  statsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
    gap: '16px',
    marginBottom: '32px',
  },
  statCard: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  statIconWrap: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '4px',
  },
  statLabel: {
    fontSize: '12px',
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  statValue: {
    fontSize: '32px',
    fontWeight: 700,
    color: 'text.primary',
    lineHeight: 1.1,
  },
  statChange: {
    fontSize: '12px',
    color: 'success.main',
  },
  twoCol: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '24px',
    marginBottom: '32px',
  },
  card: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  activityItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: '12px',
    padding: '10px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  activityDot: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
    marginTop: '5px',
    flexShrink: 0,
  },
  activityText: {
    fontSize: '13px',
    color: 'text.primary',
    lineHeight: 1.4,
  },
  activityTime: {
    fontSize: '11px',
    color: 'text.disabled',
    marginTop: '2px',
  },
  progressRow: {
    marginBottom: '16px',
    '&:last-child': { marginBottom: 0 },
  },
  progressLabel: {
    display: 'flex',
    justifyContent: 'space-between',
    marginBottom: '6px',
  },
  progressLabelText: {
    fontSize: '13px',
    color: 'text.secondary',
  },
  progressLabelValue: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
  },
} satisfies Record<string, SxProps<Theme>>;

function formatSpend(cents: number): string {
  const dollars = cents / 100;
  if (dollars >= 1000) {
    return `$${(dollars / 1000).toFixed(1)}k`;
  }
  return `$${dollars.toFixed(2)}`;
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

function getActivityColor(eventType: string): string {
  return ACTIVITY_EVENT_COLORS[eventType] ?? '#9e9e9e';
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

const WORKFLOW_STATUS_COLORS: Record<string, string> = {
  Completed: '#4caf50',
  'In Progress': '#2196f3',
  Failed: '#f44336',
  Queued: '#ff9800',
};

interface ProjectOverviewPanelProps {
  projectId?: number;
}

const ACTIVITY_PER_PAGE = 10;

const ProjectOverviewPanel = ({ projectId: _projectId }: ProjectOverviewPanelProps) => {
  void _projectId;
  const [activityPage, setActivityPage] = useState(1);

  const {
    data: summary,
    isLoading: summaryLoading,
    isError: summaryError,
  } = useGetPlatformSummaryQuery(undefined, {
    pollingInterval: 60_000,
  });

  const {
    data: workflowRunStats,
    isLoading: workflowRunStatsLoading,
    isError: workflowRunStatsError,
  } = useGetWorkflowRunStatsQuery(undefined, {
    pollingInterval: 60_000,
  });

  const {
    data: boardTaskDistribution,
    isLoading: boardTaskDistributionLoading,
    isError: boardTaskDistributionError,
  } = useGetBoardTaskDistributionQuery(undefined, {
    pollingInterval: 60_000,
  });

  const {
    data: topAgents,
    isLoading: topAgentsLoading,
    isError: topAgentsError,
  } = useGetTopAgentsBySessionsQuery(
    { limit: 10 },
    {
      pollingInterval: 60_000,
    },
  );

  const {
    data: recentActivity,
    isLoading: activityLoading,
    isError: activityError,
  } = useGetRecentActivityQuery(
    { page: 1, perPage: activityPage * ACTIVITY_PER_PAGE },
    { pollingInterval: 60_000 },
  );

  const workflowStatus = workflowRunStats
    ? [
        {
          label: 'Completed',
          value: workflowRunStats.completed,
          total: workflowRunStats.total,
          color: WORKFLOW_STATUS_COLORS['Completed'],
        },
        {
          label: 'In Progress',
          value: workflowRunStats.inProgress,
          total: workflowRunStats.total,
          color: WORKFLOW_STATUS_COLORS['In Progress'],
        },
        {
          label: 'Failed',
          value: workflowRunStats.failed,
          total: workflowRunStats.total,
          color: WORKFLOW_STATUS_COLORS['Failed'],
        },
        {
          label: 'Queued',
          value: workflowRunStats.queued,
          total: workflowRunStats.total,
          color: WORKFLOW_STATUS_COLORS['Queued'],
        },
      ]
    : [];

  const platformStats = summary
    ? [
        {
          label: 'Sessions Launched',
          value: summary.sessionsLaunched.toLocaleString(),
          icon: <PlayCircleIcon sx={{ color: 'primary.main', fontSize: 20 }} />,
        },
        {
          label: 'Total Spend',
          value: formatSpend(summary.totalSpendCents),
          icon: <AttachMoneyIcon sx={{ color: 'success.main', fontSize: 20 }} />,
        },
        {
          label: 'Workflows',
          value: summary.workflowsCount.toLocaleString(),
          icon: <WorkflowsIcon sx={{ color: 'info.main', fontSize: 20 }} />,
        },
        {
          label: 'Board Tasks',
          value: summary.boardTasksCount.toLocaleString(),
          icon: <ViewKanbanIcon sx={{ color: 'warning.main', fontSize: 20 }} />,
        },
        {
          label: 'Users',
          value: summary.usersCount.toLocaleString(),
          icon: <AccountCircleIcon sx={{ color: 'secondary.main', fontSize: 20 }} />,
        },
        {
          label: 'Agents',
          value: summary.agentsCount.toLocaleString(),
          icon: <SmartToyIcon sx={{ color: 'error.main', fontSize: 20 }} />,
        },
        {
          label: 'Projects',
          value: summary.projectsCount.toLocaleString(),
          icon: <FolderIcon sx={{ color: 'primary.light', fontSize: 20 }} />,
        },
      ]
    : [];

  return (
    <Box sx={styles.container}>
      <Box sx={styles.pageHeader}>
        <Typography sx={styles.pageTitle}>Project Overview</Typography>
        <Typography sx={styles.pageSubtitle}>Platform-wide activity at a glance</Typography>
      </Box>

      {/* Platform Stats */}
      <Typography sx={styles.sectionTitle}>Platform Summary</Typography>
      {summaryError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load platform summary. Please refresh to try again.
        </Typography>
      )}
      <Box sx={styles.statsGrid}>
        {summaryLoading
          ? Array.from({ length: 7 }).map((_, i) => (
              <Card key={i} sx={styles.statCard} elevation={0}>
                <Box sx={styles.statIconWrap}>
                  <Skeleton variant="circular" width={20} height={20} />
                  <Skeleton variant="text" width={80} />
                </Box>
                <Skeleton variant="text" width={60} height={40} />
              </Card>
            ))
          : platformStats.map((stat) => (
              <Card key={stat.label} sx={styles.statCard} elevation={0}>
                <Box sx={styles.statIconWrap}>
                  {stat.icon}
                  <Typography sx={styles.statLabel}>{stat.label}</Typography>
                </Box>
                <Typography sx={styles.statValue}>{stat.value}</Typography>
              </Card>
            ))}
      </Box>

      {/* Two-column section */}
      <Box sx={styles.twoCol}>
        {/* Recent Activity */}
        <Card sx={styles.card} elevation={0}>
          <Typography sx={styles.sectionTitle}>Recent Activity</Typography>
          {activityError && (
            <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
              Failed to load recent activity. Please refresh to try again.
            </Typography>
          )}
          {activityLoading
            ? Array.from({ length: 5 }).map((_, i) => (
                <Box key={i} sx={styles.activityItem}>
                  <Skeleton variant="circular" width={8} height={8} sx={{ marginTop: '5px', flexShrink: 0 }} />
                  <Box sx={{ flex: 1 }}>
                    <Skeleton variant="text" width="80%" />
                    <Skeleton variant="text" width={60} />
                  </Box>
                </Box>
              ))
            : (recentActivity?.activities ?? []).map((item, idx) => (
                <Box key={idx} sx={styles.activityItem}>
                  <Box sx={{ ...styles.activityDot, backgroundColor: getActivityColor(item.eventType) }} />
                  <Box>
                    <Typography sx={styles.activityText}>{item.description}</Typography>
                    <Typography sx={styles.activityTime}>
                      {item.actorName} · {formatRelativeTime(item.occurredAt)}
                    </Typography>
                  </Box>
                </Box>
              ))}
          {!activityLoading && !activityError && (recentActivity?.activities ?? []).length === 0 && (
            <Typography sx={{ fontSize: '13px', color: 'text.disabled', py: '10px' }}>
              No recent activity found.
            </Typography>
          )}
          {!activityLoading &&
            recentActivity &&
            recentActivity.activities.length < recentActivity.meta.total && (
              <Button
                size="small"
                onClick={() => setActivityPage((p) => p + 1)}
                sx={{ mt: 1, fontSize: '12px', textTransform: 'none' }}
              >
                Load more
              </Button>
            )}
        </Card>

        {/* Workflow Status */}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          <Card sx={styles.card} elevation={0}>
            <Typography sx={styles.sectionTitle}>Workflow Runs</Typography>
            {workflowRunStatsError && (
              <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
                Failed to load workflow run stats. Please refresh to try again.
              </Typography>
            )}
            {workflowRunStatsLoading
              ? Array.from({ length: 4 }).map((_, i) => (
                  <Box key={i} sx={styles.progressRow}>
                    <Box sx={styles.progressLabel}>
                      <Skeleton variant="text" width={80} />
                      <Skeleton variant="text" width={60} />
                    </Box>
                    <Skeleton variant="rectangular" height={6} sx={{ borderRadius: 3 }} />
                  </Box>
                ))
              : workflowStatus.map((item) => (
                  <Box key={item.label} sx={styles.progressRow}>
                    <Box sx={styles.progressLabel}>
                      <Typography sx={styles.progressLabelText}>{item.label}</Typography>
                      <Typography sx={styles.progressLabelValue}>
                        {item.value}{' '}
                        <Typography component="span" sx={{ color: 'text.disabled', fontWeight: 400 }}>
                          / {item.total}
                        </Typography>
                      </Typography>
                    </Box>
                    <LinearProgress
                      variant="determinate"
                      value={item.total > 0 ? (item.value / item.total) * 100 : 0}
                      sx={{
                        height: 6,
                        borderRadius: 3,
                        backgroundColor: 'background.elevated',
                        '& .MuiLinearProgress-bar': { backgroundColor: item.color, borderRadius: 3 },
                      }}
                    />
                  </Box>
                ))}
          </Card>

          <Card sx={styles.card} elevation={0}>
            <Typography sx={styles.sectionTitle}>Top Agents by Sessions</Typography>
            {topAgentsError && (
              <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
                Failed to load top agents. Please refresh to try again.
              </Typography>
            )}
            {topAgentsLoading
              ? Array.from({ length: 4 }).map((_, i) => (
                  <Box key={i}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', py: '10px' }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Skeleton variant="circular" width={16} height={16} />
                        <Skeleton variant="text" width={120} />
                      </Box>
                      <Box sx={{ display: 'flex', gap: 1 }}>
                        <Skeleton variant="rectangular" width={80} height={20} sx={{ borderRadius: 1 }} />
                        <Skeleton variant="rectangular" width={60} height={20} sx={{ borderRadius: 1 }} />
                      </Box>
                    </Box>
                    {i < 3 && <Divider />}
                  </Box>
                ))
              : (topAgents ?? []).map((agent, idx) => (
                  <Box key={agent.rank}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', py: '10px' }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <SmartToyIcon sx={{ fontSize: 16, color: 'text.disabled' }} />
                        <Typography sx={{ fontSize: '13px', color: 'text.primary' }}>{agent.name}</Typography>
                        <Chip
                          label={agent.agentType}
                          size="small"
                          variant="outlined"
                          sx={{ fontSize: '10px', height: 16 }}
                        />
                      </Box>
                      <Box sx={{ display: 'flex', gap: 1 }}>
                        <Chip
                          label={`${agent.sessionsCount} sessions`}
                          size="small"
                          sx={{ fontSize: '11px', height: 20 }}
                        />
                        <Chip
                          label={formatSpend(agent.totalCostCents)}
                          size="small"
                          color="success"
                          variant="outlined"
                          sx={{ fontSize: '11px', height: 20 }}
                        />
                      </Box>
                    </Box>
                    {idx < (topAgents ?? []).length - 1 && <Divider />}
                  </Box>
                ))}
            {!topAgentsLoading && !topAgentsError && (topAgents ?? []).length === 0 && (
              <Typography sx={{ fontSize: '13px', color: 'text.disabled', py: '10px' }}>
                No agent sessions found.
              </Typography>
            )}
          </Card>
        </Box>
      </Box>

      {/* Tasks by status */}
      <Typography sx={styles.sectionTitle}>Board Task Distribution</Typography>
      {boardTaskDistributionError && (
        <Typography sx={{ color: 'error.main', fontSize: '13px', marginBottom: '16px' }}>
          Failed to load board task distribution. Please refresh to try again.
        </Typography>
      )}
      <Card
        sx={{
          ...styles.card,
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
          gap: '16px',
        }}
        elevation={0}
      >
        {boardTaskDistributionLoading
          ? Array.from({ length: 6 }).map((_, i) => (
              <Box
                key={i}
                sx={{
                  textAlign: 'center',
                  padding: '12px',
                  borderRadius: '8px',
                  backgroundColor: 'background.default',
                }}
              >
                <Skeleton variant="text" width={60} height={40} sx={{ margin: '0 auto' }} />
                <Skeleton variant="text" width={80} sx={{ margin: '4px auto 0' }} />
              </Box>
            ))
          : (boardTaskDistribution?.columns ?? []).map((col) => (
              <Box
                key={col.name}
                sx={{
                  textAlign: 'center',
                  padding: '12px',
                  borderRadius: '8px',
                  backgroundColor: 'background.default',
                }}
              >
                <Typography sx={{ fontSize: '28px', fontWeight: 700, color: 'text.primary' }}>{col.count}</Typography>
                <Typography sx={{ fontSize: '12px', color: 'text.secondary', marginTop: '4px' }}>{col.name}</Typography>
              </Box>
            ))}
        {!boardTaskDistributionLoading && boardTaskDistribution && (
          <Box
            sx={{
              textAlign: 'center',
              padding: '12px',
              borderRadius: '8px',
              backgroundColor: 'primary.main',
            }}
          >
            <Typography sx={{ fontSize: '28px', fontWeight: 700, color: 'primary.contrastText' }}>
              {boardTaskDistribution.total}
            </Typography>
            <Typography sx={{ fontSize: '12px', color: 'primary.contrastText', marginTop: '4px', opacity: 0.85 }}>
              Total
            </Typography>
          </Box>
        )}
      </Card>
    </Box>
  );
};

export default ProjectOverviewPanel;
