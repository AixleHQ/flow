import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import { Box, Button, Typography, type SxProps } from '@mui/material';
import { useNavigate } from '@tanstack/react-router';
import { type FC } from 'react';

import { Routes } from 'shared/routes';

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '12px 16px',
    mb: 2,
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'primary.main',
    backgroundColor: 'background.elevated',
    backgroundImage: 'linear-gradient(135deg, rgba(99, 102, 241, 0.05) 0%, rgba(168, 85, 247, 0.05) 100%)',
  },
  left: { display: 'flex', alignItems: 'center', gap: 1.5 },
  icon: { fontSize: 28, color: 'primary.main' },
  title: { fontSize: 14, fontWeight: 600, color: 'text.primary' },
  subtitle: { fontSize: 12, color: 'text.secondary' },
} satisfies Record<string, SxProps>;

interface PaladBuilderBannerProps {
  projectId: number;
}

export const PaladBuilderBanner: FC<PaladBuilderBannerProps> = ({ projectId }) => {
  const navigate = useNavigate();

  return (
    <Box sx={styles.root}>
      <Box sx={styles.left}>
        <AutoFixHighIcon sx={styles.icon} />
        <Box>
          <Typography sx={styles.title}>Palad Builder</Typography>
          <Typography sx={styles.subtitle}>Build workflows with AI — agents, steps, board automation</Typography>
        </Box>
      </Box>
      <Button
        variant="contained"
        size="small"
        startIcon={<AutoFixHighIcon />}
        onClick={() => navigate({ to: Routes.frontend.paladBuilderPath(String(projectId)) })}
      >
        Open Builder
      </Button>
    </Box>
  );
};
