import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Card,
  Group,
  Loader,
  Modal,
  Progress,
  ScrollArea,
  Stack,
  Text,
  Textarea,
  TextInput,
  Tooltip,
} from '@mantine/core';
import {
  IconArrowLeft,
  IconArrowRight,
  IconCheck,
  IconChevronRight,
  IconClock,
  IconDownload,
  IconPlayerPlay,
  IconPlayerStop,
  IconTerminal2,
  IconUpload,
  IconX,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import {
  exportAllApiV1ProjectWorkflowRunWorkflowRunAssetsPath,
  exportApiV1ProjectWorkflowRunWorkflowRunAssetPath,
  finishApiV1TerminalSessionPath,
} from 'shared/api/routes';
import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './ShowPage.module.css';

// ── Types ──────────────────────────────────────────

interface SubStepRun {
  id: number;
  state: string;
  subStepName: string | null;
  subStepDescription: string | null;
  startedAt: string | null;
  completedAt: string | null;
}

interface PastFailure {
  errorMessage: string | null;
  failedAt: string | null;
}

interface StepRun {
  id: number;
  stepId: number;
  stepName: string | null;
  stepPosition: number | null;
  state: string;
  stepNote: string | null;
  errorMessage: string | null;
  terminalSessionId: number | null;
  terminalSessionState: string | null;
  allowNonInteractive: boolean;
  startedAt: string | null;
  completedAt: string | null;
  terminalUrl: string | null;
  ideUrl: string | null;
  dependsOnStepIds: number[];
  dependsOnNames: string[];
  subStepRuns: SubStepRun[];
  pastFailures?: PastFailure[];
}

interface WorkflowRunAsset {
  id: number;
  name: string;
  contentType: string | null;
  fileSize: number | null;
  stepName: string | null;
  downloadUrl: string | null;
}

interface WorkflowRun {
  id: number;
  workflowId: number;
  workflowName: string;
  state: string;
  mode: string;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  stepsCompleted: number;
  stepsTotal: number;
  stepRuns: StepRun[];
  agentType: string | null;
  userName: string | null;
  costCents: number;
}

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  run: WorkflowRun;
  assets: WorkflowRunAsset[];
  cableStream: string;
}

// ── Constants ──────────────────────────────────────

const STATE_COLORS: Record<string, string> = {
  pending: 'gray',
  running: 'blue',
  in_progress: 'cyan',
  completed: 'green',
  failed: 'red',
  cancelled: 'gray',
  paused: 'yellow',
  waiting_input: 'orange',
  skipped: 'gray',
};

const ACTIVE_STATES = new Set(['pending', 'running', 'paused', 'waiting_input']);

const MODE_LABELS: Record<string, string> = {
  interactive: 'Interactive',
  non_interactive: 'Auto-run',
  mixed: 'Custom',
};

// ── Helpers ────────────────────────────────────────

function subStepLabel(ss: SubStepRun, fallback: string): string {
  const name = ss.subStepName;
  const isDefault = !name || /^Sub-step \d+$/i.test(name);
  if (!isDefault) return name;
  return ss.subStepDescription || fallback;
}

function stepIcon(state: string) {
  if (state === 'completed') return <IconCheck size={14} />;
  if (state === 'failed') return <IconX size={14} />;
  if (state === 'running') return <IconPlayerPlay size={14} />;
  if (state === 'waiting_input') return <IconClock size={14} />;
  return <IconClock size={14} />;
}

