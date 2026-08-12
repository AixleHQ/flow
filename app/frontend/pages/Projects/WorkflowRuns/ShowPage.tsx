import { Head, router, usePage } from '@inertiajs/react';
import { Alert, Anchor, Button, Group, Loader, Modal, Stack, Text, Textarea, TextInput } from '@mantine/core';
import { IconAlertTriangle, IconDownload, IconFile, IconPlayerStop, IconUpload } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useMemo, useState } from 'react';

import type StepRun from 'types/generated/StepRun';
import type WorkflowRun from 'types/generated/WorkflowRun';
import type WorkflowRunAsset from 'types/generated/WorkflowRunAsset';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { costColor, formatCost, formatDuration, formatFileSize, formatTokens } from 'shared/lib/sessionFormat';
import {
  exportAllApiV1ProjectWorkflowRunWorkflowRunAssetsPath,
  exportApiV1ProjectWorkflowRunWorkflowRunAssetPath,
  finishApiV1TerminalSessionPath,
} from 'shared/routes';
import { ConsoleFrame, DetailHeader, SessionCard, TabBar, type SessionCardData } from 'shared/ui/sessions';

import { persistentProjectLayoutNoPadding, setPageLayout } from '../ProjectLayout';

import classes from './ShowPage.module.css';

// ── Types ──────────────────────────────────────────

interface Props {
  project: { id: number; name: string };
  run: WorkflowRun;
  assets: WorkflowRunAsset[];
  cableStream: string;
}

const ACTIVE_STATES = new Set(['pending', 'running', 'paused', 'waiting_input']);

const RUN_STATE_LABELS: Record<string, string> = {
  completed: 'Completed',
  running: 'Running',
  paused: 'Paused',
  failed: 'Failed',
  cancelled: 'Cancelled',
  pending: 'Pending',
};

/** Sessions inside a run are numbered; their checklist items are the steps. */
function toCardData(stepRun: StepRun, index: number): SessionCardData {
  return {
    id: stepRun.id,
    ordinal: `Session ${index + 1}`,
    title: stepRun.stepName ?? `Step ${stepRun.stepPosition ?? index + 1}`,
    state: stepRun.state,
    terminalSessionId: stepRun.terminalSessionId,
    agentType: stepRun.agentType ?? null,
    totalTokens: stepRun.totalTokens,
    costCents: stepRun.costCents,
    startedAt: stepRun.startedAt,
    completedAt: stepRun.completedAt,
    excerpt: stepRun.stepNote ?? stepRun.initialPrompt ?? null,
    prompt: stepRun.initialPrompt ?? null,
    note: stepRun.stepNote,
    errorMessage: stepRun.errorMessage,
    steps: stepRun.subStepRuns.map((ss) => ({
      id: ss.id,
      label: ss.subStepName ?? `Step #${ss.id}`,
      state: ss.state ?? 'pending',
    })),
  };
}

