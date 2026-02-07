import { Box, CircularProgress, Typography } from '@mui/material';
import { useState, useRef, useCallback, useMemo } from 'react';
import { Panel, Group, Separator } from 'react-resizable-panels';

import type { ITerminalSession } from 'entities/terminal-session';
import { FileTree, FileViewer } from 'features/file-tree';
import { useTerminalSessionChannel } from 'shared/lib/hooks';

export interface TerminalSessionWidgetProps {
  /** Terminal session ID to display */
  sessionId: number | null;
  /** Show file tree panel */
  showFileTree?: boolean;
  /** Show file content viewer panel */
  showFileViewer?: boolean;
  /** Show terminal panel */
  showTerminal?: boolean;
  /** Initial file tree width in percent (default: 20) */
  fileTreeWidth?: number;
  /** Initial file viewer width in percent (default: 40) */
  fileViewerWidth?: number;
  /** Callback when session updates */
  onSessionUpdate?: (session: ITerminalSession) => void;
  /** Callback when authentication is complete (detected by watcher) */
  onAuthComplete?: () => void;
  /** Callback when file is selected in tree */
  onFileSelect?: (path: string) => void;
}

const styles = {
  container: {
    width: '100%',
    height: '100%',
    display: 'flex',
    bgcolor: '#1e1e1e',
    overflow: 'hidden',
  },
  panel: {
    height: '100%',
    overflow: 'hidden',
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
  terminalContainer: {
    width: '100%',
    height: '100%',
    position: 'relative',
    bgcolor: '#000',
  },
  iframe: {
    width: '100%',
    height: '100%',
    border: 'none',
    backgroundColor: '#000',
  },
  loadingContainer: {
    width: '100%',
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
    bgcolor: '#1e1e1e',
  },
  loadingText: {
    color: '#d4d4d4',
    fontSize: '13px',
  },
  errorText: {
    color: '#f44747',
    fontSize: '13px',
  },
  emptyText: {
    color: '#808080',
    fontSize: '13px',
  },
} as const;

// Resize handle component
const ResizeHandle = () => (
  <Separator
    style={{
      width: '4px',
      backgroundColor: '#3d3d3d',
      cursor: 'col-resize',
      transition: 'background-color 0.15s ease',
    }}
    className="terminal-widget-resize-handle"
  />
);

export const TerminalSessionWidget: React.FC<TerminalSessionWidgetProps> = ({
  sessionId,
  showFileTree = true,
  showFileViewer = true,
  showTerminal = true,
  fileTreeWidth = 20,
  fileViewerWidth = 40,
  onSessionUpdate,
  onAuthComplete,
  onFileSelect,
}) => {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [iframeLoaded, setIframeLoaded] = useState(false);
  const [selectedFile, setSelectedFile] = useState<string | null>(null);

  // Subscribe to session updates via ActionCable
  const { session, connecting, error } = useTerminalSessionChannel({
    sessionId,
    onUpdate: onSessionUpdate,
    onAuthComplete,
  });

  // Derive URLs from session
  const ttydUrl = useMemo(() => {
    if (!session?.websocketUrl) return null;
    // websocket_url: ws://localhost/t/{token}/tty/ws -> http://localhost/t/{token}/tty
    return session.websocketUrl
      .replace('wss://', 'https://')
      .replace('ws://', 'http://')
      .replace('/ws', '');
  }, [session?.websocketUrl]);

  const watcherUrl = useMemo(() => {
    if (!session?.websocketUrl) return null;
    // websocket_url: ws://localhost/t/{token}/tty/ws -> http://localhost/t/{token}/fs
    return session.websocketUrl
      .replace('wss://', 'https://')
      .replace('ws://', 'http://')
      .replace('/tty/ws', '/fs')
      .replace('/tty', '/fs');
  }, [session?.watcherUrl, session?.websocketUrl]);

  const handleIframeLoad = useCallback(() => {
    setIframeLoaded(true);
    iframeRef.current?.focus();
  }, []);

  const handleFileSelect = useCallback(
    (path: string) => {
      setSelectedFile(path);
      onFileSelect?.(path);
    },
    [onFileSelect],
  );

  const handleCloseFileViewer = useCallback(() => {
    setSelectedFile(null);
  }, []);

  // Reset iframe loaded state when session changes
  const prevSessionIdRef = useRef(sessionId);
  if (sessionId !== prevSessionIdRef.current) {
    prevSessionIdRef.current = sessionId;
    setIframeLoaded(false);
    setSelectedFile(null);
  }

  // Determine what panels to show based on session state
  const isSessionRunning = session?.state === 'running';
  const canShowTerminal = showTerminal && isSessionRunning && ttydUrl;
  const canShowFileTree = showFileTree && isSessionRunning && watcherUrl;
  const canShowFileViewer = showFileViewer && selectedFile && watcherUrl;

  // Calculate panel count for sizing
  const visiblePanels = [canShowFileTree, canShowFileViewer, canShowTerminal].filter(Boolean).length;

  // Render loading/error states
  if (!sessionId) {
    return (
      <Box sx={styles.loadingContainer}>
        <Typography sx={styles.emptyText}>No session selected</Typography>
      </Box>
    );
  }

  if (connecting) {
    return (
      <Box sx={styles.loadingContainer}>
        <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        <Typography sx={styles.loadingText}>Connecting to session...</Typography>
      </Box>
    );
  }

  if (error) {
    return (
      <Box sx={styles.loadingContainer}>
        <Typography sx={styles.errorText}>{error}</Typography>
      </Box>
    );
  }

  if (!session) {
    return (
      <Box sx={styles.loadingContainer}>
        <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        <Typography sx={styles.loadingText}>Loading session...</Typography>
      </Box>
    );
  }

  if (!isSessionRunning) {
    return (
      <Box sx={styles.loadingContainer}>
        <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        <Typography sx={styles.loadingText}>Waiting for container ({session.state})...</Typography>
        {session.errorMessage && <Typography sx={styles.errorText}>{session.errorMessage}</Typography>}
      </Box>
    );
  }

  // No panels to show
  if (visiblePanels === 0) {
    return (
      <Box sx={styles.loadingContainer}>
        <Typography sx={styles.emptyText}>No panels enabled</Typography>
      </Box>
    );
  }

  // Render terminal only
  const renderTerminal = () => (
    <Box sx={styles.terminalContainer}>
      {!iframeLoaded && (
        <Box
          sx={{
            ...styles.loadingContainer,
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 1,
          }}
        >
          <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
          <Typography sx={styles.loadingText}>Connecting to terminal...</Typography>
        </Box>
      )}
      <iframe ref={iframeRef} src={ttydUrl!} style={styles.iframe} title="Terminal" onLoad={handleIframeLoad} />
    </Box>
  );

  // Single panel - no resizing needed
  if (visiblePanels === 1) {
    if (canShowFileTree) {
      return (
        <Box sx={styles.container}>
          <FileTree watcherUrl={watcherUrl} onFileSelect={handleFileSelect} selectedPath={selectedFile} />
        </Box>
      );
    }
    if (canShowTerminal) {
      return <Box sx={styles.container}>{renderTerminal()}</Box>;
    }
    return null;
  }

  // Multiple panels with resizing
  return (
    <Box sx={styles.container}>
      <style>{`
        .terminal-widget-resize-handle:hover {
          background-color: #007acc !important;
        }
        .terminal-widget-resize-handle[data-resize-handle-active] {
          background-color: #007acc !important;
        }
      `}</style>

      <Group orientation="horizontal" style={{ width: '100%', height: '100%' }}>
        {/* File Tree Panel */}
        {canShowFileTree && (
          <>
            <Panel defaultSize={fileTreeWidth} minSize={10} style={styles.panel}>
              <FileTree watcherUrl={watcherUrl} onFileSelect={handleFileSelect} selectedPath={selectedFile} />
            </Panel>
            <ResizeHandle />
          </>
        )}

        {/* File Viewer Panel */}
        {canShowFileViewer && (
          <>
            <Panel defaultSize={fileViewerWidth} minSize={15} style={styles.panel}>
              <FileViewer watcherUrl={watcherUrl} filePath={selectedFile} onClose={handleCloseFileViewer} />
            </Panel>
            <ResizeHandle />
          </>
        )}

        {/* Terminal Panel */}
        {canShowTerminal && (
          <Panel
            defaultSize={100 - fileTreeWidth - (canShowFileViewer ? fileViewerWidth : 0)}
            minSize={20}
            style={styles.panel}
          >
            {renderTerminal()}
          </Panel>
        )}
      </Group>
    </Box>
  );
};
