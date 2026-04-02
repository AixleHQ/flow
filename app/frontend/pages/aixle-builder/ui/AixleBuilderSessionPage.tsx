import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import DashboardIcon from '@mui/icons-material/Dashboard';
import ListAltIcon from '@mui/icons-material/ListAlt';
import StopIcon from '@mui/icons-material/Stop';
import { Box, Button, Chip, CircularProgress, Tab, Tabs, Typography, type SxProps } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useMemo, useState } from 'react';

import { useMetaActivityChannel } from 'features/aixle-builder/lib/useMetaActivityChannel';
import { BoardPreview } from 'features/aixle-builder/ui/BoardPreview';
import { MetaActivityLog, type MetaActivity } from 'features/aixle-builder/ui/MetaActivityLog';
import { WorkflowsListPreview } from 'features/aixle-builder/ui/WorkflowsListPreview';
import { useTerminalSession } from 'shared/lib';
import { Routes } from 'shared/routes';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const styles = {
  root: { height: 'calc(100vh - 64px)', display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    px: 2,
    py: 1,
    borderBottom: '1px solid',
    borderColor: 'divider',
    bgcolor: 'background.paper',
    flexShrink: 0,
  },
  headerLeft: { display: 'flex', alignItems: 'center', gap: 1.5 },
  headerRight: { display: 'flex', alignItems: 'center', gap: 1 },
  body: { flex: 1, display: 'flex', overflow: 'hidden' },
  terminalPanel: { flex: 1, minWidth: 0, overflow: 'hidden' },
  sidePanel: { width: 300, display: 'flex', flexDirection: 'column', borderLeft: '1px solid', borderColor: 'divider' },
  ended: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'column',
    gap: 2,
  },
  loading: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: 'calc(100vh - 64px)', gap: 2 },
} satisfies Record<string, SxProps>;

const STATE_COLORS: Record<string, 'success' | 'info' | 'warning' | 'error' | 'default'> = {
  ready: 'success',
  running: 'info',
  finished: 'default',
  failed: 'error',
  not_started: 'default',
};

const AixleBuilderSessionPage = () => {
  const { projectId, runId: sessionId } = useParams({ strict: false }) as { projectId: string; runId: string };
  const navigate = useNavigate();
  const [sideTab, setSideTab] = useState(0);
  const [isStopping, setIsStopping] = useState(false);

  const id = Number(sessionId);
  const projectIdNum = Number(projectId);

  const { session, isLoading, isError, finishSession } = useTerminalSession({
    sessionId: id && !isNaN(id) ? id : null,
  });

  // Real-time activities from WebSocket
  const { activities: realtimeActivities } = useMetaActivityChannel({
    sessionId: id && !isNaN(id) ? id : null,
  });

  // Merge persisted activities (from session.metadata) + real-time (from WebSocket)
  const allActivities = useMemo(() => {
    const persisted: MetaActivity[] = (session?.metadata?.builderActivities as MetaActivity[]) || [];
    const persistedTimestamps = new Set(persisted.map((a) => a.timestamp));
    const newOnly = realtimeActivities.filter((a) => !persistedTimestamps.has(a.timestamp));
    return [...persisted, ...newOnly];
  }, [session?.metadata?.builderActivities, realtimeActivities]);

  const isTerminal = ['finished', 'failed'].includes(session?.state ?? '');
  const isActive = ['running', 'ready'].includes(session?.state ?? '');

  const handleFinish = async () => {
    setIsStopping(true);
    try {
      await finishSession(id);
    } catch {
      // error already handled by RTK Query
    } finally {
      setTimeout(() => setIsStopping(false), 3000);
    }
  };

  if (isLoading && !session) {
    return (
      <Box sx={styles.loading}>
        <CircularProgress size={24} />
        <Typography color="text.secondary">Loading session...</Typography>
      </Box>
    );
  }

  if (isError && !session) {
    return (
      <Box sx={styles.loading}>
        <Typography color="error">Session not found</Typography>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Button
            size="small"
            startIcon={<ArrowBackIcon />}
            onClick={() => navigate({ to: Routes.frontend.aixleBuilderPath(projectId) })}
            sx={{ color: 'text.secondary', minWidth: 'auto' }}
          >
            Back
          </Button>
          <AutoFixHighIcon sx={{ fontSize: 20, color: 'primary.main' }} />
          <Typography variant="subtitle2">Aixle Builder</Typography>
          {session && <Chip size="small" label={session.state} color={STATE_COLORS[session.state] || 'default'} />}
          <Typography variant="caption" color="text.secondary">
            #{id}
          </Typography>
        </Box>
        <Box sx={styles.headerRight}>
          {isActive && (
            <Button
              size="small"
              variant="outlined"
              color="warning"
              startIcon={<StopIcon />}
              onClick={handleFinish}
              disabled={isStopping}
            >
              {isStopping ? 'Finishing...' : 'Finish Session'}
            </Button>
          )}
        </Box>
      </Box>

      {/* Body */}
      {isTerminal ? (
        <Box sx={styles.ended}>
          <AutoFixHighIcon sx={{ fontSize: 48, color: 'text.disabled' }} />
          <Typography variant="h6" color="text.secondary">
            Session {session?.state}
          </Typography>
          {session?.errorMessage && (
            <Typography variant="body2" color="error">
              {session.errorMessage}
            </Typography>
          )}
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" onClick={() => navigate({ to: Routes.frontend.aixleBuilderPath(projectId) })}>
              Back to Builder
            </Button>
            <Button variant="contained" onClick={() => navigate({ to: Routes.frontend.aixleBuilderPath(projectId) })}>
              Start New Build
            </Button>
          </Box>
        </Box>
      ) : (
        <Box sx={styles.body}>
          {/* Terminal — no editor */}
          <Box sx={styles.terminalPanel}>
            <TerminalSessionWidget sessionId={id} showEditor={false} showTerminal />
          </Box>

          {/* Side panel — Workflows + Board (auto-refresh from API) */}
          <Box sx={styles.sidePanel}>
            <Tabs
              value={sideTab}
              onChange={(_, v) => setSideTab(v)}
              variant="fullWidth"
              sx={{ minHeight: 36, borderBottom: '1px solid', borderColor: 'divider' }}
            >
              <Tab
                label={`Activity${allActivities.length ? ` (${allActivities.length})` : ''}`}
                sx={{ minHeight: 36, fontSize: 12, textTransform: 'none' }}
              />
              <Tab
                icon={<ListAltIcon sx={{ fontSize: 14 }} />}
                iconPosition="start"
                label="Workflows"
                sx={{ minHeight: 36, fontSize: 12, textTransform: 'none' }}
              />
              <Tab
                icon={<DashboardIcon sx={{ fontSize: 14 }} />}
                iconPosition="start"
                label="Board"
                sx={{ minHeight: 36, fontSize: 12, textTransform: 'none' }}
              />
            </Tabs>
            <Box sx={{ flex: 1, overflow: 'hidden' }}>
              {sideTab === 0 && <MetaActivityLog activities={allActivities} />}
              {sideTab === 1 && <WorkflowsListPreview projectId={projectIdNum} />}
              {sideTab === 2 && <BoardPreview projectId={projectIdNum} activities={allActivities} />}
            </Box>
          </Box>
        </Box>
      )}
    </Box>
  );
};

export default AixleBuilderSessionPage;
