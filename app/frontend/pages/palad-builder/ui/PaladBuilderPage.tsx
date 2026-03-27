import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import HistoryIcon from '@mui/icons-material/History';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  type SxProps,
} from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';

import {
  useStartPaladBuilderMutation,
  useGetPaladBuilderStatusQuery,
} from 'features/palad-builder';
import { Routes } from 'shared/routes';

const styles = {
  root: { p: 4, maxWidth: 900, mx: 'auto' },
  hero: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    textAlign: 'center',
    py: 6,
    px: 4,
    mb: 4,
    borderRadius: 2,
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
  },
  heroIcon: { fontSize: 56, color: 'primary.main', mb: 2 },
  heroTitle: { fontSize: 28, fontWeight: 700, color: 'text.primary', mb: 1 },
  heroSubtitle: { fontSize: 15, color: 'text.secondary', maxWidth: 500, mb: 3 },
  section: { mb: 4 },
  sectionTitle: { fontSize: 18, fontWeight: 600, color: 'text.primary', mb: 2, display: 'flex', alignItems: 'center', gap: 1 },
} satisfies Record<string, SxProps>;

const stateColors: Record<string, 'success' | 'warning' | 'error' | 'info' | 'default'> = {
  completed: 'success',
  running: 'warning',
  paused: 'info',
  failed: 'error',
  cancelled: 'default',
  pending: 'default',
};

const PaladBuilderPage = () => {
  const { projectId } = useParams({ strict: false }) as { projectId: string };
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [startBuilder, { isLoading: isStarting }] = useStartPaladBuilderMutation();
  const { data: runs, isLoading } = useGetPaladBuilderStatusQuery(Number(projectId));

  const activeRun = runs?.find((r) => ['pending', 'running', 'paused'].includes(r.state));

  const handleStart = async () => {
    if (activeRun) {
      navigate({ to: Routes.frontend.workflowRunPath(projectId, String(activeRun.id)) });
      return;
    }

    try {
      const run = await startBuilder(Number(projectId)).unwrap();
      navigate({ to: Routes.frontend.workflowRunPath(projectId, String(run.id)) });
    } catch {
      enqueueSnackbar('Failed to start Palad Builder', { variant: 'error' });
    }
  };

  const handleGoToRun = (runId: number) => {
    navigate({ to: Routes.frontend.workflowRunPath(projectId, String(runId)) });
  };

  return (
    <Box sx={styles.root}>
      <Box sx={styles.hero}>
        <AutoFixHighIcon sx={styles.heroIcon} />
        <Typography sx={styles.heroTitle}>Palad Builder</Typography>
        <Typography sx={styles.heroSubtitle}>
          Build complete workflow automations with AI. Describe what you need and the builder will create agents, steps,
          board columns, and trigger bindings for you.
        </Typography>
        <Button
          variant="contained"
          size="large"
          startIcon={activeRun ? <PlayArrowIcon /> : <AutoFixHighIcon />}
          onClick={handleStart}
          disabled={isStarting}
        >
          {activeRun ? 'Continue Active Build' : 'Start New Build'}
        </Button>
      </Box>

      {isLoading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
          <CircularProgress />
        </Box>
      ) : runs && runs.length > 0 ? (
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>
            <HistoryIcon fontSize="small" />
            Build History
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Run</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell>Completed</TableCell>
                  <TableCell />
                </TableRow>
              </TableHead>
              <TableBody>
                {runs.map((run) => (
                  <TableRow key={run.id} hover sx={{ cursor: 'pointer' }} onClick={() => handleGoToRun(run.id)}>
                    <TableCell>#{run.id}</TableCell>
                    <TableCell>
                      <Chip label={run.state} size="small" color={stateColors[run.state] || 'default'} />
                    </TableCell>
                    <TableCell>{run.startedAt ? new Date(run.startedAt).toLocaleString() : '—'}</TableCell>
                    <TableCell>{run.completedAt ? new Date(run.completedAt).toLocaleString() : '—'}</TableCell>
                    <TableCell>
                      <Button size="small" variant="text" onClick={() => handleGoToRun(run.id)}>
                        View
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Box>
      ) : null}
    </Box>
  );
};

export default PaladBuilderPage;
