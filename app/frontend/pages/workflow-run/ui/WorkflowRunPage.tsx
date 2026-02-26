import {
  Alert,
  Box,
  Breadcrumbs,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  Link,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import {
  useApproveStepMutation,
  useCancelWorkflowRunMutation,
  useGetWorkflowRunQuery,
  useRetryStepMutation,
  useSkipStepMutation,
} from 'features/workflow-execution';
import { WorkflowAssetsReview } from 'features/workflow-execution/ui/WorkflowAssetsReview';
import type { StepRunInfo, WorkflowRun } from 'features/workflow-execution';
import { useGetStepsQuery } from 'features/workflow-steps/api/stepsApi';
import { useWorkflowRunChannel } from 'shared/lib/hooks';
import { Routes } from 'shared/routes';
import { StatusBar } from 'shared/ui';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const styles = {
  root: {
    height: '100vh',
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'background.default',
  },
  header: {
    padding: '12px 24px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
  },
  headerLeft: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  breadcrumbs: {
    '& .MuiBreadcrumbs-separator': { marginX: '8px' },
  },
  breadcrumbLink: {
    color: 'text.secondary',
    textDecoration: 'none',
    cursor: 'pointer',
    fontSize: '13px',
    '&:hover': { color: 'text.primary' },
  },
  title: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  actionButton: {
    padding: '8px',
    color: 'text.secondary',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '6px',
    '&:hover': { backgroundColor: 'action.hover', borderColor: 'border.strong' },
  },
  dangerButton: {
    color: 'error.main',
    borderColor: 'error.main',
    '&:hover': { backgroundColor: 'rgba(239, 68, 68, 0.1)' },
  },
  stepsContainer: {
    backgroundColor: 'background.paper',
    borderBottom: '1px solid',
    borderColor: 'divider',
    padding: '16px 24px',
    flexShrink: 0,
  },
  stepsHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: '12px',
  },
  stepsTitle: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
  },
  stepsList: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    overflowX: 'auto',
    overflowY: 'hidden',
    flexWrap: 'nowrap',
    paddingBottom: '8px',
    scrollBehavior: 'smooth',
    '&::-webkit-scrollbar': { height: '6px' },
    '&::-webkit-scrollbar-track': { backgroundColor: 'background.elevated', borderRadius: '3px' },
    '&::-webkit-scrollbar-thumb': {
      backgroundColor: 'divider',
      borderRadius: '3px',
      '&:hover': { backgroundColor: 'text.disabled' },
    },
  },
  stepItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 12px',
    backgroundColor: 'background.elevated',
    borderRadius: '6px',
    cursor: 'pointer',
    flexShrink: 0,
    border: '1px solid transparent',
    transition: 'all 0.2s ease',
    '&:hover': { borderColor: 'border.strong' },
  },
  stepItemActive: { borderColor: 'primary.main', backgroundColor: 'action.selected' },
  stepIndicator: {
    width: '24px',
    height: '24px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    fontWeight: 600,
    flexShrink: 0,
  },
  stepIndicatorCompleted: { backgroundColor: 'success.main', color: 'white' },
  stepIndicatorRunning: {
    backgroundColor: 'primary.main',
    color: 'white',
    animation: 'pulse 2s infinite',
    '@keyframes pulse': { '0%, 100%': { opacity: 1 }, '50%': { opacity: 0.6 } },
  },
  stepIndicatorPending: {
    backgroundColor: 'background.paper',
    border: '2px solid',
    borderColor: 'divider',
    color: 'text.disabled',
  },
  stepIndicatorFailed: { backgroundColor: 'error.main', color: 'white' },
  stepIndicatorSkipped: { backgroundColor: 'text.disabled', color: 'white' },
  stepIndicatorWaiting: {
    backgroundColor: 'warning.main',
    color: 'white',
    animation: 'pulse 2s infinite',
    '@keyframes pulse': { '0%, 100%': { opacity: 1 }, '50%': { opacity: 0.6 } },
  },
  stepInfo: { display: 'flex', flexDirection: 'column', gap: '2px' },
  stepName: { fontSize: '13px', fontWeight: 500, color: 'text.primary', whiteSpace: 'nowrap' },
  stepMeta: {
    fontSize: '11px',
    color: 'text.secondary',
    fontFamily: '"JetBrains Mono", monospace',
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  stepConnector: { width: '24px', height: '2px', backgroundColor: 'divider', flexShrink: 0 },
  stepConnectorCompleted: { backgroundColor: 'success.main' },
  main: { flex: 1, display: 'flex', overflow: 'hidden' },
  contentArea: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  splitContainer: { flex: 1, display: 'flex', flexDirection: 'row', overflow: 'hidden' },
  terminalPanel: {
    flex: 1,
    minWidth: '300px',
    backgroundColor: '#0D0D0D',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  panelHeader: {
    padding: '8px 16px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
    backgroundColor: 'background.elevated',
  },
  panelTitle: {
    fontSize: '12px',
    fontWeight: 500,
    color: 'text.secondary',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  panelContent: { flex: 1, overflow: 'auto' },
  placeholder: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    gap: '8px',
  },
  placeholderText: { fontSize: '13px', color: 'text.secondary' },
  placeholderSubtext: { fontSize: '11px', color: 'text.disabled' },
  loading: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' },
  subStepsPanel: {
    width: 280,
    minWidth: 240,
    borderLeft: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    flexShrink: 0,
  },
  subStepsList: {
    flex: 1,
    overflow: 'auto',
    padding: '8px 0',
  },
  subStepItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: '10px',
    padding: '8px 16px',
    '&:not(:last-child)': { borderBottom: '1px solid', borderColor: 'divider' },
  },
  subStepCheck: {
    width: 20,
    height: 20,
    borderRadius: '4px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '11px',
    fontWeight: 700,
    flexShrink: 0,
    marginTop: '2px',
  },
  subStepCheckPending: { border: '2px solid', borderColor: 'divider', color: 'text.disabled' },
  subStepCheckInProgress: { backgroundColor: 'primary.main', color: 'white', animation: 'pulse 2s infinite' },
  subStepCheckCompleted: { backgroundColor: 'success.main', color: 'white' },
  subStepCheckSkipped: { backgroundColor: 'text.disabled', color: 'white' },
  subStepContent: { flex: 1, minWidth: 0 },
  subStepName: { fontSize: '12px', fontWeight: 500, color: 'text.primary', lineHeight: 1.4 },
  subStepNote: { fontSize: '11px', color: 'text.secondary', mt: '2px', fontStyle: 'italic' },
  stepActionBar: {
    padding: '12px 24px',
    borderTop: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
  },
  stepActionBarLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  stepActionBarRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
} satisfies Record<string, SxProps<Theme>>;

