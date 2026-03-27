import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import AutoFixHighIcon from '@mui/icons-material/AutoFixHigh';
import DashboardIcon from '@mui/icons-material/Dashboard';
import ListAltIcon from '@mui/icons-material/ListAlt';
import { Box, Chip, CircularProgress, IconButton, Tab, Tabs, Tooltip, Typography, type SxProps } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useMemo, useState } from 'react';

import { useGetWorkflowRunQuery } from 'features/workflow-execution';
import { MetaActivityLog } from 'features/palad-builder/ui/MetaActivityLog';
import { WorkflowPreview } from 'features/palad-builder/ui/WorkflowPreview';
import { BoardPreview } from 'features/palad-builder/ui/BoardPreview';
import { useMetaActivityChannel } from 'features/palad-builder/lib/useMetaActivityChannel';
import { Routes } from 'shared/routes';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const styles = {
  root: { height: '100vh', display: 'flex', flexDirection: 'column', backgroundColor: 'background.default' },
  header: {
    display: 'flex', alignItems: 'center', gap: 2, px: 2, py: 1.5,
    borderBottom: '1px solid', borderColor: 'divider', backgroundColor: 'background.paper',
  },
  headerTitle: { fontSize: 18, fontWeight: 600, color: 'text.primary', display: 'flex', alignItems: 'center', gap: 1 },
  body: { flex: 1, display: 'flex', overflow: 'hidden' },
  terminal: { flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', borderRight: '1px solid', borderColor: 'divider' },
  activityPanel: { width: 280, display: 'flex', flexDirection: 'column', borderRight: '1px solid', borderColor: 'divider' },
  previewPanel: { width: 320, display: 'flex', flexDirection: 'column' },
  footer: {
    display: 'flex', alignItems: 'center', gap: 1, px: 2, py: 1,
    borderTop: '1px solid', borderColor: 'divider', backgroundColor: 'background.paper',
  },
  subStep: { fontSize: 12, display: 'flex', alignItems: 'center', gap: 0.5 },
  loading: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' },
} satisfies Record<string, SxProps>;

const STATE_COLORS: Record<string, 'success' | 'warning' | 'error' | 'info' | 'default'> = {
  completed: 'success', running: 'warning', paused: 'info', failed: 'error', cancelled: 'default', pending: 'default',
};

const PaladBuilderRunPage = () => {
  const { projectId, runId } = useParams({ strict: false }) as { projectId: string; runId: string };
  const navigate = useNavigate();
  const [previewTab, setPreviewTab] = useState(0);

  const runIdNum = Number(runId);
  const projectIdNum = Number(projectId);

  const { data: run, refetch: refetchRun, isLoading } = useGetWorkflowRunQuery(
    { projectId: projectIdNum, runId: runIdNum },
    { skip: !runIdNum },
  );

  const { activities, connected } = useMetaActivityChannel({
    runId: runIdNum || null,
    onRunUpdate: refetchRun,
  });

  // Find target_workflow_id from activities or shared_context
  const targetWorkflowId = useMemo(() => {
    const createWfActivity = activities.find((a) => a.action === 'created_workflow');
    if (createWfActivity) return createWfActivity.entityId;
    return (run as any)?.sharedContext?.targetWorkflowId || null;
  }, [activities, run]);

  const currentStepRun = useMemo(() => {
    if (!run) return null;
    const stepRuns = (run as any)?.stepRuns || [];
    return stepRuns.find((sr: any) => ['running', 'waiting_input'].includes(sr.state)) || null;
  }, [run]);

  const terminalSessionId = currentStepRun?.terminalSessionId || null;

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
            <ArrowBackIcon />
          </IconButton>
        </Tooltip>
        <Typography sx={styles.headerTitle}>
          <AutoFixHighIcon sx={{ fontSize: 22, color: 'primary.main' }} />
          Palad Builder
        </Typography>
        <Chip
          label={run.state}
          size="small"
          color={STATE_COLORS[run.state] || 'default'}
        />
        {currentStepRun && (
          <Typography sx={{ fontSize: 13, color: 'text.secondary' }}>
            Step: {currentStepRun.stepName || `#${currentStepRun.stepId}`}
          </Typography>
        )}
        <Box sx={{ flex: 1 }} />
        {connected && <Chip label="Live" size="small" color="success" variant="outlined" />}
      </Box>

      {/* Body: Terminal | Activity | Preview */}
      <Box sx={styles.body}>
        {/* Terminal Panel */}
        <Box sx={styles.terminal}>
          {terminalSessionId ? (
            <TerminalSessionWidget sessionId={terminalSessionId} />
          ) : (
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: 'text.disabled' }}>
              {run.state === 'pending' ? 'Starting...' : run.state === 'completed' ? 'Build complete' : 'No active session'}
            </Box>
          )}
        </Box>

        {/* Activity Log Panel */}
        <Box sx={styles.activityPanel}>
          <MetaActivityLog activities={activities} />
        </Box>

        {/* Preview Panel (tabbed) */}
        <Box sx={styles.previewPanel}>
          <Tabs value={previewTab} onChange={(_, v) => setPreviewTab(v)} variant="fullWidth" sx={{ minHeight: 36 }}>
            <Tab icon={<ListAltIcon sx={{ fontSize: 16 }} />} iconPosition="start" label="Workflow" sx={{ minHeight: 36, fontSize: 12 }} />
            <Tab icon={<DashboardIcon sx={{ fontSize: 16 }} />} iconPosition="start" label="Board" sx={{ minHeight: 36, fontSize: 12 }} />
          </Tabs>
          <Box sx={{ flex: 1, overflow: 'hidden' }}>
            {previewTab === 0 && (
              <WorkflowPreview projectId={projectIdNum} workflowId={targetWorkflowId} activities={activities} />
            )}
            {previewTab === 1 && (
              <BoardPreview projectId={projectIdNum} activities={activities} />
            )}
          </Box>
        </Box>
      </Box>

      {/* Footer: Sub-step progress */}
      <Box sx={styles.footer}>
        {currentStepRun?.subStepRuns?.map((ssr: any) => (
          <Box key={ssr.id} sx={styles.subStep}>
            {ssr.state === 'completed' ? '\u2705' : ssr.state === 'in_progress' ? '\uD83D\uDD04' : '\u2B1C'}
            <Typography sx={{ fontSize: 12 }}>{ssr.subStepName || ssr.name}</Typography>
          </Box>
        )) || <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>No active sub-steps</Typography>}
      </Box>
    </Box>
  );
};

export default PaladBuilderRunPage;
