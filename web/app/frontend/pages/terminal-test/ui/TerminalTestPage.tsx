import {
  Box,
  Button,
  Paper,
  Typography,
  CircularProgress,
  ToggleButton,
  ToggleButtonGroup,
  IconButton,
  Chip,
} from '@mui/material';
import { enqueueSnackbar } from 'notistack';
import { useState, useEffect } from 'react';
import { useParams, useNavigate } from '@tanstack/react-router';

import type { AgentType, ITerminalSession } from 'entities/terminal-session/model/types';
import {
  useCreateTerminalSessionMutation,
  useCancelSessionMutation,
  useGetTerminalSessionQuery,
} from 'shared/api/terminalSessionApi';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const AGENT_TYPES: { type: AgentType; label: string; color: string }[] = [
  { type: 'claude_code', label: 'Claude Code', color: '#D97706' },
  { type: 'cursor_cli', label: 'Cursor CLI', color: '#7C3AED' },
  { type: 'codex', label: 'Codex', color: '#059669' },
  { type: 'gemini_cli', label: 'Gemini CLI', color: '#2563EB' },
];

type SessionType = 'auth_setup' | 'agent_session';

const CloseIcon = () => <span style={{ fontSize: '16px' }}>✕</span>;

export const TerminalTestPage: React.FC = () => {
  const params = useParams({ strict: false });
  const navigate = useNavigate();
  const routeToken = (params as { routeToken?: string }).routeToken;

  const [selectedAgent, setSelectedAgent] = useState<AgentType>('claude_code');
  const [sessionType, setSessionType] = useState<SessionType>('agent_session');
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [session, setSession] = useState<ITerminalSession | null>(null);

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [cancelSession, { isLoading: isCancelling }] = useCancelSessionMutation();

  // Fetch existing session by routeToken if provided
  const { data: existingSession, isLoading: isLoadingExisting } = useGetTerminalSessionQuery(
    routeToken as string,
    { skip: !routeToken }
  );

  // When existing session is loaded, use it
  useEffect(() => {
    if (existingSession?.data) {
      setSessionId(existingSession.data.id);
      setSession(existingSession.data);
      // Set agent type from session
      if (existingSession.data.agentType) {
        setSelectedAgent(existingSession.data.agentType);
      }
    }
  }, [existingSession]);

  const selectedAgentInfo = AGENT_TYPES.find((a) => a.type === selectedAgent)!;

  const handleAgentChange = (_: React.MouseEvent<HTMLElement>, newAgent: AgentType | null) => {
    if (newAgent) {
      setSelectedAgent(newAgent);
    }
  };

  const handleSessionTypeChange = (_: React.MouseEvent<HTMLElement>, newType: SessionType | null) => {
    if (newType) {
      setSessionType(newType);
    }
  };

  const handleStart = async () => {
    try {
      const result = await createSession({
        terminalSession: {
          sessionType: sessionType,
          agentType: selectedAgent,
        },
      }).unwrap();

      setSessionId(result.data.id);
      const modeLabel = sessionType === 'agent_session' ? '(with credentials)' : '(auth)';
      enqueueSnackbar(`${selectedAgentInfo.label} session started ${modeLabel}`, { variant: 'success' });
    } catch (error) {
      enqueueSnackbar(`Failed to start ${selectedAgentInfo.label}`, { variant: 'error' });
      console.error('Failed to create terminal session:', error);
    }
  };

  const handleStop = async () => {
    if (!sessionId) return;

    try {
      await cancelSession(sessionId).unwrap();
      setSessionId(null);
      setSession(null);
      // Navigate back to terminal-test without routeToken
      if (routeToken) {
        navigate({ to: '/terminal-test' });
      }
      enqueueSnackbar('Session stopped', { variant: 'info' });
    } catch {
      enqueueSnackbar('Failed to stop session', { variant: 'error' });
    }
  };

  const handleSessionUpdate = (updatedSession: ITerminalSession) => {
    setSession(updatedSession);

    // Update URL with route_token when session becomes running
    if (updatedSession.state === 'running' && updatedSession.routeToken && !routeToken) {
      navigate({ to: '/terminal-test/$routeToken', params: { routeToken: updatedSession.routeToken } });
    }
  };

  const getStatusChip = () => {
    if (!session) return null;
    if (session.errorMessage) return <Chip size="small" label="Error" color="error" />;
    if (session.state === 'running') return <Chip size="small" label="Running" color="success" />;
    return <Chip size="small" label={session.state} color="default" />;
  };

  // Loading existing session
  if (routeToken && isLoadingExisting) {
    return (
      <Box sx={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <CircularProgress />
        <Typography sx={{ ml: 2 }}>Loading session...</Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ height: '100vh', display: 'flex', flexDirection: 'column', bgcolor: '#f5f5f5' }}>
      {/* Header */}
      <Paper sx={{ p: 2, borderRadius: 0, flexShrink: 0 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
            <Typography variant="h6">Terminal Test</Typography>

            {/* Session type selector */}
            <ToggleButtonGroup
              value={sessionType}
              exclusive
              onChange={handleSessionTypeChange}
              size="small"
              disabled={!!sessionId}
            >
              <ToggleButton value="agent_session">With Credentials</ToggleButton>
              <ToggleButton value="auth_setup">Auth Setup</ToggleButton>
            </ToggleButtonGroup>

            {/* Agent selector */}
            <ToggleButtonGroup
              value={selectedAgent}
              exclusive
              onChange={handleAgentChange}
              size="small"
              disabled={!!sessionId}
            >
              {AGENT_TYPES.map(({ type, label, color }) => (
                <ToggleButton
                  key={type}
                  value={type}
                  sx={{
                    '&.Mui-selected': {
                      bgcolor: color,
                      color: '#fff',
                      '&:hover': {
                        bgcolor: color,
                      },
                    },
                  }}
                >
                  {label}
                </ToggleButton>
              ))}
            </ToggleButtonGroup>

            {/* Start/Stop button */}
            {!sessionId ? (
              <Button
                variant="contained"
                onClick={handleStart}
                disabled={isCreating}
                startIcon={isCreating ? <CircularProgress size={16} color="inherit" /> : undefined}
                sx={{ bgcolor: selectedAgentInfo.color }}
              >
                Start Session
              </Button>
            ) : (
              <Button
                variant="outlined"
                color="error"
                onClick={handleStop}
                disabled={isCancelling}
                startIcon={isCancelling ? <CircularProgress size={16} color="inherit" /> : undefined}
              >
                Stop
              </Button>
            )}
          </Box>

          {/* Session info */}
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {session && (
              <>
                {getStatusChip()}
                <Typography variant="caption" color="text.secondary">
                  Session #{session.id}
                </Typography>
                {session.containerId && (
                  <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>
                    {session.containerId.slice(0, 12)}
                  </Typography>
                )}
                <IconButton size="small" onClick={handleStop} disabled={isCancelling}>
                  <CloseIcon />
                </IconButton>
              </>
            )}
          </Box>
        </Box>

        {/* Debug info */}
        {session && (
          <Box sx={{ mt: 1, pt: 1, borderTop: '1px solid #eee' }}>
            <Typography variant="caption" color="text.secondary" component="div" sx={{ fontFamily: 'monospace' }}>
              WebSocket: {session.websocketUrl || 'N/A'}
            </Typography>
            {session.errorMessage && (
              <Typography variant="caption" color="error" component="div">
                Error: {session.errorMessage}
              </Typography>
            )}
          </Box>
        )}
      </Paper>

      {/* Terminal Widget */}
      <Box sx={{ flex: 1, overflow: 'hidden' }}>
        {sessionId ? (
          <TerminalSessionWidget
            sessionId={sessionId}
            showFileTree={true}
            showFileViewer={true}
            showTerminal={true}
            onSessionUpdate={handleSessionUpdate}
          />
        ) : (
          <Box
            sx={{
              height: '100%',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 2,
              color: '#666',
            }}
          >
            <Typography variant="h6">Select an agent and click Start</Typography>
            <Typography variant="body2" color="text.secondary">
              The terminal session will appear here with file tree, file viewer, and terminal panels.
            </Typography>
          </Box>
        )}
      </Box>
    </Box>
  );
};
