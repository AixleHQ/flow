import { Box, Button, Card, CardContent, Chip, Grid, Paper, Typography, CircularProgress } from '@mui/material';
import { useState, useRef } from 'react';
import { enqueueSnackbar } from 'notistack';

import type { AgentType } from 'entities/terminal-session/model/types';
import {
  useCreateTerminalSessionMutation,
  useCancelSessionMutation,
  useGetTerminalSessionQuery,
} from 'shared/api/terminalSessionApi';

const AGENT_TYPES: { type: AgentType; label: string; color: string }[] = [
  { type: 'claude_code', label: 'Claude Code', color: '#D97706' },
  { type: 'cursor_cli', label: 'Cursor CLI', color: '#7C3AED' },
  { type: 'codex', label: 'Codex', color: '#059669' },
  { type: 'gemini_cli', label: 'Gemini CLI', color: '#2563EB' },
];

interface AgentTerminalProps {
  agentType: AgentType;
  label: string;
  color: string;
}

const AgentTerminal: React.FC<AgentTerminalProps> = ({ agentType, label, color }) => {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [iframeLoaded, setIframeLoaded] = useState(false);

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [cancelSession, { isLoading: isCancelling }] = useCancelSessionMutation();

  // Poll session status
  const { data: sessionData } = useGetTerminalSessionQuery(sessionId!, {
    skip: !sessionId,
    pollingInterval: 2000,
  });

  const session = sessionData?.data;

  // Build ttyd URL from websocket URL
  // websocket_url: ws://localhost/s/26/tty/ws -> http://localhost/s/26/tty
  const ttydUrl = session?.websocketUrl
    ? session.websocketUrl.replace('ws://', 'http://').replace('/ws', '')
    : null;

  // Start session
  const handleStart = async () => {
    try {
      const result = await createSession({
        terminalSession: {
          sessionType: 'auth_setup',
          agentType,
        },
      }).unwrap();

      setSessionId(result.data.id);
      setIframeLoaded(false);
      enqueueSnackbar(`${label} session started`, { variant: 'success' });
    } catch (error) {
      enqueueSnackbar(`Failed to start ${label}`, { variant: 'error' });
      console.error('Failed to create terminal session:', error);
    }
  };

  // Stop session
  const handleStop = async () => {
    if (!sessionId) return;

    try {
      await cancelSession(sessionId).unwrap();
      setSessionId(null);
      setIframeLoaded(false);
      enqueueSnackbar(`${label} session stopped`, { variant: 'info' });
    } catch (error) {
      enqueueSnackbar(`Failed to stop ${label}`, { variant: 'error' });
    }
  };

  const handleIframeLoad = () => {
    setIframeLoaded(true);
    iframeRef.current?.focus();
  };

  const getStatusChip = () => {
    if (!session) return <Chip size="small" label="Idle" />;
    if (session.errorMessage) return <Chip size="small" label="Error" color="error" />;
    if (session.state !== 'running') return <Chip size="small" label={session.state} color="default" />;
    if (!iframeLoaded) return <Chip size="small" label="Connecting..." color="warning" />;
    return <Chip size="small" label="Connected" color="success" />;
  };

  const isRunning = session?.state === 'running';

  return (
    <Card
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        borderTop: `3px solid ${color}`,
      }}
    >
      <CardContent sx={{ py: 1.5, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Typography variant="subtitle1" fontWeight={600}>
            {label}
          </Typography>
          {getStatusChip()}
        </Box>
        <Box sx={{ display: 'flex', gap: 1 }}>
          {!sessionId ? (
            <Button
              size="small"
              variant="contained"
              onClick={handleStart}
              disabled={isCreating}
              startIcon={isCreating ? <CircularProgress size={14} /> : undefined}
              sx={{ bgcolor: color }}
            >
              Start
            </Button>
          ) : (
            <Button
              size="small"
              variant="outlined"
              color="error"
              onClick={handleStop}
              disabled={isCancelling}
              startIcon={isCancelling ? <CircularProgress size={14} /> : undefined}
            >
              Stop
            </Button>
          )}
        </Box>
      </CardContent>

      {/* Debug info */}
      {session && (
        <Box sx={{ px: 2, pb: 1 }}>
          <Typography variant="caption" color="text.secondary" component="div">
            Session ID: {session.id} | Container: {session.containerId || 'N/A'} | State: {session.state}
          </Typography>
          <Typography variant="caption" color="text.secondary" component="div" sx={{ wordBreak: 'break-all' }}>
            TTY URL: {ttydUrl || 'N/A'}
          </Typography>
          {session.errorMessage && (
            <Typography variant="caption" color="error" component="div">
              Error: {session.errorMessage}
            </Typography>
          )}
        </Box>
      )}

      {/* Terminal iframe */}
      <Box
        sx={{
          flex: 1,
          minHeight: 250,
          bgcolor: '#1e1e1e',
          position: 'relative',
        }}
      >
        {isRunning && ttydUrl ? (
          <>
            {!iframeLoaded && (
              <Box
                sx={{
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  bgcolor: '#1e1e1e',
                  zIndex: 1,
                }}
              >
                <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
                <Typography variant="caption" sx={{ mt: 1, color: '#d4d4d4' }}>
                  Connecting to terminal...
                </Typography>
              </Box>
            )}
            <iframe
              ref={iframeRef}
              src={ttydUrl}
              style={{
                width: '100%',
                height: '100%',
                border: 'none',
                backgroundColor: '#000',
              }}
              title={`${label} Terminal`}
              onLoad={handleIframeLoad}
            />
          </>
        ) : (
          <Box
            sx={{
              height: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#808080',
            }}
          >
            <Typography variant="body2">
              {session?.errorMessage
                ? 'Session failed - check error above'
                : session
                  ? `Waiting for container (${session.state})...`
                  : 'Click Start to launch terminal'}
            </Typography>
          </Box>
        )}
      </Box>
    </Card>
  );
};

export const TerminalTestPage: React.FC = () => {
  return (
    <Box sx={{ p: 3, height: '100vh', bgcolor: '#f5f5f5' }}>
      <Paper sx={{ p: 2, mb: 3 }}>
        <Typography variant="h5" gutterBottom>
          Terminal Test Page
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Test all 4 agent types simultaneously. Click &quot;Start&quot; to launch a terminal session for each agent.
        </Typography>
        <Box sx={{ mt: 2, p: 2, bgcolor: '#fff3cd', borderRadius: 1 }}>
          <Typography variant="body2">
            <strong>Architecture:</strong> Rails (Control Plane) → Traefik (Data Plane) → Container (ttyd)
          </Typography>
          <Typography variant="body2" sx={{ mt: 1 }}>
            <strong>TTY Route:</strong> <code>/s/&#123;session_id&#125;/tty</code> → Traefik ForwardAuth → Container:7681
          </Typography>
        </Box>
      </Paper>

      <Grid container spacing={2} sx={{ height: 'calc(100% - 180px)' }}>
        {AGENT_TYPES.map(({ type, label, color }) => (
          <Grid item xs={12} md={6} key={type} sx={{ height: '50%' }}>
            <AgentTerminal agentType={type} label={label} color={color} />
          </Grid>
        ))}
      </Grid>
    </Box>
  );
};
