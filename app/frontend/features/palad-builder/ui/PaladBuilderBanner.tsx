import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import { Box, Button, Typography, type SxProps } from '@mui/material';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { type FC } from 'react';

import { Routes } from 'shared/routes';

import { useStartPaladBuilderMutation, useGetPaladBuilderStatusQuery } from '../api/paladBuilderApi';

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '16px 20px',
    mb: 3,
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'primary.main',
    backgroundColor: 'background.elevated',
    backgroundImage: 'linear-gradient(135deg, rgba(99, 102, 241, 0.05) 0%, rgba(168, 85, 247, 0.05) 100%)',
  },
  left: {
    display: 'flex',
    alignItems: 'center',
    gap: 2,
  },
  icon: {
    fontSize: 32,
    color: 'primary.main',
  },
  title: {
    fontSize: 16,
    fontWeight: 600,
    color: 'text.primary',
  },
  subtitle: {
    fontSize: 13,
    color: 'text.secondary',
  },
} satisfies Record<string, SxProps>;

interface PaladBuilderBannerProps {
  projectId: number;
}

export const PaladBuilderBanner: FC<PaladBuilderBannerProps> = ({ projectId }) => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [startBuilder, { isLoading }] = useStartPaladBuilderMutation();
  const { data: runs } = useGetPaladBuilderStatusQuery(projectId);

  const activeRun = runs?.find((r) => ['pending', 'running', 'paused'].includes(r.state));

  const handleStart = async () => {
    if (activeRun) {
      navigate({ to: Routes.frontend.workflowRunPath(String(projectId), String(activeRun.id)) });
      return;
    }

    try {
      const run = await startBuilder(projectId).unwrap();
      navigate({ to: Routes.frontend.workflowRunPath(String(projectId), String(run.id)) });
    } catch {
      enqueueSnackbar('Failed to start Palad Builder', { variant: 'error' });
    }
  };

  return (
    <Box sx={styles.root}>
      <Box sx={styles.left}>
        <AutoFixHighIcon sx={styles.icon} />
        <Box>
          <Typography sx={styles.title}>Palad Builder</Typography>
          <Typography sx={styles.subtitle}>
            Create workflows with AI assistance. Describe what you need — the builder creates agents, steps, board
            columns, and automation for you.
          </Typography>
        </Box>
      </Box>
      <Button
        variant="contained"
        startIcon={activeRun ? <PlayArrowIcon /> : <AutoFixHighIcon />}
        onClick={handleStart}
        disabled={isLoading}
        sx={{ whiteSpace: 'nowrap' }}
      >
        {activeRun ? 'Continue Building' : 'Start Builder'}
      </Button>
    </Box>
  );
};
