import ChevronLeftIcon from '@mui/icons-material/ChevronLeft';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';
import { Box, CircularProgress, IconButton, Typography } from '@mui/material';
import { useState, useRef, useCallback, useMemo } from 'react';
import { Panel, Group, Separator } from 'react-resizable-panels';

import { type ITerminalSession, SessionSummaryCard } from 'entities/terminal-session';
import { useTerminalSessionChannel } from 'shared/lib/hooks';

export interface TerminalSessionWidgetProps {
  sessionId: number | null;
  session?: ITerminalSession | null;
  showEditor?: boolean;
  showTerminal?: boolean;
  editorWidth?: number;
  onSessionUpdate?: (session: ITerminalSession) => void;
  onAuthComplete?: () => void;
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
  iframeBox: {
    width: '100%',
    height: '100%',
    position: 'relative',
    bgcolor: '#1e1e1e',
  },
  iframe: {
    width: '100%',
    height: '100%',
    border: 'none',
    backgroundColor: '#1e1e1e',
  },
  terminalIframe: {
    width: '100%',
    height: '100%',
    border: 'none',
    backgroundColor: '#1e1e1e',
  },
  loadingOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
    bgcolor: '#1e1e1e',
  },
  centeredBox: {
    width: '100%',
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
    bgcolor: '#1e1e1e',
  },
  loadingText: { color: '#d4d4d4', fontSize: '13px' },
  errorText: { color: '#f44747', fontSize: '13px' },
  emptyText: { color: '#808080', fontSize: '13px' },
  separator: {
    width: '4px',
    backgroundColor: '#3d3d3d',
    cursor: 'col-resize',
    transition: 'background-color 0.15s ease',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative' as const,
  },
  collapseButton: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 20,
    height: 40,
    borderRadius: '4px',
    bgcolor: '#3d3d3d',
    color: '#ccc',
    zIndex: 2,
    p: 0,
    minWidth: 0,
    '&:hover': { bgcolor: '#007acc', color: '#fff' },
  },
} as const;

const FINISHED_STATES = ['finished', 'failed'];