const WorkflowRunShowPage = () => {
  const { project, run, assets, cableStream } = usePage<{ props: Props }>().props as unknown as Props;

  const isActive = ACTIVE_STATES.has(run.state);
  const isTerminal = run.state === 'completed' || run.state === 'failed' || run.state === 'cancelled';

  const [tab, setTab] = useState<'sessions' | 'assets'>('sessions');
  const [skipOpen, setSkipOpen] = useState(false);
  const [skipReason, setSkipReason] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [promoteOpen, setPromoteOpen] = useState<{ assetId: number | null; name: string } | null>(null);
  const [promoteFolder, setPromoteFolder] = useState('');
  const [promoteLoading, setPromoteLoading] = useState(false);
  const [termLoaded, setTermLoaded] = useState(false);

  useInertiaCableStream(cableStream, { only: ['run', 'assets'], enabled: !isTerminal });

  const basePath = `/company/projects/${project.id}`;
  const workflowName = run.workflowName ?? 'Workflow run';
  const runPath = `${basePath}/workflow_runs/${run.id}`;

  const sortedSteps = useMemo(
    () => [...run.stepRuns].sort((a, b) => (a.stepPosition ?? 0) - (b.stepPosition ?? 0)),
    [run.stepRuns],
  );

  // The session whose console the running view shows: whatever is producing
  // output right now, or waiting on the person looking at the screen.
  const liveStep = useMemo(
    () => sortedSteps.find((s) => s.state === 'running' || s.state === 'waiting_input') ?? null,
    [sortedSteps],
  );

  useEffect(() => {
    setTermLoaded(false);
  }, [liveStep?.terminalUrl]);

  const failedStep = useMemo(() => sortedSteps.find((s) => s.state === 'failed') ?? null, [sortedSteps]);

  const post = useCallback((path: string, data: Parameters<typeof router.post>[1] = {}) => {
    setActionLoading(true);
    router.post(path, data, { preserveScroll: true, onFinish: () => setActionLoading(false) });
  }, []);

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

  const stepIsInteractive = run.mode === 'interactive' || (run.mode === 'mixed' && !liveStep?.allowNonInteractive);
  const canFinishSession = liveStep?.state === 'running' && !!liveStep.terminalSessionId && stepIsInteractive;

  // Failed runs swap "Started" for where they stopped — the one fact you open a
  // failed run to learn.
  const stats = [
    { label: 'Sessions', value: `${run.stepsCompleted}/${run.stepsTotal}` },
    { label: 'Duration', value: formatDuration(run.startedAt, run.completedAt, run.state) },
    { label: 'Cost', value: formatCost(run.costCents), color: costColor(run.costCents) },
    run.state === 'failed' && failedStep
      ? {
          label: 'Failed at',
          value: `${failedStep.stepName ?? `Step ${failedStep.stepPosition}`}`,
          sans: true,
        }
      : {
          label: 'Started',
          value: formatDistanceToNow(new Date(run.startedAt ?? run.createdAt), { addSuffix: true }),
          sans: true,
        },
  ];

  const sessionCards = sortedSteps.map((step, i) => (
    <SessionCard
      key={step.id}
      data={toCardData(step, i)}
      live={isActive && step.id === liveStep?.id}
      defaultOpen={isActive ? step.id === liveStep?.id : step.state === 'failed'}
      sessionHref={step.terminalSessionId ? `${basePath}/sessions/${step.terminalSessionId}` : null}
    />
  ));

  const renderConsole = () => {
    if (!liveStep) return null;
    const label = `Session ${sortedSteps.indexOf(liveStep) + 1} · ${liveStep.stepName ?? 'Step'}`;

    return (
      <ConsoleFrame className={classes.console} label={label} live>
        {liveStep.terminalUrl ? (
          <>
            {!termLoaded && (
              <div className={classes.terminalLoading}>
                <Loader size="md" />
                <Text size="sm" c="dimmed">
                  Connecting to terminal…
                </Text>
              </div>
            )}
            <iframe
              key={liveStep.terminalUrl}
              src={liveStep.terminalUrl}
              title="Terminal"
              allow="clipboard-read; clipboard-write"
              onLoad={() => setTermLoaded(true)}
            />
          </>
        ) : (
          <div className={classes.terminalLoading}>
            <Loader size="md" />
            <Text size="sm" c="dimmed">
              Session starting…
            </Text>
          </div>
        )}
      </ConsoleFrame>
    );
  };

  const renderAssets = () => {
    if (assets.length === 0) {
      return <div className={classes.empty}>No assets yet — they&apos;ll appear here as sessions produce them.</div>;
    }

    return (
      <>
        <div className={classes.paneHead}>
          <span className={classes.paneCount}>
            {assets.length} {assets.length === 1 ? 'file' : 'files'}
          </span>
          <Button
            size="xs"
            variant="light"
            leftSection={<IconUpload size={14} />}
            onClick={() => setPromoteOpen({ assetId: null, name: 'All artifacts' })}
          >
            Promote all to project
          </Button>
        </div>
        {assets.map((asset) => (
          <div className={classes.assetRow} key={asset.id}>
            <IconFile size={17} color="var(--app-text-tertiary)" />
            <div className={classes.assetMeta}>
              <div className={classes.assetName}>{asset.name}</div>
              <div className={classes.assetSub}>
                {asset.contentType ?? 'unknown type'}
                {asset.fileSize ? ` · ${formatFileSize(asset.fileSize)}` : ''}
                {asset.stepName ? ` · ${asset.stepName}` : ''}
              </div>
            </div>
            <div className={classes.assetActions}>
              {asset.downloadUrl && (
                <Button
                  size="xs"
                  variant="default"
                  component="a"
                  href={asset.downloadUrl}
                  target="_blank"
                  leftSection={<IconDownload size={12} />}
                >
                  Download
                </Button>
              )}
              <Button
                size="xs"
                variant="default"
                onClick={() => setPromoteOpen({ assetId: asset.id, name: asset.name })}
              >
                Promote
              </Button>
            </div>
          </div>
        ))}
      </>
    );
  };

  return (
    <>
      <Head title={`Run #${run.id} — ${project.name}`} />
      <div className={classes.root}>
        <DetailHeader
          crumbs={[
            { label: 'Sessions & Runs', href: `${basePath}/sessions` },
            { label: `${workflowName} · Run #${run.id}` },
          ]}
          title={workflowName}
          state={run.state}
          statusLabel={RUN_STATE_LABELS[run.state]}
          identifier={`Run #${run.id}`}
          description={run.workflowDescription}
          agentType={run.agentType}
          userName={run.userName}
          mode={run.mode}
          stats={stats}
          formatTokenValue={formatTokens}
          actions={
            !isTerminal && (
              <Button
                variant="default"
                leftSection={<IconPlayerStop size={14} />}
                loading={actionLoading}
                onClick={() => post(`${runPath}/cancel`)}
              >
                Cancel run
              </Button>
            )
          }
          tabs={
            <TabBar
              inline
              aria-label="Run detail"
              value={tab}
              onChange={setTab}
              tabs={[
                { value: 'sessions', label: 'Sessions', count: run.stepsTotal },
                { value: 'assets', label: 'Assets', count: assets.length },
              ]}
            />
          }
        />

        {run.failureReason === 'quota_exceeded' && (
          <Alert
            icon={<IconAlertTriangle size={16} />}
            color="orange"
            title="Workflow stopped: account ran out of credits"
            radius={0}
          >
            <Stack gap="xs">
              <Text size="sm">
                <strong>{run.failedAccountName ?? 'A connected account'}</strong> hit its quota limit. Top up the
                account and re-run, or switch to a different connected account.
              </Text>
              <Group gap="xs">
                <Button
                  size="xs"
                  variant="light"
                  color="orange"
                  loading={actionLoading}
                  onClick={() =>
                    post(`${basePath}/workflow_runs`, {
                      workflowRun: { workflowId: run.workflowId, mode: run.mode },
                    })
                  }
                >
                  Re-run workflow
                </Button>
                <Anchor size="xs" href="/profile">
                  Manage accounts
                </Anchor>
              </Group>
            </Stack>
          </Alert>
        )}

        <div
          className={isActive && tab === 'sessions' ? `${classes.body} ${classes.bodyWide}` : classes.body}
          role="tabpanel"
        >
          {tab === 'assets' ? (
            renderAssets()
          ) : sortedSteps.length === 0 ? (
            <div className={classes.empty}>This run has no sessions yet.</div>
          ) : (
            <>
              {/* The one human decision in a run gets the only solid button on
                  the surface; the escape hatches stay secondary. */}
              {isActive && liveStep && (liveStep.state === 'waiting_input' || canFinishSession) && (
                <div className={classes.actionBar}>
                  <span className={classes.actionBarText}>
                    {liveStep.state === 'waiting_input'
                      ? `"${liveStep.stepName ?? 'This session'}" is waiting for your approval.`
                      : `"${liveStep.stepName ?? 'This session'}" is running interactively.`}
                  </span>
                  {liveStep.state === 'waiting_input' && (
                    <>
                      <Button loading={actionLoading} onClick={() => post(`${runPath}/approve_step`)}>
                        Approve &amp; continue
                      </Button>
                      <Button variant="subtle" color="gray" onClick={() => setSkipOpen(true)}>
                        Skip
                      </Button>
                      <Button
                        variant="subtle"
                        color="gray"
                        loading={actionLoading}
                        onClick={() => post(`${runPath}/retry_step`)}
                      >
                        Retry
                      </Button>
                    </>
                  )}
                  {canFinishSession && liveStep.state !== 'waiting_input' && (
                    <Button loading={actionLoading} onClick={() => handleFinishSession(liveStep.terminalSessionId!)}>
                      Finish session
                    </Button>
                  )}
                </div>
              )}

              {failedStep && !isActive && (
                <div className={classes.actionBar}>
                  <span className={classes.actionBarText}>
                    &quot;{failedStep.stepName ?? 'A session'}&quot; failed.
                  </span>
                  <Button variant="default" loading={actionLoading} onClick={() => post(`${runPath}/retry_step`)}>
                    Retry session
                  </Button>
                </div>
              )}

              {isActive && liveStep ? (
                <div className={classes.split}>
                  <div className={classes.list}>{sessionCards}</div>
                  {renderConsole()}
                </div>
              ) : (
                <div className={classes.list}>{sessionCards}</div>
              )}
            </>
          )}
        </div>
      </div>

      <Modal opened={skipOpen} onClose={() => setSkipOpen(false)} title="Skip session" centered size="sm">
        <Textarea
          label="Reason (optional)"
          value={skipReason}
          onChange={(e) => setSkipReason(e.currentTarget.value)}
          autosize
          minRows={3}
          mb="md"
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={() => setSkipOpen(false)}>
            Cancel
          </Button>
          <Button
            loading={actionLoading}
            onClick={() => {
              post(`${runPath}/skip_step`, { reason: skipReason || null });
              setSkipOpen(false);
              setSkipReason('');
            }}
          >
            Skip session
          </Button>
        </Group>
      </Modal>

      <Modal
        opened={!!promoteOpen}
        onClose={() => setPromoteOpen(null)}
        title={promoteOpen?.assetId ? `Promote "${promoteOpen.name}"` : 'Promote all artifacts'}
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
          <Button variant="default" onClick={() => setPromoteOpen(null)}>
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

setPageLayout(WorkflowRunShowPage, persistentProjectLayoutNoPadding);

export default WorkflowRunShowPage;
