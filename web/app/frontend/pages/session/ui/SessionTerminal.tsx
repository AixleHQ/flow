import { useCallback, useRef, useEffect } from 'react';
import { Box, Typography, Chip, Paper } from '@mui/material';
import { Terminal, TerminalHandle } from 'shared/ui/Terminal';
import { useTerminalWebSocket } from '@/shared/lib/hooks';

interface SessionTerminalProps {
  sessionId: string;
  stepName: string;
}

export function SessionTerminal({ sessionId, stepName }: SessionTerminalProps) {
  const terminalRef = useRef<TerminalHandle>(null);

  const handleOutput = useCallback((data: string) => {
    terminalRef.current?.write(data);
  }, []);

  const handleError = useCallback((message: string) => {
    terminalRef.current?.write(`\r\n\x1b[31m[Error: ${message}]\x1b[0m\r\n`);
  }, []);

  const handleDisconnect = useCallback((reason: string) => {
    terminalRef.current?.write(`\r\n\x1b[33m[Disconnected: ${reason}]\x1b[0m\r\n`);
  }, []);

  const { connected, connecting, sendInput, sendResize } = useTerminalWebSocket({
    sessionId,
    stepName,
    onOutput: handleOutput,
    onError: handleError,
    onDisconnect: handleDisconnect,
  });

  // Focus terminal when connected
  useEffect(() => {
    if (connected) {
      terminalRef.current?.focus();
    }
  }, [connected]);

  const handleData = useCallback(
    (data: string) => {
      sendInput(data);
    },
    [sendInput]
  );

  const handleResize = useCallback(
    (cols: number, rows: number) => {
      sendResize(cols, rows);
    },
    [sendResize]
  );

  const getStatusColor = () => {
    if (connecting) return 'warning';
    if (connected) return 'success';
    return 'error';
  };

  const getStatusLabel = () => {
    if (connecting) return 'Connecting...';
    if (connected) return 'Connected';
    return 'Disconnected';
  };

  return (
    <Paper
      elevation={3}
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        bgcolor: '#1e1e1e',
      }}
    >
      {/* Header */}
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          px: 2,
          py: 1,
          bgcolor: '#2d2d2d',
          borderBottom: '1px solid #3d3d3d',
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Typography variant="subtitle2" sx={{ color: '#d4d4d4' }}>
            {stepName}
          </Typography>
          <Typography variant="caption" sx={{ color: '#808080' }}>
            Session: {sessionId.slice(0, 8)}...
          </Typography>
        </Box>

        <Chip
          size="small"
          label={getStatusLabel()}
          color={getStatusColor()}
          sx={{ height: 24 }}
        />
      </Box>

      {/* Terminal */}
      <Box sx={{ flex: 1, overflow: 'hidden' }}>
        <Terminal
          ref={terminalRef}
          onData={handleData}
          onResize={handleResize}
          fontSize={14}
        />
      </Box>
    </Paper>
  );
}
