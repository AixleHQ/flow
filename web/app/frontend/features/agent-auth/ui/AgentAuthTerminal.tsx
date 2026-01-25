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
  const authCompleteCalledRef = useRef(false);

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [finishAuth, { isLoading: isFinishing }] = useFinishAuthMutation();
  const [cancelSession, { isLoading: isCancelling }] = useCancelSessionMutation();

  const handleSessionUpdate = useCallback((s: ITerminalSession) => setSession(s), []);

  // Stop polling helper - defined early so it can be used in handlers
  const stopPolling = useCallback(() => {
    if (pollingRef.current) {
      clearInterval(pollingRef.current);
      pollingRef.current = null;
    }
  }, []);

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
    stopPolling(); // Stop polling immediately
    try {
      await finishAuth(sessionId).unwrap();
      enqueueSnackbar('Authentication saved!', { variant: 'success' });
      if (!authCompleteCalledRef.current) {
        authCompleteCalledRef.current = true;
        onAuthComplete?.();
      }
    } catch {
      enqueueSnackbar('Failed to finish', { variant: 'error' });
      finishingRef.current = false;
    }
  }, [sessionId, finishAuth, onAuthComplete, stopPolling]);

  const handleCancel = async () => {
    if (!sessionId) {
      onCancel?.();
      return;
    }
    try {
      await cancelSession(sessionId).unwrap();
      stopPolling(); // Stop polling on cancel too
      onCancel?.();
    } catch {
      enqueueSnackbar('Failed to cancel', { variant: 'error' });
    }
  };

  // Poll /auth endpoint to detect authentication
  useEffect(() => {
    // Stop polling if auth detected or finishing
    if (authDetected || finishingRef.current) {
      stopPolling();
      return;
    }

    // Only poll when session is running
    if (!session?.routeToken || session.state !== 'running') {
      stopPolling();
      return;
    }

    const checkAuth = async () => {
      // Double-check we should still be polling
      if (authDetected || finishingRef.current) {
        stopPolling();
        return;
      }

      try {
        const baseUrl = (window as unknown as { Settings?: { traefikHttpBase?: string } }).Settings?.traefikHttpBase || '';
        const url = `${baseUrl}/t/${session.routeToken}/fs/auth`;
        const response = await fetch(url, { credentials: 'include' });
        if (response.ok) {
          const data: AuthStatusResponse = await response.json();
          if (data.authenticated) {
            setAuthDetected(true);
            stopPolling();
            enqueueSnackbar('Authentication detected! Click "Save" to finish.', { variant: 'success' });
          }
        }
      } catch {
        // Ignore errors - container might not be ready yet
      }
    };

    // Check immediately
    checkAuth();

    // Poll every 2 seconds
    pollingRef.current = setInterval(checkAuth, 2000);

    return () => stopPolling();
  }, [session?.routeToken, session?.state, authDetected, stopPolling]);

  // Auto-complete when collected (only once)
  useEffect(() => {
    if (session?.state === 'collected' && !authCompleteCalledRef.current) {
      authCompleteCalledRef.current = true;
      onAuthComplete?.();
    }
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
