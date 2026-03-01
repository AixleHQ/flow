import AccessTimeIcon from '@mui/icons-material/AccessTime';
import { Box, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import type { BoardActivity } from 'entities/board-task';

const styles = {
  root: {
    display: 'flex',
    gap: 1,
    py: 1,
    px: 1.5,
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  icon: {
    mt: 0.3,
    color: 'text.secondary',
    fontSize: '16px',
  },
  content: {
    flex: 1,
    minWidth: 0,
  },
  description: {
    fontSize: '13px',
    lineHeight: 1.4,
  },
  time: {
    fontSize: '11px',
    color: 'text.disabled',
    mt: 0.25,
  },
} satisfies Record<string, SxProps<Theme>>;

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export const ActivityItem = ({ activity }: { activity: BoardActivity }) => (
  <Box sx={styles.root}>
    <AccessTimeIcon sx={styles.icon} />
    <Box sx={styles.content}>
      <Typography sx={styles.description}>{activity.description}</Typography>
      <Typography sx={styles.time}>{timeAgo(activity.createdAt)}</Typography>
    </Box>
  </Box>
);
