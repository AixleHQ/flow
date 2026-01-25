import { Box, Button, CircularProgress, Typography } from '@mui/material';
import { enqueueSnackbar } from 'notistack';
import { useCallback, useEffect, useState, useRef } from 'react';

import type { AgentType, ITerminalSession } from 'entities/terminal-session/model/types';
import {
  useCreateTerminalSessionMutation,
  useFinishAuthMutation,
  useCancelSessionMutation,
} from 'shared/api/terminalSessionApi';
import { TerminalSessionWidget } from 'widgets/terminal-session';

interface AuthStatusResponse {
  authenticated: boolean;
}

interface AgentAuthTerminalProps {
  agentType: AgentType;
  onAuthComplete?: () => void;
  onCancel?: () => void;
}

export const AgentAuthTerminal: React.FC<AgentAuthTerminalProps> = ({ agentType, onAuthComplete, onCancel }) => {
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [session, setSession] = useState<ITerminalSession | null>(null);
  const [authDetected, setAuthDetected] = useState(false);
  const finishingRef = useRef(false);
  const pollingRef = useRef<NodeJS.Timeout | null>(null);

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [finishAuth, { isLoading: isFinishing }] = useFinishAuthMutation();
  const [cancelSession, { isLoading: isCancelling }] = useCancelSessionMutation();

  const handleSessionUpdate = useCallback((s: ITerminalSession) => setSession(s), []);

  const handleStart = async () => {
    try {
      const result = await createSession({
        terminalSession: { sessionType: 'auth_setup', agentType },
      }).unwrap();
      setSessionId(result.data.id);
    } catch {
      enqueueSnackbar('Failed to start session', { variant: 'error' });
    }
  };

  const handleFinish = useCallback(async () => {
    if (!sessionId || finishingRef.current) return;
    finishingRef.current = true;
    try {
      await finishAuth(sessionId).unwrap();
      enqueueSnackbar('Authentication saved!', { variant: 'success' });
      onAuthComplete?.();
    } catch {
      enqueueSnackbar('Failed to finish', { variant: 'error' });
      finishingRef.current = false;
    }
  }, [sessionId, finishAuth, onAuthComplete]);

  const handleCancel = async () => {
    if (!sessionId) {
      onCancel?.();
      return;
    }
    try {
      await cancelSession(sessionId).unwrap();
      onCancel?.();
    } catch {
      enqueueSnackbar('Failed to cancel', { variant: 'error' });
    }
  };

  // Poll /auth endpoint to detect authentication
  useEffect(() => {
    console.log('[AgentAuthTerminal] Polling effect:', {
      routeToken: session?.routeToken,
      state: session?.state,
      authDetected,
    });

    if (!session?.routeToken || session.state !== 'running' || authDetected) {
      console.log('[AgentAuthTerminal] Skipping polling - conditions not met');
      return;
    }

    console.log('[AgentAuthTerminal] Starting auth polling...');

    const checkAuth = async () => {
      try {
        // Use Traefik base URL (from Settings via gon) for /t/... routes
        const baseUrl = (window as unknown as { Settings?: { traefikHttpBase?: string } }).Settings?.traefikHttpBase || '';
        const url = `${baseUrl}/t/${session.routeToken}/fs/auth`;
        console.log('[AgentAuthTerminal] Checking auth at:', url);
        const response = await fetch(url, { credentials: 'include' });
        if (response.ok) {
          const data: AuthStatusResponse = await response.json();
          console.log('[AgentAuthTerminal] Auth response:', data);
          if (data.authenticated && !authDetected) {
            console.log('[AgentAuthTerminal] Auth detected via polling!');
            setAuthDetected(true);
            enqueueSnackbar('Authentication detected! Click "Finish" to save.', { variant: 'success' });
          }
        } else {
          console.log('[AgentAuthTerminal] Auth check failed:', response.status);
        }
      } catch (e) {
        console.log('[AgentAuthTerminal] Auth check error:', e);
      }
    };

    // Check immediately
    checkAuth();

    // Poll every 2 seconds
    pollingRef.current = setInterval(checkAuth, 2000);

    return () => {
      if (pollingRef.current) {
        console.log('[AgentAuthTerminal] Stopping auth polling');
        clearInterval(pollingRef.current);
        pollingRef.current = null;
      }
    };
  }, [session?.routeToken, session?.state, authDetected]);

  // Auto-complete when collected
  useEffect(() => {
    if (session?.state === 'collected') onAuthComplete?.();
  }, [session?.state, onAuthComplete]);

  const isRunning = session?.state === 'running';
  const canCancel = session?.state && !['collected', 'cancelled'].includes(session.state);

  // Not started - show start button
  if (!sessionId) {
    return (
      <Box sx={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: '#1e1e1e' }}>
        <Button
          variant="contained"
          onClick={handleStart}
          disabled={isCreating}
          startIcon={isCreating ? <CircularProgress size={16} /> : undefined}
        >
          Start Authentication
        </Button>
      </Box>
    );
  }

  // Session started - show terminal with action buttons
  return (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: '#1e1e1e' }}>
      {/* Header with session info */}
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, p: 1, borderBottom: '1px solid #3d3d3d' }}>
        <Typography variant="body2" sx={{ color: '#888' }}>
          {agentType}
        </Typography>
        {session?.routeToken && (
          <Typography variant="caption" sx={{ color: '#666', fontFamily: 'monospace' }}>
            {session.routeToken}
          </Typography>
        )}
        {session?.state && (
          <Typography variant="caption" sx={{ color: session.state === 'running' ? '#4caf50' : '#888' }}>
            {session.state}
          </Typography>
        )}
        {authDetected && (
          <Typography variant="caption" sx={{ color: '#4caf50', fontWeight: 'bold' }}>
            Auth detected
          </Typography>
        )}
      </Box>

      {/* Terminal */}
      <Box sx={{ flex: 1, overflow: 'hidden' }}>
        <TerminalSessionWidget
          sessionId={sessionId}
          showFileTree={false}
          showFileViewer={false}
          showTerminal={true}
          onSessionUpdate={handleSessionUpdate}
        />
      </Box>

      {/* Action buttons */}
      <Box sx={{ display: 'flex', gap: 1, p: 1, borderTop: '1px solid #3d3d3d' }}>
        {isRunning && (
          <Button
            variant="contained"
            color="success"
            size="small"
            onClick={handleFinish}
            disabled={isFinishing}
          >
            {isFinishing ? 'Saving...' : 'Save Authentication'}
          </Button>
        )}
        {canCancel && (
          <Button
            variant="outlined"
            color="error"
            size="small"
            onClick={handleCancel}
            disabled={isCancelling}
          >
            Cancel
          </Button>
        )}
      </Box>
    </Box>
  );
};
