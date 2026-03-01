import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { Box, Button, CircularProgress, Collapse, IconButton, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

import { useGetBoardActivitiesQuery } from '../api/boardApi';

import { ActivityItem } from './ActivityItem';

interface ActivityFeedPanelProps {
  projectId: number;
}

const PANEL_HEIGHT = 260;

const styles = {
  root: {
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    px: 2,
    py: 0.5,
    cursor: 'pointer',
    '&:hover': { bgcolor: 'action.hover' },
  },
  title: {
    fontSize: '13px',
    fontWeight: 600,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
  },
  content: {
    maxHeight: PANEL_HEIGHT,
    overflowY: 'auto',
  },
  empty: {
    py: 3,
    textAlign: 'center',
    color: 'text.disabled',
  },
  loadMore: {
    display: 'flex',
    justifyContent: 'center',
    py: 1,
  },
} satisfies Record<string, SxProps<Theme>>;

export const ActivityFeedPanel = ({ projectId }: ActivityFeedPanelProps) => {
  const [open, setOpen] = useState(false);
  const [page, setPage] = useState(1);

  const { data, isLoading } = useGetBoardActivitiesQuery({ projectId, page, perPage: 20 }, { skip: !open });

  const activities = data?.items || [];
  const hasMore = data?.meta ? data.meta.page < data.meta.totalPages : false;

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header} onClick={() => setOpen(!open)}>
        <Typography sx={styles.title}>Activity Feed</Typography>
        <IconButton size="small">{open ? <ExpandLessIcon /> : <ExpandMoreIcon />}</IconButton>
      </Box>
      <Collapse in={open}>
        <Box sx={styles.content}>
          {isLoading && (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
              <CircularProgress size={20} />
            </Box>
          )}
          {!isLoading && activities.length === 0 && <Typography sx={styles.empty}>No activity yet</Typography>}
          {activities.map((a) => (
            <ActivityItem key={a.id} activity={a} />
          ))}
          {hasMore && (
            <Box sx={styles.loadMore}>
              <Button size="small" onClick={() => setPage((p) => p + 1)}>
                Load more
              </Button>
            </Box>
          )}
        </Box>
      </Collapse>
    </Box>
  );
};
