import { Box, Button, CircularProgress, TextField, Typography } from '@mui/material';
import { enqueueSnackbar } from 'notistack';
import { useCallback, useEffect, useState, useRef } from 'react';

import type { AgentType, ITerminalSession } from 'entities/terminal-session';
import { useCreateTerminalSessionMutation, useFinishSessionMutation } from 'shared/api';
import { TerminalSessionWidget } from 'widgets/terminal-session';

// Agent-specific env fields that must be configured before starting container
const AGENT_ENV_FIELDS: Record<string, { key: string; label: string; required: boolean; placeholder?: string }[]> = {
  gemini_cli: [
    { key: 'google_cloud_project', label: 'Google Cloud Project ID', required: true, placeholder: 'my-project-123' },
  ],
};

interface AuthStatusResponse {
  authenticated: boolean;
}

interface AgentAuthTerminalProps {
  agentType: AgentType;
  onAuthComplete?: () => void;
  onCancel?: () => void;
}

type AuthStep = 'env_fields' | 'terminal' | 'completed';

export const AgentAuthTerminal: React.FC<AgentAuthTerminalProps> = ({ agentType, onAuthComplete, onCancel }) => {
  const envFields = AGENT_ENV_FIELDS[agentType] || [];
  const requiresEnvFields = envFields.some((f) => f.required);

  const [step, setStep] = useState<AuthStep>(requiresEnvFields ? 'env_fields' : 'terminal');
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [session, setSession] = useState<ITerminalSession | null>(null);
  const [authDetected, setAuthDetected] = useState(false);
  const [metadata, setMetadata] = useState<Record<string, string>>({});
  const finishingRef = useRef(false);
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const authCompleteCalledRef = useRef(false);

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [finishSession, { isLoading: isFinishing }] = useFinishSessionMutation();
  const isCancelling = isFinishing;

  const handleSessionUpdate = useCallback((s: ITerminalSession) => setSession(s), []);

  // Reset state when agentType changes
  useEffect(() => {
    setStep(requiresEnvFields ? 'env_fields' : 'terminal');
    setSessionId(null);
    setSession(null);
    setAuthDetected(false);
    setMetadata({});
    finishingRef.current = false;
    // Note: don't reset authCompleteCalledRef here as it could cause double calls
    // when parent changes activeLoginAgent during onAuthComplete callback
    if (pollingRef.current) {
      clearInterval(pollingRef.current);
      pollingRef.current = null;
    }
  }, [agentType, requiresEnvFields]);

  const stopPolling = useCallback(() => {
    if (pollingRef.current) {
      clearInterval(pollingRef.current);
      pollingRef.current = null;
    }
  }, []);

  // Handle env fields submission and proceed to terminal
  const handleEnvFieldsSubmit = () => {
    // Validate required fields
    const missingRequired = envFields.filter((f) => f.required && !metadata[f.key]).map((f) => f.label);
    if (missingRequired.length > 0) {
      enqueueSnackbar(`Please fill in: ${missingRequired.join(', ')}`, { variant: 'warning' });
      return;
    }
    setStep('terminal');
  };

  // Handle starting terminal session
  const handleStartTerminal = async () => {
    try {
      const result = await createSession({
        terminalSession: {
          sessionType: 'auth_setup',
          agentType,
          // Pass env fields as metadata - will be used for container env vars
          metadata: Object.keys(metadata).length > 0 ? metadata : undefined,
        },
      }).unwrap();
      setSessionId(result.data.id);
    } catch {
      enqueueSnackbar('Failed to start session', { variant: 'error' });
    }
  };

  // Handle finishing authentication
  const handleFinish = useCallback(async () => {
    if (!sessionId || finishingRef.current) return;
    finishingRef.current = true;
    stopPolling();
    try {
      await finishSession({ sessionId }).unwrap();
      enqueueSnackbar('Authentication saved!', { variant: 'success' });
      setStep('completed');
      if (!authCompleteCalledRef.current) {
        authCompleteCalledRef.current = true;
        onAuthComplete?.();
      }
    } catch {
      enqueueSnackbar('Failed to finish', { variant: 'error' });
      finishingRef.current = false;
    }
  }, [sessionId, finishSession, onAuthComplete, stopPolling]);

  const handleCancel = async () => {
    if (!sessionId) {
      onCancel?.();
      return;
    }
    try {
      await finishSession({ sessionId }).unwrap();
      stopPolling();
      onCancel?.();
    } catch {
      enqueueSnackbar('Failed to cancel', { variant: 'error' });
    }
  };

  // Poll /auth endpoint to detect authentication
  useEffect(() => {
    if (authDetected || finishingRef.current) {
      stopPolling();
      return;
    }
    if (!session?.routeToken || session.state !== 'ready') {
      stopPolling();
      return;
    }

    const checkAuth = async () => {
      if (authDetected || finishingRef.current) {
        stopPolling();
        return;
      }
      try {
        const baseUrl =
          (window as unknown as { Settings?: { traefikHttpBase?: string } }).Settings?.traefikHttpBase || '';
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
        // Ignore - container might not be ready
      }
    };

    checkAuth();
    pollingRef.current = setInterval(checkAuth, 2000);
    return () => stopPolling();
  }, [session?.routeToken, session?.state, authDetected, stopPolling]);

  // Auto-complete when session collected/stopped
  useEffect(() => {
    if (session?.state === 'finished' && !authCompleteCalledRef.current) {
      setStep('completed');
      authCompleteCalledRef.current = true;
      onAuthComplete?.();
    }
  }, [session?.state, onAuthComplete]);

  const isReady = session?.state === 'ready';
  const canCancel = session?.state && !['finished', 'failed'].includes(session.state);

  // Step 1: Env fields form (for agents that require pre-config like GOOGLE_CLOUD_PROJECT)
  if (step === 'env_fields') {
    return (
      <Box
        sx={{
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          bgcolor: '#1e1e1e',
          gap: 2,
          p: 3,
        }}
      >
        <Typography variant="h6" sx={{ color: '#fff' }}>
          Configure {agentType.replace(/_/g, ' ')}
        </Typography>
        <Typography variant="body2" sx={{ color: '#888', mb: 2 }}>
          These settings are required before starting authentication.
        </Typography>

        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, width: '100%', maxWidth: 400 }}>
          {envFields.map((field) => (
            <TextField
              key={field.key}
              label={field.label}
              placeholder={field.placeholder}
              required={field.required}
              value={metadata[field.key] || ''}
              onChange={(e) => setMetadata((prev) => ({ ...prev, [field.key]: e.target.value }))}
              fullWidth
              InputLabelProps={{ shrink: true }}
              sx={{
                '& .MuiInputBase-root': { bgcolor: '#252525', color: '#fff' },
                '& .MuiInputBase-input': { color: '#fff' },
                '& .MuiInputLabel-root': { color: '#aaa' },
                '& .MuiOutlinedInput-notchedOutline': { borderColor: '#3d3d3d' },
                '& .MuiOutlinedInput-root:hover .MuiOutlinedInput-notchedOutline': { borderColor: '#555' },
              }}
            />
          ))}
        </Box>

        <Box sx={{ display: 'flex', gap: 2, mt: 2 }}>
          <Button variant="contained" onClick={handleEnvFieldsSubmit}>
            Continue
          </Button>
          <Button variant="outlined" onClick={onCancel}>
            Cancel
          </Button>
        </Box>
      </Box>
    );
  }

  // Step 3: Completed
  if (step === 'completed') {
    return (
      <Box
        sx={{
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          bgcolor: '#1e1e1e',
          gap: 2,
        }}
      >
        <Typography sx={{ fontSize: '48px' }}>✅</Typography>
        <Typography variant="h6" sx={{ color: '#4caf50' }}>
          Authentication Complete
        </Typography>
        <Typography variant="body2" sx={{ color: '#888' }}>
          Credentials have been saved securely.
        </Typography>
      </Box>
    );
  }

  // Step 2: Terminal (not started yet)
  if (!sessionId) {
    return (
      <Box sx={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: '#1e1e1e' }}>
        <Button
          variant="contained"
          onClick={handleStartTerminal}
          disabled={isCreating}
          startIcon={isCreating ? <CircularProgress size={16} /> : undefined}
        >
          Start Authentication
        </Button>
      </Box>
    );
  }

  // Step 2: Terminal (session running)
  return (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: '#1e1e1e' }}>
      {/* Header */}
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
          <Typography variant="caption" sx={{ color: session.state === 'ready' ? '#4caf50' : '#888' }}>
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
          showEditor={false}
          showTerminal
          onSessionUpdate={handleSessionUpdate}
        />
      </Box>

      {/* Action buttons */}
      <Box sx={{ display: 'flex', gap: 1, p: 1, borderTop: '1px solid #3d3d3d', alignItems: 'center' }}>
        {isReady && (
          <>
            <Button
              variant="contained"
              color="success"
              size="small"
              onClick={handleFinish}
              disabled={isFinishing || !authDetected}
            >
              {isFinishing ? 'Saving...' : 'Save Authentication'}
            </Button>
            {!authDetected && (
              <Typography variant="caption" sx={{ color: '#888', ml: 1 }}>
                Complete authentication in terminal first
              </Typography>
            )}
          </>
        )}
        {canCancel && (
          <Button variant="outlined" color="error" size="small" onClick={handleCancel} disabled={isCancelling}>
            Cancel
          </Button>
        )}
      </Box>
    </Box>
  );
};