function getStepIndicatorStyle(state: string): SxProps<Theme> {
  switch (state) {
    case 'completed':
      return styles.stepIndicatorCompleted;
    case 'running':
      return styles.stepIndicatorRunning;
    case 'waiting_input':
      return styles.stepIndicatorWaiting;
    case 'failed':
      return styles.stepIndicatorFailed;
    case 'skipped':
      return styles.stepIndicatorSkipped;
    default:
      return styles.stepIndicatorPending;
  }
}

function getStepIcon(state: string, index: number): string {
  switch (state) {
    case 'completed':
      return '\u2713';
    case 'running':
      return '\u25CF';
    case 'waiting_input':
      return '\u270B';
    case 'failed':
      return '\u2717';
    case 'skipped':
      return '\u2192';
    default:
      return String(index + 1);
  }
}

function formatDuration(startedAt: string | null, completedAt?: string | null): string {
  if (!startedAt) return '--';
  const start = new Date(startedAt);
  const end = completedAt ? new Date(completedAt) : new Date();
  const diffMs = end.getTime() - start.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffSecs = Math.floor((diffMs % 60000) / 1000);
  return `${diffMins}m ${diffSecs}s`;
}

function isRunActive(run: WorkflowRun): boolean {
  return ['pending', 'running', 'paused'].includes(run.state);
}

