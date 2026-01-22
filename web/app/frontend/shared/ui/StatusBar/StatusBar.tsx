import { Box, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

type SessionStatus = 'idle' | 'starting' | 'running' | 'stopping' | 'error' | 'completed';

interface IStatusBarProps {
  agent?: string;
  status: SessionStatus;
  cost?: number;
  duration?: string;
  user?: string;
}

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    height: '28px',
    paddingX: '12px',
    backgroundColor: 'background.elevated',
    borderTop: '1px solid',
    borderColor: 'divider',
    gap: '16px',
  },
  section: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  label: {
    fontSize: '11px',
    color: 'text.disabled',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  value: {
    fontSize: '12px',
    color: 'text.secondary',
    fontFamily: '"JetBrains Mono", monospace',
  },
  statusIndicator: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
  },
  cost: {
    fontSize: '12px',
    color: 'success.main',
    fontFamily: '"JetBrains Mono", monospace',
  },
  divider: {
    width: '1px',
    height: '16px',
    backgroundColor: 'divider',
  },
} satisfies Record<string, SxProps<Theme>>;

const getStatusColor = (status: SessionStatus): string => {
  switch (status) {
    case 'completed':
      return 'success.main';
    case 'running':
      return 'primary.main';
    case 'starting':
    case 'stopping':
      return 'warning.main';
    case 'error':
      return 'error.main';
    default:
      return 'text.disabled';
  }
};

const getStatusLabel = (status: SessionStatus): string => {
  switch (status) {
    case 'completed':
      return 'Completed';
    case 'running':
      return 'Running';
    case 'starting':
      return 'Starting...';
    case 'stopping':
      return 'Stopping...';
    case 'error':
      return 'Error';
    default:
      return 'Idle';
  }
};

const StatusBar = ({ agent, status, cost, duration, user }: IStatusBarProps) => {
  return (
    <Box sx={styles.root}>
      {/* Agent */}
      {agent && (
        <>
          <Box sx={styles.section}>
            <Typography sx={styles.label}>Agent</Typography>
            <Typography sx={styles.value}>{agent}</Typography>
          </Box>
          <Box sx={styles.divider} />
        </>
      )}

      {/* Status */}
      <Box sx={styles.section}>
        <Box
          sx={{
            ...styles.statusIndicator,
            backgroundColor: getStatusColor(status),
            ...(status === 'running' && {
              animation: 'pulse 2s infinite',
              '@keyframes pulse': {
                '0%, 100%': { opacity: 1 },
                '50%': { opacity: 0.5 },
              },
            }),
          }}
        />
        <Typography sx={styles.value}>{getStatusLabel(status)}</Typography>
      </Box>

      {/* User (if running by someone else) */}
      {user && (
        <>
          <Box sx={styles.divider} />
          <Box sx={styles.section}>
            <Typography sx={styles.label}>User</Typography>
            <Typography sx={styles.value}>{user}</Typography>
          </Box>
        </>
      )}

      {/* Spacer */}
      <Box sx={{ flex: 1 }} />

      {/* Duration */}
      {duration && (
        <>
          <Box sx={styles.section}>
            <Typography sx={styles.label}>Duration</Typography>
            <Typography sx={styles.value}>{duration}</Typography>
          </Box>
          <Box sx={styles.divider} />
        </>
      )}

      {/* Cost */}
      {cost !== undefined && (
        <Box sx={styles.section}>
          <Typography sx={styles.label}>Cost</Typography>
          <Typography sx={styles.cost}>${cost.toFixed(2)}</Typography>
        </Box>
      )}
    </Box>
  );
};

export default StatusBar;
