import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import HistoryIcon from '@mui/icons-material/History';
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
import { useStartPaladBuilderMutation, useGetPaladBuilderSessionsQuery } from 'features/palad-builder';
import { useLazyGetAgentModelsQuery } from 'shared/api/agentModelsApi';
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
  finished: 'success', running: 'warning', ready: 'info', failed: 'error', not_started: 'default',
};

const PaladBuilderPage = () => {
  const { projectId } = useParams({ strict: false }) as { projectId: string };
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const [startBuilder, { isLoading: isStarting }] = useStartPaladBuilderMutation();
  const { data: sessions, isLoading } = useGetPaladBuilderSessionsQuery(Number(projectId));
  const { data: currentUser } = useGetCurrentUserQuery();

  const configuredAgents = useMemo(
    () => AVAILABLE_AGENTS.filter((a) => currentUser?.configuredAgents?.includes(a.type)),
    [currentUser],
  );
  const [agentRuntime, setAgentRuntime] = useState<AgentType | ''>('');
  const [selectedModel, setSelectedModel] = useState<string>('');
  const [fetchModels, { data: models }] = useLazyGetAgentModelsQuery();

  // Set default runtime
  useEffect(() => {
    if (configuredAgents.length > 0 && !agentRuntime) {
      const def = currentUser?.defaultAgentRuntime;
      setAgentRuntime(def && configuredAgents.some((a) => a.type === def) ? def : configuredAgents[0].type);
    }
  }, [configuredAgents, currentUser, agentRuntime]);

  // Fetch models when runtime changes
  useEffect(() => {
    if (agentRuntime) {
      fetchModels(agentRuntime);
      setSelectedModel('');
    }
  }, [agentRuntime, fetchModels]);

  // Set default model from credential
  useEffect(() => {
    if (models && models.length > 0 && !selectedModel) {
      const credential = currentUser?.agentCredentials?.find((c) => c.agentType === agentRuntime);
      const defaultModel = credential?.defaultModel;
      if (defaultModel && models.some((m) => m.modelId === defaultModel)) {
        setSelectedModel(defaultModel);
      }
    }
  }, [models, selectedModel, currentUser, agentRuntime]);

  const activeSession = sessions?.find((s) => ['running', 'ready'].includes(s.state));

  const handleStart = async () => {
    if (activeSession) {
      navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(activeSession.id)) });
      return;
    }
    if (!agentRuntime) {
      enqueueSnackbar('Select an agent runtime', { variant: 'warning' });
      return;
    }
    try {
      const session = await startBuilder({
        projectId: Number(projectId),
        agentRuntime,
        preferredModel: selectedModel || undefined,
      }).unwrap();
      navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(session.id)) });
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

        {configuredAgents.length > 0 && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mb: 2, width: '100%', maxWidth: 400 }}>
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
                      <Box sx={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: AGENT_COLORS[agent.type] }} />
                      {agent.name}
                    </Box>
                  </MenuItem>
                ))}
              </Select>
            </FormControl>

            {models && models.length > 0 && (
              <FormControl fullWidth size="small">
                <InputLabel>Model (optional)</InputLabel>
                <Select
                  value={selectedModel}
                  label="Model (optional)"
                  onChange={(e) => setSelectedModel(e.target.value)}
                  displayEmpty
                >
                  <MenuItem value="">
                    <Typography sx={{ color: 'text.secondary', fontSize: 14 }}>Default</Typography>
                  </MenuItem>
                  {models.map((m) => (
                    <MenuItem key={m.modelId} value={m.modelId}>
                      <Box>
                        <Typography sx={{ fontSize: 14 }}>{m.displayName}</Typography>
                        {m.description && (
                          <Typography sx={{ fontSize: 11, color: 'text.secondary' }}>{m.description}</Typography>
                        )}
                      </Box>
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            )}
          </Box>
        )}

        <Button
          variant="contained"
          size="large"
          startIcon={<AutoFixHighIcon />}
          onClick={handleStart}
          disabled={isStarting || (!agentRuntime && !activeSession)}
        >
          {activeSession ? 'Continue Active Session' : 'Start Builder'}
        </Button>
      </Box>

      {isLoading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress /></Box>
      ) : sessions && sessions.length > 0 ? (
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>
            <HistoryIcon fontSize="small" />
            Previous Sessions
          </Typography>
          <TableContainer component={Paper} variant="outlined">
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Session</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Runtime</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell />
                </TableRow>
              </TableHead>
              <TableBody>
                {sessions.map((s) => (
                  <TableRow
                    key={s.id}
                    hover
                    sx={{ cursor: 'pointer' }}
                    onClick={() => navigate({ to: Routes.frontend.paladBuilderRunPath(projectId, String(s.id)) })}
                  >
                    <TableCell>#{s.id}</TableCell>
                    <TableCell>
                      <Chip label={s.state} size="small" color={stateColors[s.state] || 'default'} />
                    </TableCell>
                    <TableCell>{s.agentType || '—'}</TableCell>
                    <TableCell>{s.startedAt ? new Date(s.startedAt).toLocaleString() : '—'}</TableCell>
                    <TableCell>
                      <Button size="small" variant="text">Open</Button>
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
