import { Box, CircularProgress, IconButton, Tab, Tabs, Tooltip, Typography } from '@mui/material';
import { useSnackbar } from 'notistack';
import { useCallback, useRef, useState } from 'react';

import { useCreateSessionMutation, useGetAgentsQuery, useStopSessionMutation } from '../api/workspaceApi';
import type { AgentType, IAgentSession } from '../lib/types';

const agentColors: Record<AgentType, string> = {
  codex: '#10a37f',
  cursor_cli: '#7c3aed',
  open_code: '#3b82f6',
  claude_code: '#d97706',
};

const PlayIcon = () => <span style={{ fontSize: '16px' }}>▶</span>;
const StopIcon = () => <span style={{ fontSize: '14px' }}>■</span>;
const RefreshIcon = () => <span style={{ fontSize: '16px' }}>↻</span>;

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
    flexShrink: 0,
  },
  headerTitle: {
    color: '#ffffff',
    fontWeight: 600,
    fontFamily: '"JetBrains Mono", monospace',
  },
  tabsContainer: {
    bgcolor: '#252526',
    borderBottom: '1px solid #3d3d3d',
  },
  tab: {
    textTransform: 'none',
    minHeight: '48px',
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: '13px',
    color: 'rgba(255, 255, 255, 0.7)',
    '&.Mui-selected': {
      color: '#ffffff',
    },
  },
  tabContent: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  tabIndicator: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
  },
  mainContent: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
    position: 'relative',
  },
  terminalContainer: {
    flex: 1,
    position: 'relative',
    bgcolor: '#000',
  },
  iframe: {
    width: '100%',
    height: '100%',
    border: 'none',
    backgroundColor: '#000',
  },
  placeholder: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '16px',
    bgcolor: '#1e1e1e',
  },
  placeholderText: {
    color: 'rgba(255, 255, 255, 0.5)',
    fontFamily: '"JetBrains Mono", monospace',
  },
  startButton: {
    padding: '12px 32px',
    borderRadius: '8px',
    border: '1px solid rgba(255, 255, 255, 0.2)',
    bgcolor: 'transparent',
    color: '#ffffff',
    cursor: 'pointer',
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: '14px',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    transition: 'all 0.2s ease',
    '&:hover': {
      bgcolor: 'rgba(255, 255, 255, 0.1)',
      borderColor: 'rgba(255, 255, 255, 0.4)',
    },
  },
  controlsBar: {
    position: 'absolute',
    top: '8px',
    right: '8px',
    display: 'flex',
    gap: '4px',
    zIndex: 10,
  },
  controlButton: {
    bgcolor: 'rgba(0, 0, 0, 0.6)',
    color: '#ffffff',
    '&:hover': {
      bgcolor: 'rgba(0, 0, 0, 0.8)',
    },
  },
  loadingOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '16px',
    bgcolor: 'rgba(0, 0, 0, 0.8)',
    zIndex: 5,
  },
} as const;