function formatDuration(startedAt: string | null, completedAt: string | null): string {
  if (!startedAt) return '—';
  const start = new Date(startedAt);
  const end = completedAt ? new Date(completedAt) : new Date();
  const seconds = Math.round((end.getTime() - start.getTime()) / 1000);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

function formatFileSize(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatCost(cents: number): string {
  if (!cents || cents === 0) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

// ── DAG Waves ──────────────────────────────────────

interface Wave {
  label: string;
  steps: StepRun[];
}

function computeWaves(steps: StepRun[]): Wave[] {
  const assigned = new Map<number, number>();
  const waves: Wave[] = [];
  let remaining = [...steps];

  while (remaining.length > 0) {
    const waveIndex = waves.length;
    const currentWave: StepRun[] = [];

    for (const step of remaining) {
      const deps = step.dependsOnStepIds ?? [];
      const allDepsAssigned = deps.every((depId) => assigned.has(depId) && assigned.get(depId)! < waveIndex);
      if (allDepsAssigned) currentWave.push(step);
    }

    if (currentWave.length === 0) {
      waves.push({ label: 'Remaining', steps: remaining });
      break;
    }

    for (const step of currentWave) assigned.set(step.stepId, waveIndex);

    const label =
      waveIndex === 0
        ? currentWave.length > 1
          ? 'Parallel start'
          : 'Start'
        : `After ${[...new Set(currentWave.flatMap((s) => s.dependsOnNames))].join(', ')}`;

    waves.push({ label, steps: currentWave });
    remaining = remaining.filter((s) => !assigned.has(s.stepId));
  }

  return waves;
}

// ── Live Duration ──────────────────────────────────

function LiveDuration({ startedAt }: { startedAt: string }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);
  const seconds = Math.max(0, Math.round((now - new Date(startedAt).getTime()) / 1000));
  const text =
    seconds < 60
      ? `${seconds}s`
      : seconds < 3600
        ? `${Math.floor(seconds / 60)}m ${seconds % 60}s`
        : `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;

  return (
    <Text size="xs" c="blue" ff="monospace" className={classes.elapsed}>
      {text}
    </Text>
  );
}

// ── Main Component ─────────────────────────────────

const WorkflowRunShowPage = () => {
  const { project, run, assets, cableStream } = usePage<{ props: Props }>().props as unknown as Props;

  const isActive = ACTIVE_STATES.has(run.state);
  const isTerminal = run.state === 'completed' || run.state === 'failed' || run.state === 'cancelled';

  const [selectedStepId, setSelectedStepId] = useState<number | null>(null);
  const [view, setView] = useState<'steps' | 'assets'>('steps');
  const [skipOpen, setSkipOpen] = useState(false);
  const [skipReason, setSkipReason] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [promoteOpen, setPromoteOpen] = useState<{ assetId: number | null; name: string } | null>(null);
  const [promoteFolder, setPromoteFolder] = useState('');
  const [promoteLoading, setPromoteLoading] = useState(false);

  useInertiaCableStream(cableStream, {
    only: ['run', 'assets'],
    enabled: !isTerminal,
  });

  const basePath = `/company/projects/${project.id}`;
  const runPath = `${basePath}/workflow_runs/${run.id}`;

  const sortedSteps = useMemo(
    () => [...run.stepRuns].sort((a, b) => (a.stepPosition ?? 0) - (b.stepPosition ?? 0)),
    [run.stepRuns],
  );

  const selectedStep = useMemo(
    () => sortedSteps.find((s) => s.id === selectedStepId) ?? null,
    [sortedSteps, selectedStepId],
  );

  const activeSteps = useMemo(
    () => sortedSteps.filter((s) => s.state === 'running' || s.state === 'waiting_input'),
    [sortedSteps],
  );

  const waves = useMemo(() => computeWaves(sortedSteps), [sortedSteps]);
  const hasDag = waves.length > 1 || waves.some((w) => w.steps.length > 1);

  const progressPct = run.stepsTotal > 0 ? (run.stepsCompleted / run.stepsTotal) * 100 : 0;

  // Auto-select: pick first active step on mount, or when no step is selected
  useEffect(() => {
    if (selectedStepId && sortedSteps.some((s) => s.id === selectedStepId)) return;
    const active = sortedSteps.find((s) => s.state === 'running' || s.state === 'waiting_input');
    setSelectedStepId(active?.id ?? sortedSteps[0]?.id ?? null);
  }, [sortedSteps]);

  // ── Actions ────────────────────────────────────

  const handleCancel = useCallback(() => {
    setActionLoading(true);
    router.post(
      `${runPath}/cancel`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setActionLoading(false),
      },
    );
  }, [runPath]);

  const handleApprove = useCallback(() => {
    setActionLoading(true);
    router.post(
      `${runPath}/approve_step`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setActionLoading(false),
      },
    );
  }, [runPath]);

  const handleSkip = useCallback(() => {
    setActionLoading(true);
    router.post(
      `${runPath}/skip_step`,
      { reason: skipReason || null },
      {
        preserveScroll: true,
        onFinish: () => {
          setActionLoading(false);
          setSkipOpen(false);
          setSkipReason('');
        },
      },
    );
  }, [runPath, skipReason]);

  const handleRetry = useCallback(() => {
    setActionLoading(true);
    router.post(
      `${runPath}/retry_step`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setActionLoading(false),
      },
    );
  }, [runPath]);

  const handleFinishSession = useCallback(async (sessionId: number) => {
    setActionLoading(true);
    try {
      await apiFetch(finishApiV1TerminalSessionPath(sessionId), { method: 'POST' });
      router.reload({ only: ['run'] });
    } finally {
      setActionLoading(false);
    }
  }, []);

  const handlePromote = useCallback(async () => {
    if (!promoteOpen) return;
    setPromoteLoading(true);
    try {
      const url = promoteOpen.assetId
        ? exportApiV1ProjectWorkflowRunWorkflowRunAssetPath(project.id, run.id, promoteOpen.assetId)
        : exportAllApiV1ProjectWorkflowRunWorkflowRunAssetsPath(project.id, run.id);
      await apiFetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder: promoteFolder || null }),
      });
      router.reload({ only: ['assets'] });
    } finally {
      setPromoteLoading(false);
      setPromoteOpen(null);
      setPromoteFolder('');
    }
  }, [project.id, run.id, promoteOpen, promoteFolder]);

  const stepIsInteractive = run.mode === 'interactive' || (run.mode === 'mixed' && !selectedStep?.allowNonInteractive);
  const canFinishSession = selectedStep?.state === 'running' && selectedStep.terminalSessionId && stepIsInteractive;

  // Group assets by step
  const assetsByStep = useMemo(() => {
    const map: Record<string, WorkflowRunAsset[]> = {};
    for (const a of assets) {
      const key = a.stepName ?? 'Unknown Step';
      (map[key] ??= []).push(a);
    }
    return map;
  }, [assets]);

  // ── Render ─────────────────────────────────────

  const renderStepItem = (step: StepRun) => {
    const isSelected = step.id === selectedStepId;
    const color = STATE_COLORS[step.state] ?? 'gray';

    return (
      <Box key={step.id}>
        <div
          className={`${classes.stepItem} ${isSelected ? classes.stepItemActive : ''}`}
          style={{ borderLeftColor: `var(--mantine-color-${color}-6)` }}
          onClick={() => setSelectedStepId(step.id)}
        >
          <Group gap="sm" wrap="nowrap">
            <div className={classes.stepIcon} style={{ backgroundColor: `var(--mantine-color-${color}-6)` }}>
              {stepIcon(step.state)}
            </div>
            <Box style={{ flex: 1, minWidth: 0 }}>
              <Group gap="xs" wrap="nowrap">
                <Text size="sm" fw={500} truncate>
                  {step.stepName ?? `Step ${step.stepPosition}`}
                </Text>
                <Badge
                  size="xs"
                  color={color}
                  variant="outline"
                  className={step.state === 'running' ? classes.pulse : undefined}
                >
                  {step.state}
                </Badge>
                {(step.pastFailures?.length ?? 0) > 0 && (
                  <Tooltip label={`${step.pastFailures!.length} past failure(s)`}>
                    <Badge size="xs" color="red" variant="filled" style={{ minWidth: 18, padding: '0 4px' }}>
                      {step.pastFailures!.length}
                    </Badge>
                  </Tooltip>
                )}
              </Group>
              {step.state === 'running' && step.startedAt ? (
                <LiveDuration startedAt={step.startedAt} />
              ) : step.startedAt ? (
                <Text size="xs" c="dimmed" ff="monospace">
                  {formatDuration(step.startedAt, step.completedAt)}
                </Text>
              ) : null}
              {step.state === 'pending' && step.dependsOnNames.length > 0 && (
                <Text size="xs" c="dimmed">
                  waits for {step.dependsOnNames.join(', ')}
                </Text>
              )}
            </Box>
            {step.terminalSessionId && (
              <Tooltip label={`Open session #${step.terminalSessionId}`}>
                <ActionIcon
                  variant="subtle"
                  size="xs"
                  onClick={(e: React.MouseEvent) => {
                    e.stopPropagation();
                    router.visit(`${basePath}/sessions/${step.terminalSessionId}`);
                  }}
                >
                  <IconChevronRight size={14} />
                </ActionIcon>
              </Tooltip>
            )}
          </Group>

          {step.subStepRuns.length > 0 && (
            <Group gap={4} mt={6} ml={36} wrap="wrap">
              {step.subStepRuns.map((ss) => (
                <Badge
                  key={ss.id}
                  size="xs"
                  color={STATE_COLORS[ss.state] ?? 'gray'}
                  variant={ss.state === 'completed' ? 'filled' : ss.state === 'in_progress' ? 'light' : 'outline'}
                  className={ss.state === 'in_progress' ? classes.pulse : undefined}
                >
                  {subStepLabel(ss, `#${ss.id}`)}
                </Badge>
              ))}
            </Group>
          )}

          {step.errorMessage && (
            <Text size="xs" c="red" mt={4} ml={36} lineClamp={2}>
              {step.errorMessage}
            </Text>
          )}
        </div>
      </Box>
    );
  };

  const [termLoaded, setTermLoaded] = useState(false);

  // Reset terminal loaded state when selected step changes
  useEffect(() => {
    setTermLoaded(false);
  }, [selectedStepId]);

  const sessionState = selectedStep?.terminalSessionState;
  const sessionReady = sessionState === 'ready';
  const sessionStarting = sessionState === 'not_started' || sessionState === 'running';
  const sessionFinished = sessionState === 'finished' || sessionState === 'failed';
  const hasTerminal = selectedStep?.terminalUrl != null && sessionReady;

  const renderStepDetail = () => {
    if (!selectedStep) {
      return (
        <div className={classes.detailEmpty}>
          <Stack align="center" gap="sm">
            <Text size="lg" c="dimmed">
              {sortedSteps.length === 0 ? 'No steps yet' : 'Select a step'}
            </Text>
          </Stack>
        </div>
      );
    }

    const color = STATE_COLORS[selectedStep.state] ?? 'gray';
    const stepIsRunning = selectedStep.state === 'running';

    return (
      <>
        {/* Parallel active steps tabs — only when multiple steps are active */}
        {activeSteps.length > 1 && (
          <div className={classes.parallelTabs}>
            <ScrollArea type="never" offsetScrollbars={false}>
              <Group gap={0} wrap="nowrap">
                {activeSteps.map((as) => {
                  const isCurrent = as.id === selectedStepId;
                  const asColor = STATE_COLORS[as.state] ?? 'gray';
                  return (
                    <button
                      key={as.id}
                      type="button"
                      className={`${classes.parallelTab} ${isCurrent ? classes.parallelTabActive : ''}`}
                      onClick={() => setSelectedStepId(as.id)}
                    >
                      <Group gap={6} wrap="nowrap">
                        <div className={classes.liveDot} />
                        <Text size="xs" fw={isCurrent ? 600 : 400} truncate>
                          {as.stepName ?? `Step ${as.stepPosition}`}
                        </Text>
                        <Badge size="xs" color={asColor} variant="outline" className={classes.pulse}>
                          {as.state}
                        </Badge>
                        {as.startedAt && <LiveDuration startedAt={as.startedAt} />}
                      </Group>
                    </button>
                  );
                })}
              </Group>
            </ScrollArea>
          </div>
        )}

        {/* Step info bar */}
        <div className={classes.stepInfoBar}>
          <Group justify="space-between" wrap="nowrap">
            <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
              <Text fw={600} size="sm" truncate>
                {selectedStep.stepName ?? `Step ${selectedStep.stepPosition}`}
              </Text>
              <Badge color={color} size="sm" variant="light" className={stepIsRunning ? classes.pulse : undefined}>
                {selectedStep.state}
              </Badge>
              {stepIsRunning && selectedStep.startedAt && (
                <Group gap={6} wrap="nowrap">
                  <div className={classes.liveDot} />
                  <LiveDuration startedAt={selectedStep.startedAt} />
                </Group>
              )}
              {!stepIsRunning && selectedStep.startedAt && (
                <Text size="xs" c="dimmed" ff="monospace">
                  {formatDuration(selectedStep.startedAt, selectedStep.completedAt)}
                </Text>
              )}
            </Group>
            <Group gap="xs" wrap="nowrap" />
          </Group>

          {/* Dependency info for pending steps */}
          {selectedStep.dependsOnNames.length > 0 && selectedStep.state === 'pending' && (
            <Group gap={4} mt={4}>
              <Text size="xs" c="dimmed">
                Waiting for:
              </Text>
              {selectedStep.dependsOnNames.map((name) => (
                <Badge key={name} size="xs" variant="outline" color="yellow">
                  {name}
                </Badge>
              ))}
            </Group>
          )}
        </div>

        {/* Terminal / IDE area for running steps */}
        {hasTerminal ? (
          <div className={classes.terminalArea}>
            {!termLoaded && (
              <div className={classes.terminalLoading}>
                <Loader size="md" />
                <Text size="sm" c="dimmed">
                  Connecting to terminal...
                </Text>
              </div>
            )}
            <iframe
              key={selectedStep.terminalUrl}
              src={selectedStep.terminalUrl!}
              title="Terminal"
              className={classes.terminalIframe}
              onLoad={() => setTermLoaded(true)}
            />
          </div>
        ) : sessionStarting && stepIsRunning ? (
          <div className={classes.terminalArea}>
            <div className={classes.terminalLoading}>
              <Loader size="md" />
              <Text size="sm" c="dimmed">
                Session starting...
              </Text>
              <Badge size="sm" variant="outline" color="blue">
                {sessionState}
              </Badge>
            </div>
          </div>
        ) : (
          <div className={classes.detailContent}>
            <Stack gap="lg">
              {/* Session finished banner */}
              {sessionFinished && selectedStep.terminalSessionId && (
                <Card withBorder p="sm" bg="var(--mantine-color-dark-6)">
                  <Group justify="space-between">
                    <Group gap="sm">
                      <IconTerminal2 size={18} style={{ opacity: 0.5 }} />
                      <Text size="sm" fw={500}>
                        Session #{selectedStep.terminalSessionId} finished
                      </Text>
                      <Badge size="xs" color={sessionState === 'failed' ? 'red' : 'green'} variant="outline">
                        {sessionState}
                      </Badge>
                    </Group>
                    <Button
                      variant="subtle"
                      size="xs"
                      rightSection={<IconChevronRight size={14} />}
                      onClick={() => router.visit(`${basePath}/sessions/${selectedStep.terminalSessionId}`)}
                    >
                      View Session
                    </Button>
                  </Group>
                </Card>
              )}

              {/* Note */}
              {selectedStep.stepNote && (
                <Box>
                  <Text size="xs" fw={600} c="dimmed" className={classes.sectionLabel} mb={4}>
                    Note
                  </Text>
                  <Text size="sm" style={{ fontStyle: 'italic', whiteSpace: 'pre-wrap' }}>
                    {selectedStep.stepNote}
                  </Text>
                </Box>
              )}

              {/* Sub-steps detail */}
              {selectedStep.subStepRuns.length > 0 && (
                <Box>
                  <Text size="xs" fw={600} c="dimmed" className={classes.sectionLabel} mb={8}>
                    Sub-steps ({selectedStep.subStepRuns.filter((s) => s.state === 'completed').length}/
                    {selectedStep.subStepRuns.length})
                  </Text>
                  <Stack gap={6}>
                    {selectedStep.subStepRuns.map((ss) => (
                      <div key={ss.id} className={classes.subStepRow}>
                        <div
                          className={classes.subStepDot}
                          style={{ backgroundColor: `var(--mantine-color-${STATE_COLORS[ss.state] ?? 'gray'}-6)` }}
                        >
                          {ss.state === 'completed' ? '✓' : ss.state === 'in_progress' ? '●' : '·'}
                        </div>
                        <Text size="sm" style={{ flex: 1 }}>
                          {subStepLabel(ss, `Sub-step #${ss.id}`)}
                        </Text>
                        {ss.startedAt && (
                          <Text size="xs" c="dimmed" ff="monospace">
                            {formatDuration(ss.startedAt, ss.completedAt)}
                          </Text>
                        )}
                      </div>
                    ))}
                  </Stack>
                </Box>
              )}

              {/* Past failures */}
              {(selectedStep.pastFailures?.length ?? 0) > 0 && (
                <Box>
                  <Text size="xs" fw={600} c="red" className={classes.sectionLabel} mb={4}>
                    Past Failures ({selectedStep.pastFailures!.length})
                  </Text>
                  <Stack gap={4}>
                    {selectedStep.pastFailures!.map((f, i) => (
                      <Text key={i} size="xs" c="red">
                        {f.errorMessage ?? 'Unknown error'}
                      </Text>
                    ))}
                  </Stack>
                </Box>
              )}

              {/* Error */}
              {selectedStep.errorMessage && selectedStep.state === 'failed' && (
                <Card withBorder p="sm" bg="var(--mantine-color-red-light)">
                  <Text size="xs" fw={600} c="red" mb={4}>
                    Step Failed
                  </Text>
                  <Text size="sm" c="red" style={{ whiteSpace: 'pre-wrap' }}>
                    {selectedStep.errorMessage}
                  </Text>
                </Card>
              )}

              {/* Waiting state */}
              {selectedStep.state === 'pending' && (
                <Stack align="center" gap="sm" py="xl">
                  <IconTerminal2 size={32} style={{ opacity: 0.3 }} />
                  <Text size="sm" c="dimmed">
                    Waiting to start...
                  </Text>
                </Stack>
              )}
            </Stack>
          </div>
        )}

        {/* Action bar */}
        {isActive &&
          (canFinishSession || selectedStep.state === 'waiting_input' || selectedStep.state === 'failed') && (
            <div className={classes.actionBar}>
              <Group gap="sm">
                {canFinishSession && (
                  <Button
                    color="teal"
                    size="xs"
                    onClick={() => handleFinishSession(selectedStep.terminalSessionId!)}
                    loading={actionLoading}
                  >
                    Finish Agent Session
                  </Button>
                )}
                {selectedStep.state === 'waiting_input' && (
                  <>
                    <Button size="xs" onClick={handleApprove} loading={actionLoading}>
                      Approve & Continue
                    </Button>
                    <Button size="xs" variant="outline" onClick={() => setSkipOpen(true)}>
                      Skip
                    </Button>
                    <Button size="xs" variant="outline" color="yellow" onClick={handleRetry} loading={actionLoading}>
                      Retry
                    </Button>
                  </>
                )}
                {selectedStep.state === 'failed' && (
                  <Button size="xs" variant="outline" color="yellow" onClick={handleRetry} loading={actionLoading}>
                    Retry Step
                  </Button>
                )}
              </Group>
            </div>
          )}
      </>
    );
  };

  const renderAssetsView = () => {
    if (assets.length === 0) {
      return (
        <div className={classes.detailEmpty}>
          <Text c="dimmed">No workflow assets</Text>
        </div>
      );
    }

    return (
      <div className={classes.detailContent}>
        <Stack gap="lg">
          <Group justify="flex-end">
            <Button
              size="xs"
              variant="outline"
              leftSection={<IconUpload size={14} />}
              onClick={() => setPromoteOpen({ assetId: null, name: 'All Artifacts' })}
            >
              Promote All to Project
            </Button>
          </Group>
          {Object.entries(assetsByStep).map(([stepName, stepAssets]) => (
            <Box key={stepName}>
              <Group gap="sm" mb="xs">
                <Text size="sm" fw={600}>
                  {stepName}
                </Text>
                <Badge size="xs" variant="outline">
                  {stepAssets.length} file(s)
                </Badge>
              </Group>
              <div className={classes.assetsGrid}>
                {stepAssets.map((a) => (
                  <div key={a.id} className={classes.assetCard}>
                    <Box style={{ minWidth: 0 }}>
                      <Text size="sm" fw={500} truncate>
                        {a.name}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {a.contentType ?? ''}
                        {a.fileSize ? ` · ${formatFileSize(a.fileSize)}` : ''}
                      </Text>
                    </Box>
                    <Group gap="xs" wrap="nowrap">
                      {a.downloadUrl && (
                        <Button
                          size="xs"
                          variant="light"
                          leftSection={<IconDownload size={12} />}
                          component="a"
                          href={a.downloadUrl}
                          target="_blank"
                        >
                          Download
                        </Button>
                      )}
                      <Button
                        size="xs"
                        variant="subtle"
                        leftSection={<IconUpload size={12} />}
                        onClick={() => setPromoteOpen({ assetId: a.id, name: a.name })}
                      >
                        Promote
                      </Button>
                    </Group>
                  </div>
                ))}
              </div>
            </Box>
          ))}
        </Stack>
      </div>
    );
  };

  return (
    <>
      <Head title={`Run #${run.id} — ${project.name}`} />
      <div className={classes.root}>
        {/* ── Header ─────────────────────────────── */}
        <div className={classes.header}>
          <div className={classes.headerLeft}>
            <ActionIcon variant="subtle" size="sm" onClick={() => router.visit(`${basePath}/workflow_runs`)}>
              <IconArrowLeft size={16} />
            </ActionIcon>
            <Text fw={600} size="sm">
              {run.workflowName}
            </Text>
            <Badge
              color={STATE_COLORS[run.state] ?? 'gray'}
              size="sm"
              variant={isActive ? 'filled' : 'outline'}
              className={run.state === 'running' ? classes.pulse : undefined}
            >
              {run.state}
            </Badge>
            <Text size="xs" c="dimmed" ff="monospace">
              #{run.id}
            </Text>
            {isActive && (
              <Group gap={6}>
                <div className={classes.liveDot} />
                {run.startedAt && <LiveDuration startedAt={run.startedAt} />}
              </Group>
            )}
          </div>
          <div className={classes.headerRight}>
            <div className={classes.headerMeta}>
              <Text size="xs" c="dimmed" ff="monospace">
                {run.stepsCompleted}/{run.stepsTotal} steps
              </Text>
              {!isActive && run.startedAt && (
                <Text size="xs" c="dimmed" ff="monospace">
                  {formatDuration(run.startedAt, run.completedAt)}
                </Text>
              )}
              {run.costCents > 0 && (
                <Text size="xs" c="green" ff="monospace" fw={600}>
                  {formatCost(run.costCents)}
                </Text>
              )}
              {run.mode && (
                <Badge size="xs" variant="outline" color="gray">
                  {MODE_LABELS[run.mode] ?? run.mode}
                </Badge>
              )}
            </div>
            {!isTerminal && (
              <Button
                size="xs"
                variant="outline"
                color="red"
                onClick={handleCancel}
                loading={actionLoading}
                leftSection={<IconPlayerStop size={14} />}
              >
                Cancel
              </Button>
            )}
          </div>
        </div>

        {/* ── Progress Bar ───────────────────────── */}
        {isActive && run.stepsTotal > 0 && (
          <Progress value={progressPct} size="xs" color={run.state === 'running' ? 'blue' : 'yellow'} radius={0} />
        )}

        {/* ── Content ────────────────────────────── */}
        <div className={classes.content}>
          {/* Steps sidebar */}
          <div className={classes.stepsSidebar}>
            <div className={classes.stepsHeader}>
              <Group justify="space-between">
                <Group gap="xs">
                  <Button size="xs" variant={view === 'steps' ? 'filled' : 'subtle'} onClick={() => setView('steps')}>
                    Steps
                  </Button>
                  <Button
                    size="xs"
                    variant={view === 'assets' ? 'filled' : 'subtle'}
                    onClick={() => setView('assets')}
                    disabled={isActive && assets.length === 0}
                  >
                    Assets{assets.length > 0 ? ` (${assets.length})` : ''}
                  </Button>
                </Group>
              </Group>
            </div>
            <ScrollArea className={classes.stepsList}>
              {sortedSteps.length === 0 ? (
                <Text c="dimmed" ta="center" py="xl" size="sm">
                  No steps
                </Text>
              ) : hasDag ? (
                <Stack gap={0}>
                  {waves.map((wave, wi) => (
                    <Box key={wi}>
                      {wi > 0 && (
                        <div className={classes.waveConnector}>
                          <IconArrowRight size={12} style={{ opacity: 0.4 }} />
                          <Text size="xs" c="dimmed" truncate>
                            {wave.label}
                          </Text>
                        </div>
                      )}
                      {wave.steps.length > 1 && (
                        <div className={classes.parallelLabel}>
                          <Badge size="xs" variant="outline" color="blue">
                            {wave.steps.length} parallel
                          </Badge>
                        </div>
                      )}
                      {wave.steps.map((step) => renderStepItem(step))}
                    </Box>
                  ))}
                </Stack>
              ) : (
                <Stack gap={0}>{sortedSteps.map((step) => renderStepItem(step))}</Stack>
              )}
            </ScrollArea>
          </div>

          {/* Detail panel */}
          <div className={classes.detailPanel}>{view === 'steps' ? renderStepDetail() : renderAssetsView()}</div>
        </div>

        {/* ── Status Bar ─────────────────────────── */}
        <div className={classes.statusBar}>
          <Group gap="lg" justify="center">
            {run.agentType && (
              <Text size="xs" c="dimmed">
                Agent:{' '}
                <Text span fw={500}>
                  {run.agentType}
                </Text>
              </Text>
            )}
            {run.userName && (
              <Text size="xs" c="dimmed">
                User:{' '}
                <Text span fw={500}>
                  {run.userName}
                </Text>
              </Text>
            )}
            <Text size="xs" c="dimmed">
              Created:{' '}
              <Text span fw={500}>
                {new Date(run.createdAt).toLocaleString()}
              </Text>
            </Text>
          </Group>
        </div>
      </div>

      {/* ── Skip Modal ───────────────────────────── */}
      <Modal opened={skipOpen} onClose={() => setSkipOpen(false)} title="Skip Step" centered size="sm">
        <Textarea
          label="Reason (optional)"
          value={skipReason}
          onChange={(e) => setSkipReason(e.currentTarget.value)}
          autosize
          minRows={3}
          mb="md"
        />
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setSkipOpen(false)}>
            Cancel
          </Button>
          <Button onClick={handleSkip} loading={actionLoading}>
            Skip Step
          </Button>
        </Group>
      </Modal>

      {/* ── Promote Modal ────────────────────────── */}
      <Modal
        opened={!!promoteOpen}
        onClose={() => setPromoteOpen(null)}
        title={promoteOpen?.assetId ? `Promote "${promoteOpen.name}"` : 'Promote All Artifacts'}
        centered
        size="sm"
      >
        <Text size="sm" mb="md">
          This will create project-level assets from workflow artifacts.
        </Text>
        <TextInput
          label="Folder (optional)"
          placeholder="Leave empty for root"
          value={promoteFolder}
          onChange={(e) => setPromoteFolder(e.currentTarget.value)}
          mb="md"
        />
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setPromoteOpen(null)}>
            Cancel
          </Button>
          <Button onClick={handlePromote} loading={promoteLoading}>
            Promote
          </Button>
        </Group>
      </Modal>
    </>
  );
};

setPageLayout(WorkflowRunShowPage, persistentProjectLayout);

export default WorkflowRunShowPage;
