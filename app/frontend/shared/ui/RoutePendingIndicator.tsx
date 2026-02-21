import { LinearProgress } from '@mui/material';
import { useRouterState } from '@tanstack/react-router';
import * as React from 'react';

const styles = {
  progress: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 1300,
    height: '2px',
  },
} as const;

/**
 * Route pending indicator component
 * Shows a loading bar at the top of the page when navigating between lazy-loaded routes
 */
export const RoutePendingIndicator: React.FC = () => {
  const isPending = useRouterState({
    select: (state) => state.isLoading || state.isTransitioning,
  });

  if (!isPending) {
    return null;
  }

  return <LinearProgress sx={styles.progress} />;
};
