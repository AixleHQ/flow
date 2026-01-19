import { Box, IconButton, Typography, Chip, Tooltip, CircularProgress } from '@mui/material';
import { useParams, useNavigate, useRouterState } from '@tanstack/react-router';
import { useState, useEffect, useRef } from 'react';

// Simple arrow and stop icons using unicode
const ArrowBackIcon = () => <span style={{ fontSize: '20px' }}>←</span>;
const StopIcon = () => <span style={{ fontSize: '20px' }}>■</span>;

interface SessionRouterState {
  ttydPort?: number;
}

const styles = {
  container: {
    height: '100vh',
    width: '100vw',
    display: 'flex',
    flexDirection: 'column',
    bgcolor: '#1e1e1e',
    overflow: 'hidden',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingX: '16px',
    paddingY: '8px',
    bgcolor: '#2d2d2d',
    borderBottom: '1px solid #3d3d3d',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  sessionInfo: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  sessionId: {
    color: '#808080',
    fontFamily: 'monospace',
    fontSize: '12px',
  },
  terminalContainer: {
    flex: 1,
    overflow: 'hidden',
    bgcolor: '#000',
  },
  loadingContainer: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '16px',
  },
  loadingText: {
    color: '#d4d4d4',
  },
  errorText: {
    color: '#f44747',
  },
  iframe: {
    width: '100%',
    height: '100%',
    border: 'none',
    backgroundColor: '#000',
  },
} as const;

export function SessionPage() {
  const { sessionId } = useParams({ from: '/session/$sessionId' });
  const routerState = useRouterState({ select: (s) => s.location.state as SessionRouterState });
  const navigate = useNavigate();
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [stopping, setStopping] = useState(false);
  const [iframeLoaded, setIframeLoaded] = useState(false);

  // Get ttyd port from router state or fetch from API
  const [ttydPort, setTtydPort] = useState<number | null>(routerState?.ttydPort ?? null);
  const [fetchingPort, setFetchingPort] = useState(!routerState?.ttydPort);
  const [portError, setPortError] = useState<string | null>(null);

  // Fetch ttyd port if not provided in router state
  useEffect(() => {
    if (ttydPort) {
      setFetchingPort(false);
      return;
    }

    const fetchSessionInfo = async () => {
      try {
        const response = await fetch(`/api/v1/terminal_sessions/${sessionId}?step_name=interactive`);
        const data = await response.json();

        if (!response.ok) {
          throw new Error(data.error || 'Session not found');
        }

        if (data.ttyd_port) {
          setTtydPort(data.ttyd_port);
        } else {
          setPortError('Terminal port not available');
        }
      } catch (err) {
        setPortError(err instanceof Error ? err.message : 'Failed to fetch session info');
      } finally {
        setFetchingPort(false);
      }
    };

    fetchSessionInfo();
  }, [sessionId, ttydPort]);

  // Construct ttyd URL
  const ttydUrl = ttydPort ? `http://localhost:${ttydPort}` : null;

  const handleBack = () => {
    navigate({ to: '/' });
  };

  const handleStop = async () => {
    setStopping(true);
    try {
      await fetch(`/api/v1/terminal_sessions/${sessionId}?step_name=interactive`, {
        method: 'DELETE',
      });
      navigate({ to: '/' });
    } catch (err) {
      console.error('Failed to stop session:', err);
      setStopping(false);
    }
  };

  const handleIframeLoad = () => {
    setIframeLoaded(true);
    // Focus the iframe to allow keyboard input
    if (iframeRef.current) {
      iframeRef.current.focus();
    }
  };

  const getStatusColor = () => {
    if (fetchingPort) return 'default';
    if (portError) return 'error';
    if (!iframeLoaded) return 'warning';
    return 'success';
  };

  const getStatusLabel = () => {
    if (fetchingPort) return 'Loading...';
    if (portError) return 'Error';
    if (!iframeLoaded) return 'Connecting...';
    return 'Connected';
  };

  return (
    <Box sx={styles.container}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Tooltip title="Back to home">
            <IconButton onClick={handleBack} sx={{ color: '#d4d4d4' }}>
              <ArrowBackIcon />
            </IconButton>
          </Tooltip>

          <Box sx={styles.sessionInfo}>
            <Typography variant="subtitle2" sx={{ color: '#d4d4d4' }}>
              Session
            </Typography>
            <Typography sx={styles.sessionId}>{sessionId.slice(0, 8)}...</Typography>
            {ttydPort && <Typography sx={styles.sessionId}>(port: {ttydPort})</Typography>}
          </Box>
        </Box>

        <Box sx={styles.headerRight}>
          <Chip size="small" label={getStatusLabel()} color={getStatusColor()} sx={{ height: 24 }} />

          <Tooltip title="Stop session">
            <IconButton onClick={handleStop} disabled={stopping} sx={{ color: '#f44747' }}>
              {stopping ? <CircularProgress size={20} color="inherit" /> : <StopIcon />}
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      {/* Terminal iframe or Loading */}
      {portError ? (
        <Box sx={styles.loadingContainer}>
          <Typography sx={styles.errorText}>{portError}</Typography>
        </Box>
      ) : fetchingPort ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress sx={{ color: '#4ec9b0' }} />
          <Typography sx={styles.loadingText}>Loading session...</Typography>
        </Box>
      ) : (
        <Box sx={styles.terminalContainer}>
          {!iframeLoaded && (
            <Box sx={{ ...styles.loadingContainer, position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}>
              <CircularProgress sx={{ color: '#4ec9b0' }} />
              <Typography sx={styles.loadingText}>Connecting to terminal...</Typography>
            </Box>
          )}
          <iframe
            ref={iframeRef}
            src={ttydUrl || undefined}
            style={styles.iframe}
            title="Terminal"
            onLoad={handleIframeLoad}
          />
        </Box>
      )}
    </Box>
  );
}
