import { Box, Button, CircularProgress, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

import { useGetTaskActivitiesQuery } from '../api/boardApi';

import { ActivityItem } from './ActivityItem';

interface ActivityTabProps {
  taskId: number;
  projectId: number;
}

const styles = {
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

export const ActivityTab = ({ taskId, projectId }: ActivityTabProps) => {
  const [page, setPage] = useState(1);
  const { data, isLoading } = useGetTaskActivitiesQuery({ projectId, taskId, page, perPage: 15 });

  const activities = data?.items || [];
  const hasMore = data?.meta ? data.meta.page < data.meta.totalPages : false;

  if (isLoading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
        <CircularProgress size={20} />
      </Box>
    );
  }

  if (activities.length === 0) {
    return <Typography sx={styles.empty}>No activity for this task</Typography>;
  }

  return (
    <Box>
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
  );
};
