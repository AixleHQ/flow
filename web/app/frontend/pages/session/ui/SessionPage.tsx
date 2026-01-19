import { Box, IconButton, Typography, Chip, Tooltip, CircularProgress } from '@mui/material';
import { useParams, useNavigate, useRouterState } from '@tanstack/react-router';
import { useState, useEffect, useRef } from 'react';
import { Panel, Group, Separator } from 'react-resizable-panels';

import { FileTree, FileViewer } from 'features/file-tree';

// Simple arrow and stop icons using unicode
const ArrowBackIcon = () => <span style={{ fontSize: '20px' }}>←</span>;
const StopIcon = () => <span style={{ fontSize: '20px' }}>■</span>;
const SidebarIcon = () => <span style={{ fontSize: '18px' }}>☰</span>;

interface ISessionRouterState {
  ttydPort?: number;
  watcherPort?: number;
}

const SIDEBAR_WIDTH = 260;

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
  mainContent: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
  },
  sidebar: {
    width: `${SIDEBAR_WIDTH}px`,
    borderRight: '1px solid #3d3d3d',
    flexShrink: 0,
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
  },
  sidebarHidden: {
    display: 'none',
  },
  panelGroup: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
  },
  panel: {
    height: '100%',
    overflow: 'hidden',
  },
  fileViewerPanel: {
    height: '100%',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
  },
  terminalPanel: {
    height: '100%',
    overflow: 'hidden',
    backgroundColor: '#000',
    position: 'relative',
  },
  resizeHandle: {
    width: '4px',
    backgroundColor: '#3d3d3d',
    cursor: 'col-resize',
    transition: 'background-color 0.15s ease',
    '&:hover': {
      backgroundColor: '#007acc',
    },
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

// Custom resize handle component
const ResizeHandle = () => (
  <Separator
    style={{
      width: '4px',
      backgroundColor: '#3d3d3d',
      cursor: 'col-resize',
      transition: 'background-color 0.15s ease',
    }}
    className="resize-handle"
  />
);

export function SessionPage() {
  const { sessionId } = useParams({ from: '/session/$sessionId' });
  const routerState = useRouterState({ select: (s) => s.location.state as ISessionRouterState });
  const navigate = useNavigate();
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [stopping, setStopping] = useState(false);
  const [iframeLoaded, setIframeLoaded] = useState(false);
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [selectedFile, setSelectedFile] = useState<string | null>(null);

  // Get ports from router state or fetch from API
  const [ttydPort, setTtydPort] = useState<number | null>(routerState?.ttydPort ?? null);
  const [watcherPort, setWatcherPort] = useState<number | null>(routerState?.watcherPort ?? null);
  const [fetchingPort, setFetchingPort] = useState(!routerState?.ttydPort);
  const [portError, setPortError] = useState<string | null>(null);

  // Fetch session info if not provided in router state
  useEffect(() => {
    if (ttydPort && watcherPort) {
      setFetchingPort(false);
      return;
    }

    const fetchSessionInfo = async () => {
      try {
        const response = await fetch(`/api/v1/terminal_sessions/${sessionId}?step_name=dev`);
        const data = await response.json();

        if (!response.ok) {
          throw new Error(data.error || 'Session not found');
        }

        if (data.ttyd?.port) {
          setTtydPort(data.ttyd.port);
        } else {
          setPortError('Terminal port not available');
        }

        if (data.watcher?.port) {
          setWatcherPort(data.watcher.port);
        }
      } catch (err) {
        setPortError(err instanceof Error ? err.message : 'Failed to fetch session info');
      } finally {
        setFetchingPort(false);
      }
    };

    fetchSessionInfo();
  }, [sessionId, ttydPort, watcherPort]);

  // Construct ttyd URL
  const ttydUrl = ttydPort ? `http://localhost:${ttydPort}` : null;

  const handleBack = () => {
    navigate({ to: '/' });
  };

  const handleStop = async () => {
    setStopping(true);
    try {
      await fetch(`/api/v1/terminal_sessions/${sessionId}?step_name=dev`, {
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

  const handleToggleSidebar = () => {
    setSidebarVisible((prev) => !prev);
  };

  const handleFileSelect = (path: string) => {
    setSelectedFile(path);
  };

  const handleCloseFileViewer = () => {
    setSelectedFile(null);
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

  // Render terminal content
  const renderTerminal = () => {
    if (portError) {
      return (
        <Box sx={styles.loadingContainer}>
          <Typography sx={styles.errorText}>{portError}</Typography>
        </Box>
      );
    }

    if (fetchingPort) {
      return (
        <Box sx={styles.loadingContainer}>
          <CircularProgress sx={{ color: '#4ec9b0' }} />
          <Typography sx={styles.loadingText}>Loading session...</Typography>
        </Box>
      );
    }

    return (
      <div style={{ ...styles.terminalPanel, position: 'relative' }}>
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
      </div>
    );
  };

  return (
    <Box sx={styles.container}>
      {/* Global styles for resize handle */}
      <style>{`
        .resize-handle:hover {
          background-color: #007acc !important;
        }
        .resize-handle[data-resize-handle-active] {
          background-color: #007acc !important;
        }
      `}</style>

      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Tooltip title="Back to home">
            <IconButton onClick={handleBack} sx={{ color: '#d4d4d4' }}>
              <ArrowBackIcon />
            </IconButton>
          </Tooltip>

          <Tooltip title={sidebarVisible ? 'Hide sidebar' : 'Show sidebar'}>
            <IconButton onClick={handleToggleSidebar} sx={{ color: '#d4d4d4' }}>
              <SidebarIcon />
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

      {/* Main content area */}
      <Box sx={styles.mainContent}>
        {/* Sidebar with FileTree */}
        <Box sx={{ ...styles.sidebar, ...(sidebarVisible ? {} : styles.sidebarHidden) }}>
          <FileTree watcherPort={watcherPort} onFileSelect={handleFileSelect} selectedPath={selectedFile} />
        </Box>

        {/* Resizable panels for FileViewer and Terminal */}
        {selectedFile ? (
          <Group orientation="horizontal" style={{ flex: 1, display: 'flex' }}>
            {/* File Viewer Panel */}
            <Panel defaultSize={50} minSize={20} style={styles.fileViewerPanel}>
              <FileViewer watcherPort={watcherPort} filePath={selectedFile} onClose={handleCloseFileViewer} />
            </Panel>

            <ResizeHandle />

            {/* Terminal Panel */}
            <Panel defaultSize={50} minSize={20} style={styles.terminalPanel}>
              {renderTerminal()}
            </Panel>
          </Group>
        ) : (
          /* Terminal only when no file selected */
          <div style={{ flex: 1, ...styles.terminalPanel }}>{renderTerminal()}</div>
        )}
      </Box>
    </Box>
  );
}