const WorkflowRunPage = () => {
  const navigate = useNavigate();
  const params = useParams({ strict: false }) as { projectId?: string; runId?: string };
  const projectId = Number(params.projectId);
  const runId = Number(params.runId);

  const [activeStepRunId, setActiveStepRunId] = useState<number | null>(null);
  const [skipDialogOpen, setSkipDialogOpen] = useState(false);
  const [skipReason, setSkipReason] = useState('');

  const {
    data: initialRun,
    isLoading,
    isError,
  } = useGetWorkflowRunQuery(
    { projectId, runId },
    { skip: !projectId || !runId },
  );

  const { workflowRun: liveRun } = useWorkflowRunChannel({
    runId: runId || null,
  });

  const workflowRun = liveRun ?? initialRun;

  const { data: workflowSteps = [] } = useGetStepsQuery(
    { projectId, workflowId: workflowRun?.workflowId ?? 0 },
    { skip: !workflowRun?.workflowId },
  );

  const [approveStep, { isLoading: approving }] = useApproveStepMutation();
  const [retryStep, { isLoading: retrying }] = useRetryStepMutation();
  const [skipStep, { isLoading: skipping }] = useSkipStepMutation();
  const [cancelRun, { isLoading: cancelling }] = useCancelWorkflowRunMutation();

  const stepRuns: StepRunInfo[] = workflowRun?.stepRuns ?? [];

  interface TimelineStep {
    stepId: number;
    stepName: string;
    position: number;
    wave: number;
    stepRun: StepRunInfo | null;
    state: string;
    isParallel: boolean;
  }

  const timelineSteps: TimelineStep[] = useMemo(() => {
    if (workflowSteps.length === 0) {
      return stepRuns.map((sr, i) => ({
        stepId: sr.stepId,
        stepName: sr.stepName,
        position: i + 1,
        wave: i,
        stepRun: sr,
        state: sr.state,
        isParallel: false,
      }));
    }

    const sorted = workflowSteps.slice().sort((a, b) => a.position - b.position);
    const waveMap = new Map<number, number>();

    sorted.forEach((step) => {
      const deps = step.dependsOnStepIds ?? [];
      if (deps.length === 0) {
        waveMap.set(step.id, 0);
      } else {
        const maxDepWave = Math.max(...deps.map((d) => waveMap.get(d) ?? 0));
        waveMap.set(step.id, maxDepWave + 1);
      }
    });

    const waveCounts = new Map<number, number>();
    sorted.forEach((step) => {
      const w = waveMap.get(step.id) ?? 0;
      waveCounts.set(w, (waveCounts.get(w) ?? 0) + 1);
    });

    return sorted.map((step) => {
      const sr = stepRuns.find((r) => r.stepId === step.id) ?? null;
      const wave = waveMap.get(step.id) ?? 0;
      return {
        stepId: step.id,
        stepName: step.name,
        position: step.position,
        wave,
        stepRun: sr,
        state: sr?.state ?? 'pending',
        isParallel: (waveCounts.get(wave) ?? 1) > 1,
      };
    });
  }, [workflowSteps, stepRuns]);

  const timelineWaves = useMemo(() => {
    const grouped = new Map<number, TimelineStep[]>();
    timelineSteps.forEach((ts) => {
      grouped.set(ts.wave, [...(grouped.get(ts.wave) ?? []), ts]);
    });
    return Array.from(grouped.entries())
      .sort(([a], [b]) => a - b)
      .map(([wave, steps]) => ({ wave, steps }));
  }, [timelineSteps]);

  const currentStepRun = stepRuns.find((s) => s.state === 'running' || s.state === 'waiting_input');
  const selectedTimelineStep = activeStepRunId
    ? timelineSteps.find((t) => t.stepRun?.id === activeStepRunId)
    : timelineSteps.find((t) => t.stepRun?.id === currentStepRun?.id) ?? timelineSteps[0] ?? null;
  const selectedStepRun = selectedTimelineStep?.stepRun ?? null;

  const prevCurrentIdRef = useRef<number | undefined>(undefined);
  useEffect(() => {
    if (currentStepRun && currentStepRun.id !== prevCurrentIdRef.current) {
      prevCurrentIdRef.current = currentStepRun.id;
      setActiveStepRunId(currentStepRun.id);
    }
  }, [currentStepRun]);

  const handleApprove = useCallback(() => {
    approveStep({ projectId, runId });
  }, [approveStep, projectId, runId]);

  const handleRetry = useCallback(() => {
    retryStep({ projectId, runId });
  }, [retryStep, projectId, runId]);

  const handleSkip = useCallback(() => {
    skipStep({ projectId, runId, reason: skipReason || undefined });
    setSkipDialogOpen(false);
    setSkipReason('');
  }, [skipStep, projectId, runId, skipReason]);

  const handleCancel = useCallback(() => {
    cancelRun({ projectId, runId });
  }, [cancelRun, projectId, runId]);

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <CircularProgress />
        </Box>
      </Box>
    );
  }

  if (isError || !workflowRun) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <Alert severity="error" sx={{ maxWidth: 400 }}>
            Workflow run not found
          </Alert>
        </Box>
      </Box>
    );
  }

  const completedCount = timelineSteps.filter((t) => t.state === 'completed').length;
  const progressIndex = completedCount + (currentStepRun ? 1 : 0);
  const canAct = selectedStepRun?.state === 'waiting_input' && isRunActive(workflowRun);
  const sessionStatus = isRunActive(workflowRun)
    ? 'running'
    : workflowRun.state === 'completed'
      ? 'completed'
      : 'error';

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Breadcrumbs sx={styles.breadcrumbs}>
            <Link
              sx={styles.breadcrumbLink}
              onClick={() => navigate({ to: Routes.frontend.companyProjectsPath })}
            >
              Projects
            </Link>
            <Link
              sx={styles.breadcrumbLink}
              onClick={() =>
                navigate({ to: Routes.frontend.companyProjectTabPath(String(workflowRun.projectId), 'workflows') })
              }
            >
              Project
            </Link>
            <Link
              sx={styles.breadcrumbLink}
              onClick={() =>
                navigate({ to: Routes.frontend.companyProjectTabPath(String(workflowRun.projectId), 'runs') })
              }
            >
              Runs
            </Link>
            <Typography color="text.primary" sx={{ fontSize: '13px' }}>
              {workflowRun.workflowName ?? `Run #${workflowRun.id}`}
            </Typography>
          </Breadcrumbs>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <Typography sx={styles.title}>
              {workflowRun.workflowName ?? 'Workflow Run'}
            </Typography>
            <Typography
              sx={{
                fontSize: '12px',
                fontWeight: 500,
                textTransform: 'uppercase',
                color:
                  workflowRun.state === 'running'
                    ? 'primary.main'
                    : workflowRun.state === 'completed'
                      ? 'success.main'
                      : workflowRun.state === 'failed'
                        ? 'error.main'
                        : 'text.secondary',
              }}
            >
              {workflowRun.state}
            </Typography>
          </Box>
        </Box>
        <Box sx={styles.headerRight}>
          {isRunActive(workflowRun) && (
            <Tooltip title="Cancel Workflow">
              <IconButton
                sx={{ ...styles.actionButton, ...styles.dangerButton }}
                onClick={handleCancel}
                disabled={cancelling}
              >
                <span style={{ fontSize: '14px' }}>{'\u25A0'}</span>
              </IconButton>
            </Tooltip>
          )}
        </Box>
      </Box>

      {/* Step Timeline — GitHub CI style */}
      <Box sx={styles.stepsContainer}>
        <Box sx={styles.stepsHeader}>
          <Typography sx={styles.stepsTitle}>Workflow Steps</Typography>
          <Typography sx={{ fontSize: '12px', color: 'text.secondary' }}>
            {completedCount}/{timelineSteps.length} completed
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 0, overflowX: 'auto', pb: 1 }}>
          {timelineWaves.map((wave, waveIdx) => {
            const allCompleted = wave.steps.every((t) => t.state === 'completed');
            return (
              <Box key={wave.wave} sx={{ display: 'flex', alignItems: 'center' }}>
                {/* Wave column */}
                <Box
                  sx={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '6px',
                    minWidth: 160,
                  }}
                >
                  {wave.steps.map((ts, stepIdx) => (
                    <Box
                      key={ts.stepId}
                      sx={{
                        ...styles.stepItem,
                        ...(selectedTimelineStep?.stepId === ts.stepId ? styles.stepItemActive : {}),
                      }}
                      onClick={() => ts.stepRun && setActiveStepRunId(ts.stepRun.id)}
                    >
                      <Box sx={{ ...styles.stepIndicator, ...getStepIndicatorStyle(ts.state) }}>
                        {getStepIcon(ts.state, stepIdx)}
                      </Box>
                      <Box sx={styles.stepInfo}>
                        <Typography sx={styles.stepName}>{ts.stepName}</Typography>
                        <Box sx={styles.stepMeta}>
                          <Typography component="span">{ts.state}</Typography>
                          {ts.stepRun?.startedAt && (
                            <Typography component="span">
                              {formatDuration(ts.stepRun.startedAt, ts.stepRun.completedAt)}
                            </Typography>
                          )}
                        </Box>
                      </Box>
                    </Box>
                  ))}
                </Box>
                {/* Connector between waves */}
                {waveIdx < timelineWaves.length - 1 && (
                  <Box
                    sx={{
                      width: 32,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      alignSelf: 'center',
                      flexShrink: 0,
                    }}
                  >
                    <Box
                      sx={{
                        width: 24,
                        height: 2,
                        backgroundColor: allCompleted ? 'success.main' : 'divider',
                      }}
                    />
                  </Box>
                )}
              </Box>
            );
          })}
        </Box>
      </Box>

      {/* Main Content */}
      <Box sx={styles.main}>
        <Box sx={styles.contentArea}>
          <Box sx={styles.splitContainer}>
            <Box sx={styles.terminalPanel}>
              <Box sx={{ ...styles.panelHeader, backgroundColor: '#1A1A1A' }}>
                <Box sx={styles.panelTitle}>
                  <span style={{ fontSize: '14px' }}>{'\u2B1B'}</span>
                  <Typography component="span" sx={{ color: 'text.primary' }}>
                    Terminal
                  </Typography>
                  {selectedTimelineStep && (
                    <Typography component="span" sx={{ color: 'text.disabled', fontSize: '11px' }}>
                      {'\u2014'} {selectedTimelineStep.stepName}
                    </Typography>
                  )}
                </Box>
              </Box>
              <Box sx={{ ...styles.panelContent, position: 'relative' }}>
                {selectedStepRun?.terminalSessionId ? (
                  <TerminalSessionWidget
                    sessionId={selectedStepRun.terminalSessionId}
                    showEditor={false}
                  />
                ) : (
                  <Box sx={styles.placeholder}>
                    <Typography sx={styles.placeholderText}>
                      {selectedTimelineStep
                        ? `Terminal for "${selectedTimelineStep.stepName}"`
                        : 'Select a step to view terminal'}
                    </Typography>
                    <Typography sx={styles.placeholderSubtext}>
                      {selectedTimelineStep
                        ? 'No terminal session assigned yet'
                        : 'Select a running step from the timeline above'}
                    </Typography>
                  </Box>
                )}
              </Box>
            </Box>

            {/* Sub-steps sidebar */}
            {selectedStepRun && (selectedStepRun.subStepRuns ?? []).length > 0 && (
              <Box sx={styles.subStepsPanel}>
                <Box sx={styles.panelHeader}>
                  <Box sx={styles.panelTitle}>
                    <Typography component="span" sx={{ color: 'text.primary' }}>
                      Sub-steps
                    </Typography>
                    <Typography component="span" sx={{ color: 'text.disabled', fontSize: '11px' }}>
                      {(selectedStepRun.subStepRuns ?? []).filter((s) => s.state === 'completed').length}/
                      {(selectedStepRun.subStepRuns ?? []).length}
                    </Typography>
                  </Box>
                </Box>
                <Box sx={styles.subStepsList}>
                  {(selectedStepRun.subStepRuns ?? []).map((ssr) => (
                    <Box key={ssr.id} sx={styles.subStepItem}>
                      <Box
                        sx={{
                          ...styles.subStepCheck,
                          ...(ssr.state === 'completed'
                            ? styles.subStepCheckCompleted
                            : ssr.state === 'in_progress'
                              ? styles.subStepCheckInProgress
                              : ssr.state === 'skipped'
                                ? styles.subStepCheckSkipped
                                : styles.subStepCheckPending),
                        }}
                      >
                        {ssr.state === 'completed'
                          ? '\u2713'
                          : ssr.state === 'in_progress'
                            ? '\u25CF'
                            : ssr.state === 'skipped'
                              ? '\u2192'
                              : ''}
                      </Box>
                      <Box sx={styles.subStepContent}>
                        <Typography sx={styles.subStepName}>{ssr.subStepName}</Typography>
                        {ssr.note && (
                          <Typography sx={styles.subStepNote}>{ssr.note}</Typography>
                        )}
                      </Box>
                    </Box>
                  ))}
                </Box>
                {selectedStepRun.stepNote && (
                  <Box
                    sx={{
                      borderTop: '1px solid',
                      borderColor: 'divider',
                      padding: '8px 16px',
                    }}
                  >
                    <Typography sx={{ fontSize: '11px', fontWeight: 600, color: 'text.secondary', mb: '4px' }}>
                      Step Note
                    </Typography>
                    <Typography
                      sx={{ fontSize: '12px', color: 'text.primary', whiteSpace: 'pre-wrap', lineHeight: 1.4 }}
                    >
                      {selectedStepRun.stepNote}
                    </Typography>
                  </Box>
                )}
              </Box>
            )}
          </Box>

          {/* Step Action Bar */}
          {canAct && selectedStepRun && (
            <Box sx={styles.stepActionBar}>
              <Box sx={styles.stepActionBarLeft}>
                <Typography sx={{ fontSize: '13px', fontWeight: 500, color: 'text.primary' }}>
                  {selectedStepRun.stepName}
                </Typography>
                <Typography sx={{ fontSize: '12px', color: 'warning.main' }}>
                  Waiting for your decision
                </Typography>
              </Box>
              <Box sx={styles.stepActionBarRight}>
                <Button
                  variant="outlined"
                  size="small"
                  color="inherit"
                  onClick={() => setSkipDialogOpen(true)}
                  disabled={skipping}
                >
                  Skip
                </Button>
                <Button
                  variant="outlined"
                  size="small"
                  color="warning"
                  onClick={handleRetry}
                  disabled={retrying}
                >
                  Retry
                </Button>
                <Button
                  variant="contained"
                  size="small"
                  color="primary"
                  onClick={handleApprove}
                  disabled={approving}
                >
                  Approve & Continue
                </Button>
              </Box>
            </Box>
          )}

          {/* Failed step action bar */}
          {selectedStepRun?.state === 'failed' && isRunActive(workflowRun) && (
            <Box sx={styles.stepActionBar}>
              <Box sx={styles.stepActionBarLeft}>
                <Typography sx={{ fontSize: '13px', fontWeight: 500, color: 'error.main' }}>
                  {selectedStepRun.stepName} — Failed
                </Typography>
                {selectedStepRun.errorMessage && (
                  <Typography sx={{ fontSize: '12px', color: 'text.secondary' }}>
                    {selectedStepRun.errorMessage}
                  </Typography>
                )}
              </Box>
              <Box sx={styles.stepActionBarRight}>
                <Button
                  variant="outlined"
                  size="small"
                  color="inherit"
                  onClick={() => setSkipDialogOpen(true)}
                  disabled={skipping}
                >
                  Skip
                </Button>
                <Button
                  variant="contained"
                  size="small"
                  color="warning"
                  onClick={handleRetry}
                  disabled={retrying}
                >
                  Retry
                </Button>
              </Box>
            </Box>
          )}

          {(workflowRun.state === 'completed' || workflowRun.state === 'failed') && (
            <WorkflowAssetsReview
              projectId={projectId}
              runId={runId}
              stepNameMap={Object.fromEntries(
                stepRuns.map((sr) => [sr.id, sr.stepName])
              )}
            />
          )}

          <StatusBar
            status={sessionStatus}
            duration={formatDuration(workflowRun.startedAt, workflowRun.completedAt)}
          />
        </Box>
      </Box>

      {/* Skip Reason Dialog */}
      <Dialog open={skipDialogOpen} onClose={() => setSkipDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Skip Step</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Reason (optional)"
            fullWidth
            multiline
            rows={3}
            value={skipReason}
            onChange={(e) => setSkipReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSkipDialogOpen(false)}>Cancel</Button>
          <Button onClick={handleSkip} variant="contained" disabled={skipping}>
            Skip Step
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default WorkflowRunPage;
