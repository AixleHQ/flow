import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import DashboardIcon from '@mui/icons-material/Dashboard';
import ListAltIcon from '@mui/icons-material/ListAlt';
import StopIcon from '@mui/icons-material/Stop';
import { Box, Button, Chip, CircularProgress, IconButton, Tab, Tabs, Tooltip, Typography, type SxProps } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useCallback, useMemo, useState } from 'react';
import { useSnackbar } from 'notistack';

import { useGetWorkflowRunQuery } from 'features/workflow-execution';
import { useFinishSessionMutation } from 'shared/api/terminalSessionApi';
import { MetaActivityLog } from 'features/palad-builder/ui/MetaActivityLog';
import { WorkflowPreview } from 'features/palad-builder/ui/WorkflowPreview';
import { BoardPreview } from 'features/palad-builder/ui/BoardPreview';
import { useMetaActivityChannel } from 'features/palad-builder/lib/useMetaActivityChannel';
import { useWorkflowRunChannel } from 'shared/lib/hooks';
import { Routes } from 'shared/routes';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const styles = {
  root: { height: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: 'background.default' },
  header: {
    display: 'flex', alignItems: 'center', gap: 2, px: 2, py: 1,
    borderBottom: '1px solid', borderColor: 'divider', backgroundColor: 'background.paper',
    minHeight: 48,
  },
  headerTitle: { fontSize: 16, fontWeight: 600, color: 'text.primary', display: 'flex', alignItems: 'center', gap: 1 },
  body: { flex: 1, display: 'flex', overflow: 'hidden' },
  terminalPanel: { flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' },
  sidePanel: {
    width: 300, display: 'flex', flexDirection: 'column',
    borderLeft: '1px solid', borderColor: 'divider',
  },
  loading: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' },
  emptyTerminal: {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    height: '100%', color: 'text.disabled', fontSize: 14,
  },
} satisfies Record<string, SxProps>;

const STATE_COLORS: Record<string, 'success' | 'warning' | 'error' | 'info' | 'default'> = {
  completed: 'success', running: 'warning', paused: 'info', failed: 'error', cancelled: 'default', pending: 'default',
};

const PaladBuilderRunPage = () => {
  const { projectId, runId } = useParams({ strict: false }) as { projectId: string; runId: string };
  const navigate = useNavigate();
  const [sideTab, setSideTab] = useState(0);

  const runIdNum = Number(runId);
  const projectIdNum = Number(projectId);

  const { data: run, refetch: refetchRun, isLoading } = useGetWorkflowRunQuery(
    { projectId: projectIdNum, runId: runIdNum },
    { skip: !runIdNum, pollingInterval: 5000 },
  );

  // Subscribe to workflow run channel for real-time updates
  useWorkflowRunChannel({ runId: runIdNum || null, onUpdate: refetchRun });

  // Subscribe to meta activity events
  const { activities, connected } = useMetaActivityChannel({
    runId: runIdNum || null,
    onRunUpdate: refetchRun,
  });

  // Single step — find the one step run and its terminal session
  const stepRun = useMemo(() => {
    const stepRuns = (run as any)?.stepRuns || [];
    return stepRuns[0] || null;
  }, [run]);

  const terminalSessionId = stepRun?.terminalSessionId || null;
  const isRunActive = ['running', 'paused'].includes(run?.state || '');

  // Finish session
  const { enqueueSnackbar } = useSnackbar();
  const [finishSession] = useFinishSessionMutation();
  const handleFinish = useCallback(async () => {
    if (!terminalSessionId) return;
    try {
      await finishSession({ sessionId: terminalSessionId }).unwrap();
      enqueueSnackbar('Session finished', { variant: 'success' });
      refetchRun();
    } catch {
      enqueueSnackbar('Failed to finish session', { variant: 'error' });
    }
  }, [terminalSessionId, finishSession, enqueueSnackbar, refetchRun]);

  // Find target workflow ID from meta activities
  const targetWorkflowId = useMemo(() => {
    const createWfActivity = activities.find((a) => a.action === 'created_workflow');
    if (createWfActivity) return createWfActivity.entityId;
    return (run as any)?.sharedContext?.targetWorkflowId || null;
  }, [activities, run]);

  if (isLoading) {
    return <Box sx={styles.loading}><CircularProgress /></Box>;
  }

  if (!run) {
    return (
      <Box sx={styles.loading}>
        <Typography color="text.secondary">Run not found</Typography>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Tooltip title="Back to Palad Builder">
          <IconButton size="small" onClick={() => navigate({ to: Routes.frontend.paladBuilderPath(projectId) })}>
            <ArrowBackIcon fontSize="small" />
          </IconButton>
        </Tooltip>
        <AutoFixHighIcon sx={{ fontSize: 20, color: 'primary.main' }} />
        <Typography sx={styles.headerTitle}>Palad Builder</Typography>
        <Chip label={run.state} size="small" color={STATE_COLORS[run.state] || 'default'} />
        <Box sx={{ flex: 1 }} />
        {isRunActive && terminalSessionId && (
          <Button
            size="small"
            variant="outlined"
            color="warning"
            startIcon={<StopIcon />}
            onClick={handleFinish}
          >
            Finish Session
          </Button>
        )}
        {connected && <Chip label="Live" size="small" color="success" variant="outlined" sx={{ height: 22 }} />}
      </Box>

      {/* Body: Terminal (main) | Side panel (activity/preview) */}
      <Box sx={styles.body}>
        {/* Terminal — full width, no editor */}
        <Box sx={styles.terminalPanel}>
          {terminalSessionId ? (
            <TerminalSessionWidget sessionId={terminalSessionId} showEditor={false} />
          ) : (
            <Box sx={styles.emptyTerminal}>
              {run.state === 'pending' ? 'Starting session...' :
               run.state === 'completed' ? 'Build complete' :
               run.state === 'failed' ? 'Build failed' :
               'Waiting for agent...'}
            </Box>
          )}
        </Box>

        {/* Side panel — tabs: Activity / Workflow / Board */}
        <Box sx={styles.sidePanel}>
          <Tabs
            value={sideTab}
            onChange={(_, v) => setSideTab(v)}
            variant="fullWidth"
            sx={{ minHeight: 36, borderBottom: '1px solid', borderColor: 'divider' }}
          >
            <Tab label="Activity" sx={{ minHeight: 36, fontSize: 12, textTransform: 'none' }} />
            <Tab
              icon={<ListAltIcon sx={{ fontSize: 14 }} />}
              iconPosition="start"
              label="Workflow"
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
            {sideTab === 0 && <MetaActivityLog activities={activities} />}
            {sideTab === 1 && (
              <WorkflowPreview projectId={projectIdNum} workflowId={targetWorkflowId} activities={activities} />
            )}
            {sideTab === 2 && (
              <BoardPreview projectId={projectIdNum} activities={activities} />
            )}
          </Box>
        </Box>
      </Box>
    </Box>
  );
};

export default PaladBuilderRunPage;