export const TerminalSessionWidget: React.FC<TerminalSessionWidgetProps> = ({
  sessionId,
  session: externalSession,
  showEditor = true,
  showTerminal = true,
  editorWidth = 66,
  onSessionUpdate,
  onAuthComplete,
}) => {
  const terminalIframeRef = useRef<HTMLIFrameElement>(null);
  const [terminalLoaded, setTerminalLoaded] = useState(false);
  const [editorLoaded, setEditorLoaded] = useState(false);
  const [editorCollapsed, setEditorCollapsed] = useState(false);

  const useInternalChannel = externalSession === undefined;
  const {
    session: channelSession,
    connecting,
    error,
  } = useTerminalSessionChannel({
    sessionId: useInternalChannel ? sessionId : null,
    onUpdate: onSessionUpdate,
    onAuthComplete,
  });

  const session = externalSession !== undefined ? externalSession : channelSession;

  const ttydUrl = useMemo(() => {
    if (!session?.websocketUrl) return null;
    return session.websocketUrl.replace('wss://', 'https://').replace('ws://', 'http://').replace('/ws', '');
  }, [session?.websocketUrl]);

  const ideUrl = session?.ideUrl ?? null;

  const handleTerminalLoad = useCallback(() => {
    setTerminalLoaded(true);
    terminalIframeRef.current?.focus();
  }, []);

  const handleEditorLoad = useCallback(() => {
    setEditorLoaded(true);
  }, []);

  const toggleEditorCollapse = useCallback(() => {
    setEditorCollapsed((prev) => !prev);
  }, []);

  // Reset state when session changes
  const prevSessionIdRef = useRef(sessionId);
  if (sessionId !== prevSessionIdRef.current) {
    prevSessionIdRef.current = sessionId;
    setTerminalLoaded(false);
    setEditorLoaded(false);
    setEditorCollapsed(false);
  }

  const isSessionReady = session?.state === 'ready';
  const canShowEditor = showEditor && !editorCollapsed && isSessionReady && !!ideUrl;
  const canShowTerminal = showTerminal && isSessionReady && !!ttydUrl;

  // --- Status screens ---

  if (!sessionId) {
    return (
      <Box sx={styles.centeredBox}>
        <Typography sx={styles.emptyText}>No session selected</Typography>
      </Box>
    );
  }

  if (connecting) {
    return (
      <Box sx={styles.centeredBox}>
        <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        <Typography sx={styles.loadingText}>Connecting to session...</Typography>
      </Box>
    );
  }

  if (error) {
    return (
      <Box sx={styles.centeredBox}>
        <Typography sx={styles.errorText}>{error}</Typography>
      </Box>
    );
  }

  if (!session) {
    return (
      <Box sx={styles.centeredBox}>
        <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        <Typography sx={styles.loadingText}>Loading session...</Typography>
      </Box>
    );
  }

  if (!isSessionReady) {
    const isFinished = FINISHED_STATES.includes(session.state);

    return (
      <Box sx={styles.centeredBox}>
        {isFinished ? (
          <>
            <Typography sx={{ color: session.state === 'failed' ? '#f44747' : '#808080', fontSize: '15px' }}>
              Session {session.state}
            </Typography>
            {session.errorMessage && <Typography sx={styles.errorText}>{session.errorMessage}</Typography>}
          </>
        ) : (
          <>
            <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
            <Typography sx={styles.loadingText}>
              {session.state === 'running' ? 'Starting container…' : `Waiting (${session.state})…`}
            </Typography>
          </>
        )}
        <SessionSummaryCard session={session} />
      </Box>
    );
  }

  if (!canShowEditor && !canShowTerminal) {
    return (
      <Box sx={styles.centeredBox}>
        <Typography sx={styles.emptyText}>No panels enabled</Typography>
      </Box>
    );
  }

  // --- Panel renderers ---

  const renderEditorPanel = () => (
    <Box sx={styles.iframeBox}>
      {!editorLoaded && (
        <Box sx={styles.loadingOverlay}>
          <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
          <Typography sx={styles.loadingText}>Loading editor...</Typography>
        </Box>
      )}
      <iframe src={ideUrl!} style={styles.iframe} title="VS Code Editor" onLoad={handleEditorLoad} />
    </Box>
  );

  const renderTerminalPanel = () => (
    <Box sx={{ ...styles.iframeBox, bgcolor: '#000' }}>
      {!terminalLoaded && (
        <Box sx={styles.loadingOverlay}>
          <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
          <Typography sx={styles.loadingText}>Connecting to terminal...</Typography>
        </Box>
      )}
      <iframe
        ref={terminalIframeRef}
        src={ttydUrl!}
        style={styles.terminalIframe}
        title="Terminal"
        onLoad={handleTerminalLoad}
      />
    </Box>
  );

  // --- Single panel ---

  if (!canShowEditor && canShowTerminal) {
    const showCollapseToggle = showEditor && isSessionReady && !!ideUrl && editorCollapsed;
    return (
      <Box sx={styles.container}>
        {showCollapseToggle && (
          <Box
            sx={{
              display: 'flex',
              alignItems: 'center',
              bgcolor: '#252525',
              borderRight: '1px solid #3d3d3d',
            }}
          >
            <IconButton onClick={toggleEditorCollapse} size="small" sx={{ color: '#ccc', p: 0.5 }}>
              <ChevronRightIcon fontSize="small" />
            </IconButton>
          </Box>
        )}
        {renderTerminalPanel()}
      </Box>
    );
  }

  if (canShowEditor && !canShowTerminal) {
    return <Box sx={styles.container}>{renderEditorPanel()}</Box>;
  }

  // --- Dual panel: editor + terminal ---

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

      <Group id="terminal-session-panels" orientation="horizontal" style={{ width: '100%', height: '100%' }}>
        <Panel defaultSize={editorWidth} minSize={30} style={styles.panel}>
          {renderEditorPanel()}
        </Panel>

        <Separator
          style={styles.separator}
          className="terminal-widget-resize-handle"
          onDoubleClick={toggleEditorCollapse}
        >
          <IconButton onClick={toggleEditorCollapse} sx={styles.collapseButton} size="small">
            <ChevronLeftIcon sx={{ fontSize: 16 }} />
          </IconButton>
        </Separator>

        <Panel defaultSize={100 - editorWidth} minSize={20} style={styles.panel}>
          {renderTerminalPanel()}
        </Panel>
      </Group>
    </Box>
  );
};
