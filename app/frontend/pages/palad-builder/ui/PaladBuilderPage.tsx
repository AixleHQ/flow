import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import HistoryIcon from '@mui/icons-material/History';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  FormControl,
  InputLabel,
  MenuItem,
  Paper,
  Select,
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
import { useEffect, useMemo, useState } from 'react';

import { useGetCurrentUserQuery } from 'entities/user/api/currentUserApi';
import { AVAILABLE_AGENTS, AGENT_COLORS } from 'entities/user/model/agentConstants';
import type { AgentType } from 'entities/user/model/types';
import { useStartPaladBuilderMutation, useGetPaladBuilderStatusQuery } from 'features/palad-builder';
import { Routes } from 'shared/routes';

const styles = {
  root: { p: 4, maxWidth: 700, mx: 'auto' },
  hero: {
    display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center',
    py: 5, px: 4, mb: 4, borderRadius: 2,
    backgroundColor: 'background.paper', border: '1px solid', borderColor: 'divider',
  },
  heroIcon: { fontSize: 48, color: 'primary.main', mb: 1.5 },
  heroTitle: { fontSize: 24, fontWeight: 700, color: 'text.primary', mb: 0.5 },
  heroSubtitle: { fontSize: 14, color: 'text.secondary', maxWidth: 480, mb: 3 },
  configRow: { display: 'flex', gap: 2, mb: 2, width: '100%', maxWidth: 400 },
  section: { mb: 4 },
  sectionTitle: { fontSize: 16, fontWeight: 600, color: 'text.primary', mb: 1.5, display: 'flex', alignItems: 'center', gap: 1 },
} satisfies Record<string, SxProps>;

const stateColors: Record<string, 'success' | 'warning' | 'error' | 'info' | 'default'> = {
  completed: 'success', running: 'warning', paused: 'info', failed: 'error', cancelled: 'default', pending: 'default',
};

const PaladBuilderPage = () => {
  const { projectId } = useParams({ strict: false }) as { projectId: string };
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [startBuilder, { isLoading: isStarting }] = useStartPaladBuilderMutation();
  const { data: runs, isLoading } = useGetPaladBuilderStatusQuery(Number(projectId));
  const { data: currentUser } = useGetCurrentUserQuery();

  // Agent runtime selection
  const configuredAgents = useMemo(
    () => AVAILABLE_AGENTS.filter((a) => currentUser?.configuredAgents?.includes(a.type)),
    [currentUser],
  );
  const [agentRuntime, setAgentRuntime] = useState<AgentType | ''>('');

  // Set default runtime when user data loads
  useEffect(() => {
    if (configuredAgents.length > 0 && !agentRuntime) {
      const defaultRuntime = currentUser?.defaultAgentRuntime;
      if (defaultRuntime && configuredAgents.some((a) => a.type === defaultRuntime)) {
        setAgentRuntime(defaultRuntime);
      } else {
        setAgentRuntime(configuredAgents[0].type);
      }
    }
  }, [configuredAgents, currentUser, agentRuntime]);

  const activeRun = runs?.find((r) => ['pending', 'running', 'paused'].includes(r.state));

  const handleStart = async () => {
    if (activeRun) {
      navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(activeRun.id)) });
      return;
    }

    if (!agentRuntime) {
      enqueueSnackbar('Select an agent runtime', { variant: 'warning' });
      return;
    }

    try {
      const run = await startBuilder({ projectId: Number(projectId), agentRuntime }).unwrap();
      navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(run.id)) });
    } catch {
      enqueueSnackbar('Failed to start Palad Builder', { variant: 'error' });
    }
  };

  return (
    <Box sx={styles.root}>
      <Box sx={styles.hero}>
        <AutoFixHighIcon sx={styles.heroIcon} />
        <Typography sx={styles.heroTitle}>Palad Builder</Typography>
        <Typography sx={styles.heroSubtitle}>
          Build workflows with AI. Describe what you need — the builder creates agents, steps, board columns, and
          automation for you.
        </Typography>

        {/* Agent Runtime Selector */}
        {configuredAgents.length > 0 && (
          <Box sx={styles.configRow}>
            <FormControl fullWidth size="small">
              <InputLabel>Agent Runtime</InputLabel>
              <Select
                value={agentRuntime}
                label="Agent Runtime"
                onChange={(e) => setAgentRuntime(e.target.value as AgentType)}
              >
                {configuredAgents.map((agent) => (
                  <MenuItem key={agent.type} value={agent.type}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <Box
                        sx={{
                          width: 8, height: 8, borderRadius: '50%',
                          backgroundColor: AGENT_COLORS[agent.type],
                        }}
                      />
                      {agent.name}
                    </Box>
                  </MenuItem>
                ))}
              </Select>
            </FormControl>
          </Box>
        )}

        <Button
          variant="contained"
          size="large"
          startIcon={activeRun ? <PlayArrowIcon /> : <AutoFixHighIcon />}
          onClick={handleStart}
          disabled={isStarting || (!agentRuntime && !activeRun)}
        >
          {activeRun ? 'Continue Active Build' : 'Start Builder'}
        </Button>
      </Box>

      {/* Build History */}
      {isLoading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress /></Box>
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
                  <TableCell>Runtime</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell />
                </TableRow>
              </TableHead>
              <TableBody>
                {runs.map((run) => (
                  <TableRow
                    key={run.id}
                    hover
                    sx={{ cursor: 'pointer' }}
                    onClick={() => navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(run.id)) })}
                  >
                    <TableCell>#{run.id}</TableCell>
                    <TableCell>
                      <Chip label={run.state} size="small" color={stateColors[run.state] || 'default'} />
                    </TableCell>
                    <TableCell>{run.agentRuntime || '—'}</TableCell>
                    <TableCell>{run.startedAt ? new Date(run.startedAt).toLocaleString() : '—'}</TableCell>
                    <TableCell>
                      <Button size="small" variant="text">View</Button>
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
