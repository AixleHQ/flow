import AccountCircleIcon from '@mui/icons-material/AccountCircle';
import WorkflowsIcon from '@mui/icons-material/AccountTree';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import FolderIcon from '@mui/icons-material/Folder';
import PlayCircleIcon from '@mui/icons-material/PlayCircle';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import ViewKanbanIcon from '@mui/icons-material/ViewKanban';
import { Box, Card, Chip, Divider, LinearProgress, Skeleton, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import { useGetPlatformSummaryQuery } from '../api/platformSummaryApi';

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

const RECENT_ACTIVITY = [
  { text: 'Workflow "Data Ingestion Pipeline" completed successfully', time: '2 min ago', color: '#4caf50' },
  { text: 'Agent claude-sonnet-4-6 started new session #1284', time: '7 min ago', color: '#2196f3' },
  { text: 'Task "Fix auth middleware" moved to QA', time: '15 min ago', color: '#ff9800' },
  { text: 'User alex@palad.ai joined project "Backend API"', time: '1 hr ago', color: '#9c27b0' },
  { text: 'Workflow run #847 failed: timeout on step 3', time: '2 hr ago', color: '#f44336' },
  { text: 'New workflow "Email Notifications" created', time: '3 hr ago', color: '#00bcd4' },
  { text: 'Agent usage report generated for March 2026', time: '5 hr ago', color: '#607d8b' },
];

const WORKFLOW_STATUS = [
  { label: 'Completed', value: 724, total: 1050, color: '#4caf50' },
  { label: 'In Progress', value: 187, total: 1050, color: '#2196f3' },
  { label: 'Failed', value: 89, total: 1050, color: '#f44336' },
  { label: 'Queued', value: 50, total: 1050, color: '#ff9800' },
];

const AGENT_USAGE = [
  { label: 'claude-sonnet-4-6', sessions: 812, cost: '$2,104' },
  { label: 'claude-opus-4-6', sessions: 241, cost: '$1,287' },
  { label: 'claude-haiku-4-5', sessions: 147, cost: '$312' },
  { label: 'custom-agent-v2', sessions: 84, cost: '$138' },
];

interface ProjectOverviewPanelProps {
  projectId?: number;
}

const ProjectOverviewPanel = ({ projectId: _projectId }: ProjectOverviewPanelProps) => {
  void _projectId;
  const {
    data: summary,
    isLoading: summaryLoading,
    isError: summaryError,
  } = useGetPlatformSummaryQuery(undefined, {
    pollingInterval: 60_000,
  });

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
          {RECENT_ACTIVITY.map((item, idx) => (
            <Box key={idx} sx={styles.activityItem}>
              <Box sx={{ ...styles.activityDot, backgroundColor: item.color }} />
              <Box>
                <Typography sx={styles.activityText}>{item.text}</Typography>
                <Typography sx={styles.activityTime}>{item.time}</Typography>
              </Box>
            </Box>
          ))}
        </Card>

        {/* Workflow Status */}
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          <Card sx={styles.card} elevation={0}>
            <Typography sx={styles.sectionTitle}>Workflow Runs</Typography>
            {WORKFLOW_STATUS.map((item) => (
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
                  value={(item.value / item.total) * 100}
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
            {AGENT_USAGE.map((agent, idx) => (
              <Box key={agent.label}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', py: '10px' }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <SmartToyIcon sx={{ fontSize: 16, color: 'text.disabled' }} />
                    <Typography sx={{ fontSize: '13px', color: 'text.primary' }}>{agent.label}</Typography>
                  </Box>
                  <Box sx={{ display: 'flex', gap: 1 }}>
                    <Chip label={`${agent.sessions} sessions`} size="small" sx={{ fontSize: '11px', height: 20 }} />
                    <Chip
                      label={agent.cost}
                      size="small"
                      color="success"
                      variant="outlined"
                      sx={{ fontSize: '11px', height: 20 }}
                    />
                  </Box>
                </Box>
                {idx < AGENT_USAGE.length - 1 && <Divider />}
              </Box>
            ))}
          </Card>
        </Box>
      </Box>

      {/* Tasks by status */}
      <Typography sx={styles.sectionTitle}>Board Task Distribution</Typography>
      <Card
        sx={{
          ...styles.card,
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
          gap: '16px',
        }}
        elevation={0}
      >
        {[
          { label: 'Backlog', count: 34, color: '#607d8b' },
          { label: 'In Progress', count: 18, color: '#2196f3' },
          { label: 'Fix Tests', count: 7, color: '#ff9800' },
          { label: 'QA', count: 9, color: '#9c27b0' },
          { label: 'Code Review', count: 11, color: '#00bcd4' },
          { label: 'Done', count: 33, color: '#4caf50' },
        ].map((col) => (
          <Box
            key={col.label}
            sx={{ textAlign: 'center', padding: '12px', borderRadius: '8px', backgroundColor: 'background.default' }}
          >
            <Typography sx={{ fontSize: '28px', fontWeight: 700, color: col.color }}>{col.count}</Typography>
            <Typography sx={{ fontSize: '12px', color: 'text.secondary', marginTop: '4px' }}>{col.label}</Typography>
          </Box>
        ))}
      </Card>
    </Box>
  );
};

export default ProjectOverviewPanel;