const WorkspacePage = () => {
  const { enqueueSnackbar } = useSnackbar();
  const { data: agentsData, isLoading: isLoadingAgents } = useGetAgentsQuery();
  const [createSession] = useCreateSessionMutation();
  const [stopSession] = useStopSessionMutation();

  const [activeTab, setActiveTab] = useState<AgentType>('claude_code');
  const [sessions, setSessions] = useState<Record<AgentType, IAgentSession | null>>({
    codex: null,
    cursor_cli: null,
    open_code: null,
    claude_code: null,
  });
  const [iframeLoaded, setIframeLoaded] = useState<Record<AgentType, boolean>>({
    codex: false,
    cursor_cli: false,
    open_code: false,
    claude_code: false,
  });

  const iframeRefs = useRef<Record<AgentType, HTMLIFrameElement | null>>({
    codex: null,
    cursor_cli: null,
    open_code: null,
    claude_code: null,
  });

  const agents = agentsData?.agents || [];

  const handleTabChange = (_: React.SyntheticEvent, newValue: AgentType) => {
    setActiveTab(newValue);
  };

  const handleStartSession = useCallback(
    async (agentType: AgentType) => {
      setSessions((prev) => ({
        ...prev,
        [agentType]: { id: '', agentType, status: 'starting' },
      }));

      try {
        const response = await createSession({ agentType }).unwrap();
        setSessions((prev) => ({
          ...prev,
          [agentType]: {
            id: response.id,
            agentType,
            status: 'running',
            ttydPort: response.ttyd?.port,
            watcherPort: response.watcher?.port,
          },
        }));
        enqueueSnackbar(`${agentType} session started`, { variant: 'success' });
      } catch (error) {
        setSessions((prev) => ({
          ...prev,
          [agentType]: {
            id: '',
            agentType,
            status: 'error',
            error: error instanceof Error ? error.message : 'Failed to start session',
          },
        }));
        enqueueSnackbar('Failed to start session', { variant: 'error' });
      }
    },
    [createSession, enqueueSnackbar],
  );

  const handleStopSession = useCallback(
    async (agentType: AgentType) => {
      const session = sessions[agentType];
      if (!session?.id) return;

      setSessions((prev) => ({
        ...prev,
        [agentType]: { ...prev[agentType]!, status: 'stopping' },
      }));

      try {
        await stopSession({ sessionId: session.id, agentType }).unwrap();
        setSessions((prev) => ({
          ...prev,
          [agentType]: null,
        }));
        setIframeLoaded((prev) => ({
          ...prev,
          [agentType]: false,
        }));
        enqueueSnackbar(`${agentType} session stopped`, { variant: 'info' });
      } catch {
        enqueueSnackbar('Failed to stop session', { variant: 'error' });
      }
    },
    [sessions, stopSession, enqueueSnackbar],
  );

  const handleIframeLoad = (agentType: AgentType) => {
    setIframeLoaded((prev) => ({
      ...prev,
      [agentType]: true,
    }));
    // Focus the iframe
    const iframe = iframeRefs.current[agentType];
    if (iframe) {
      iframe.focus();
    }
  };

  const getStatusColor = (agentType: AgentType) => {
    const session = sessions[agentType];
    if (!session) return 'rgba(255, 255, 255, 0.3)';
    if (session.status === 'running' && iframeLoaded[agentType]) return '#4ec9b0';
    if (session.status === 'starting' || session.status === 'stopping') return '#dcdcaa';
    if (session.status === 'error') return '#f44747';
    return 'rgba(255, 255, 255, 0.3)';
  };

  const renderTabContent = (agentType: AgentType) => {
    const session = sessions[agentType];
    const agent = agents.find((a) => a.type === agentType);

    if (!session || session.status === 'idle') {
      return (
        <Box sx={styles.placeholder}>
          <Typography sx={styles.placeholderText}>{agent?.displayName || agentType}</Typography>
          <Box
            component="button"
            sx={{ ...styles.startButton, borderColor: agentColors[agentType] }}
            onClick={() => handleStartSession(agentType)}
          >
            <PlayIcon />
            Start Session
          </Box>
        </Box>
      );
    }

    if (session.status === 'starting') {
      return (
        <Box sx={styles.placeholder}>
          <CircularProgress sx={{ color: agentColors[agentType] }} />
          <Typography sx={styles.placeholderText}>Starting {agent?.displayName || agentType}...</Typography>
        </Box>
      );
    }

    if (session.status === 'error') {
      return (
        <Box sx={styles.placeholder}>
          <Typography sx={{ color: '#f44747' }}>{session.error || 'An error occurred'}</Typography>
          <Box
            component="button"
            sx={{ ...styles.startButton, borderColor: agentColors[agentType] }}
            onClick={() => handleStartSession(agentType)}
          >
            <RefreshIcon />
            Retry
          </Box>
        </Box>
      );
    }

    const ttydUrl = session.ttydPort ? `http://localhost:${session.ttydPort}` : null;

    return (
      <Box sx={styles.terminalContainer}>
        {/* Loading overlay */}
        {session.status === 'stopping' && (
          <Box sx={styles.loadingOverlay}>
            <CircularProgress sx={{ color: agentColors[agentType] }} />
            <Typography sx={{ color: '#ffffff' }}>Stopping session...</Typography>
          </Box>
        )}

        {/* Controls */}
        <Box sx={styles.controlsBar}>
          <Tooltip title="Stop session">
            <IconButton
              size="small"
              sx={styles.controlButton}
              onClick={() => handleStopSession(agentType)}
              disabled={session.status === 'stopping'}
            >
              <StopIcon />
            </IconButton>
          </Tooltip>
        </Box>

        {/* Terminal iframe */}
        {!iframeLoaded[agentType] && (
          <Box sx={styles.loadingOverlay}>
            <CircularProgress sx={{ color: agentColors[agentType] }} />
            <Typography sx={{ color: '#ffffff' }}>Connecting to terminal...</Typography>
          </Box>
        )}
        {ttydUrl && (
          <iframe
            ref={(el) => {
              iframeRefs.current[agentType] = el;
            }}
            src={ttydUrl}
            style={styles.iframe}
            title={`${agentType} Terminal`}
            onLoad={() => handleIframeLoad(agentType)}
          />
        )}
      </Box>
    );
  };

  if (isLoadingAgents) {
    return (
      <Box sx={{ ...styles.container, alignItems: 'center', justifyContent: 'center' }}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={styles.container}>
      {/* Header */}
      <Box sx={styles.header}>
        <Typography sx={styles.headerTitle}>Palad Workspace</Typography>
      </Box>

      {/* Agent Tabs */}
      <Box sx={styles.tabsContainer}>
        <Tabs
          value={activeTab}
          onChange={handleTabChange}
          variant="fullWidth"
          TabIndicatorProps={{
            style: {
              backgroundColor: agentColors[activeTab],
            },
          }}
        >
          {agents.map((agent) => (
            <Tab
              key={agent.type}
              value={agent.type}
              sx={styles.tab}
              label={
                <Box sx={styles.tabContent}>
                  <Box sx={{ ...styles.tabIndicator, bgcolor: getStatusColor(agent.type as AgentType) }} />
                  {agent.displayName}
                </Box>
              }
            />
          ))}
        </Tabs>
      </Box>

      {/* Main Content - Terminal panels */}
      <Box sx={styles.mainContent}>
        {agents.map((agent) => (
          <Box
            key={agent.type}
            sx={{
              display: activeTab === agent.type ? 'flex' : 'none',
              flex: 1,
              overflow: 'hidden',
            }}
          >
            {renderTabContent(agent.type as AgentType)}
          </Box>
        ))}
      </Box>
    </Box>
  );
};

export default WorkspacePage;
