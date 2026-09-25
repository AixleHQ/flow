import { router } from '@inertiajs/react';
import { ActionIcon, Badge, Box, Button, Center, Group, Loader, Stack, Text, Tooltip } from '@mantine/core';
import { useClipboard, useHotkeys } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import {
  IconCheck,
  IconChevronLeft,
  IconChevronRight,
  IconCopy,
  IconEye,
  IconMaximize,
  IconMinimize,
  IconPlus,
  IconSquareCheck,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Group as PanelGroup, Panel, Separator as PanelResizeHandle, useDefaultLayout } from 'react-resizable-panels';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiMutate } from 'shared/lib/apiFetch';
import { useElapsedTimer } from 'shared/lib/hooks/useElapsedTimer';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { isWaitingForSlot, launchWaitMessage } from 'shared/lib/launchStatus';
import { costColor, formatCost, formatDuration, formatTokens, shortModelName } from 'shared/lib/sessionFormat';
import { terminalPageUrl } from 'shared/lib/terminalPageUrl';
import { finishApiV1TerminalSessionPath } from 'shared/routes';
import { ContainerFrame } from 'shared/ui/ContainerFrame';
import { ConsoleFrame, DetailHeader, StatusTag, type Crumb, type HeaderStat } from 'shared/ui/sessions';

import classes from './SessionShowContent.module.css';
import { SessionTerminalReplay } from './SessionTerminalReplay';

/** Where a workflow-step session sits inside its run — null for a standalone. */
export interface SessionWorkflowContext {
  runId: number;
  runName: string | null;
  runPath: string;
  stepName: string | null;
  stepPosition: number | null;
  stepsTotal: number;
}

export interface SessionShowContext {
  backPath: string;
  /** Label of the list this session came from, for the breadcrumb. */
  backLabel?: string;
  // Optional: company-level session creation was removed, so the company
  // session view omits this and the "New Session" buttons are hidden.
  newSessionPath?: string;
  artifactsPath: string;
}

interface Props {
  session: TerminalSession;
  cableStream: string;
  context: SessionShowContext;
  workflowContext?: SessionWorkflowContext | null;
}

const SESSION_STATE_LABELS: Record<string, string> = {
  not_started: 'Pending',
  queued: 'Queued',
  cancelled: 'Cancelled',
  running: 'Starting',
  ready: 'Running',
  finishing: 'Finishing',
  finished: 'Finished',
  failed: 'Failed',
};

/** First line of the prompt — the session's own one-line description. */
function sessionTitle(s: TerminalSession, workflowContext?: SessionWorkflowContext | null): string {
  if (workflowContext?.stepName) return workflowContext.stepName;
  const firstLine = (s.initialPrompt ?? '').trim().split('\n')[0]?.trim();
  if (firstLine) return firstLine.length > 80 ? `${firstLine.slice(0, 80)}…` : firstLine;
  return 'Interactive session';
}

export function SessionShowContent({ session: s, cableStream, context: ctx, workflowContext = null }: Props) {
  const { canExecute } = useProjectPermissions();
  const isTerminal = ['finished', 'failed', 'cancelled'].includes(s.state);
  const isQueued = s.state === 'queued';
  const waitingForSlot = isWaitingForSlot(s.launchPhase);
  const isFinishing = s.state === 'finishing';
  const isReady = s.state === 'ready';
  const isActive = isReady || s.state === 'running';

  const [ideLoaded, setIdeLoaded] = useState(false);
  const [termLoaded, setTermLoaded] = useState(false);
  const [finishRequested, setFinishRequested] = useState(false);
  const [editorCollapsed, setEditorCollapsed] = useState(false);
  const [maximized, setMaximized] = useState(false);
  const frameRef = useRef<HTMLDivElement>(null);
  const clipboard = useClipboard({ timeout: 2000 });

  const now = useElapsedTimer(isActive);

  useInertiaCableStream(cableStream, { only: ['session'], enabled: !isTerminal });

  const ttydUrl = useMemo(
    () => terminalPageUrl({ terminalUrl: s.terminalUrl, websocketUrl: s.websocketUrl }),
    [s.terminalUrl, s.websocketUrl],
  );

  // Someone else's session, shared with this viewer. They get to watch: the
  // terminal renders behind a shield that swallows clicks (so the iframe never
  // takes focus and keystrokes go nowhere), the editor is not offered at all —
  // an overlay on VS Code is just a broken editor — and Finish is hidden,
  // because the API scopes that action to the owner anyway.
  //
  // This is presentation, not enforcement: ttyd runs writable and the viewer
  // has the route token, so opening it directly still yields a live shell.
  const isOwner = s.ownedByViewer;
  const hasIde = !!s.ideUrl && isOwner;
  // Full screen is for the agent's terminal alone; the editor comes back with
  // the split it had once the console is restored.
  const canShowEditor = hasIde && !editorCollapsed && !maximized;
  const canShowTerminal = !!ttydUrl;

  const exitMaximized = useCallback(() => {
    setMaximized(false);
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => {});
  }, []);

  const enterMaximized = useCallback(() => {
    setMaximized(true);
    // The fixed-position layout stays underneath as the fallback when the
    // browser refuses (no user activation, iframe without allowfullscreen).
    void frameRef.current?.requestFullscreen?.().catch(() => {});
  }, []);

  const toggleMaximized = useCallback(() => {
    if (maximized) exitMaximized();
    else enterMaximized();
  }, [maximized, enterMaximized, exitMaximized]);

  // The browser owns Esc while fullscreen and exits without a keydown reaching
  // the page; this is what brings the React state back in line.
  useEffect(() => {
    const onChange = () => {
      if (!document.fullscreenElement) setMaximized(false);
    };
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  const handleFinish = useCallback(async () => {
    // The finishing overlay lives outside the console frame, so it would not
    // be visible over a fullscreen frame.
    exitMaximized();
    setFinishRequested(true);
    if (await apiMutate(finishApiV1TerminalSessionPath(s.id), { method: 'POST' })) {
      router.reload({ onFinish: () => setFinishRequested(false) });
    } else {
      setFinishRequested(false);
    }
  }, [s.id, exitMaximized]);

  const handleCopyLink = useCallback(() => {
    clipboard.copy(window.location.href);
    notifications.show({ message: 'Session link copied', color: 'green', autoClose: 2000 });
  }, [clipboard]);

  const toggleEditor = useCallback(() => {
    if (hasIde) setEditorCollapsed((prev) => !prev);
  }, [hasIde]);

  // Keys typed inside the ttyd/VS Code iframes never reach this document, so
  // these only fire while focus is on the page itself — Esc in the CLI stays
  // the CLI's.
  useHotkeys([
    ['mod+b', toggleEditor],
    ['mod+shift+F', toggleMaximized],
  ]);

  // Capture phase: an open Mantine tooltip (the one on the button just
  // clicked) stops Escape's propagation, which would take two presses to exit.
  useEffect(() => {
    if (!maximized) return undefined;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMaximized(false);
    };
    window.addEventListener('keydown', onKeyDown, true);
    return () => window.removeEventListener('keydown', onKeyDown, true);
  }, [maximized]);

  const { defaultLayout: savedLayout, onLayoutChanged } = useDefaultLayout({
    id: 'session-panels',
    storage: typeof window !== 'undefined' ? localStorage : undefined,
  });

  // ── Header ───────────────────────────────────────

  const crumbs: Crumb[] = [{ label: ctx.backLabel ?? 'Sessions & Runs', href: ctx.backPath }];
  if (workflowContext) {
    crumbs.push({
      label: `${workflowContext.runName ?? 'Run'} · Run #${workflowContext.runId}`,
      href: workflowContext.runPath,
    });
  }
  crumbs.push({ label: `${sessionTitle(s, workflowContext)} #${s.id}` });

  const duration = formatDuration(s.startedAt, s.finishedAt, s.state, now);

  const stats: HeaderStat[] = [
    { label: 'Duration', value: duration },
    { label: 'Cost', value: formatCost(s.costCents), color: costColor(s.costCents) },
    { label: 'Total tokens', value: formatTokens(s.totalTokens) },
    {
      label: 'Models',
      sans: true,
      value:
        s.models.length > 0 ? (
          s.models.map((m) => (
            <Tooltip key={m} label={m} multiline maw={420}>
              <span>
                <StatusTag plain>{shortModelName(m)}</StatusTag>
              </span>
            </Tooltip>
          ))
        ) : (
          <Text size="sm" c="dimmed">
            —
          </Text>
        ),
    },
  ];

  const label = workflowContext
    ? `Step ${workflowContext.stepPosition ?? '?'} of ${workflowContext.stepsTotal} · Workflow step`
    : 'Standalone session';

  // Finish is owner-only at the API (`current_user.terminal_sessions`), so
  // offering it to a viewer would only produce a failed request.
  const canFinish = canExecute && isOwner && !isTerminal && !isFinishing;
  const finishLabel = isQueued ? (workflowContext ? 'Cancel workflow' : 'Cancel session') : 'Finish session';

  // Portalled popovers and notifications render under a fullscreen element, so
  // controls on the console bar keep their tooltip inside the frame and show
  // the copy confirmation on the button itself.
  const renderCopyLinkButton = (withinPortal = true) => (
    <Tooltip label={clipboard.copied ? 'Link copied' : 'Copy session link'} withinPortal={withinPortal}>
      <ActionIcon aria-label="Copy session link" variant="subtle" size="sm" onClick={handleCopyLink}>
        {clipboard.copied ? <IconCheck size={15} /> : <IconCopy size={15} />}
      </ActionIcon>
    </Tooltip>
  );

  const header = (
    <DetailHeader
      crumbs={crumbs}
      title={sessionTitle(s, workflowContext)}
      state={s.state}
      statusLabel={SESSION_STATE_LABELS[s.state]}
      identifier={`#${s.id}`}
      description={workflowContext ? null : s.initialPrompt}
      agentType={s.agentType}
      userName={s.userName}
      mode={s.mode}
      stats={stats}
      tokens={
        s.totalTokens > 0
          ? {
              inputTokens: s.inputTokens,
              outputTokens: s.outputTokens,
              cacheReadTokens: s.cacheReadTokens,
              cacheWriteTokens: s.cacheWriteTokens,
            }
          : null
      }
      formatTokenValue={formatTokens}
      actions={
        <>
          <Text size="sm" c="dimmed">
            {label}
          </Text>
          {!isOwner && (
            <Tooltip label={`${s.userName ?? 'Someone else'} is running this session — you can watch, not type`}>
              <Badge size="sm" variant="outline" leftSection={<IconEye size={11} />}>
                View only
              </Badge>
            </Tooltip>
          )}
          {renderCopyLinkButton()}
          {canFinish && (
            <Button leftSection={<IconSquareCheck size={15} />} onClick={handleFinish} loading={finishRequested}>
              {finishLabel}
            </Button>
          )}
          {canExecute && isTerminal && ctx.newSessionPath && (
            <Button
              variant="default"
              leftSection={<IconPlus size={14} />}
              onClick={() => router.visit(ctx.newSessionPath!)}
            >
              New session
            </Button>
          )}
        </>
      }
    />
  );

  // ── Workspace frame ──────────────────────────────

  const renderLoadingOverlay = (text: string) => (
    <div className={classes.loadingOverlay}>
      <Loader size="md" />
      <Text size="sm" c="dimmed">
        {text}
      </Text>
    </div>
  );

  const renderTerminalFrame = () => (
    <>
      {!termLoaded && renderLoadingOverlay('Connecting to terminal…')}
      {!isOwner && <div className={classes.viewOnlyShield} aria-label="Read-only view of another user's session" />}
      <ContainerFrame
        src={ttydUrl!}
        title="Terminal"
        allow="clipboard-read; clipboard-write"
        onLoad={() => setTermLoaded(true)}
      />
    </>
  );

  const renderWorkspace = () => {
    if (finishRequested || isFinishing) return null;

    if (!isReady || !canShowTerminal) {
      return (
        <Center className={classes.workspace}>
          <Stack align="center" gap="md">
            <Loader size="md" />
            <Text size="lg" fw={500}>
              {launchWaitMessage(s.launchPhase)}
            </Text>
            <StatusTag state={s.state}>{SESSION_STATE_LABELS[s.state]}</StatusTag>
            {waitingForSlot && (
              <Text size="sm" c="dimmed">
                Your session will start automatically when a slot frees up.
              </Text>
            )}
            {/* The launch's own reason for not being up — a refused preflight, a
                failed dispatch, a capacity refusal. Silence here is what made
                every launch problem look like an ordinary queue wait. */}
            {s.launchError && (
              <Text size="sm" c="red.6" ta="center" maw={480}>
                {s.launchError}
              </Text>
            )}
            {waitingForSlot && s.queuedAt && (
              <Text size="xs" c="dimmed">
                Queued at {new Date(s.queuedAt).toLocaleString()}
              </Text>
            )}
          </Stack>
        </Center>
      );
    }

    if (!canShowEditor) {
      return (
        <div className={classes.workspace}>
          {editorCollapsed && hasIde && (
            <div className={classes.collapseStrip}>
              <Tooltip label="Show editor (⌘B)">
                <ActionIcon aria-label="Show editor (⌘B)" variant="subtle" size="sm" onClick={toggleEditor}>
                  <IconChevronRight size={14} />
                </ActionIcon>
              </Tooltip>
            </div>
          )}
          <div style={{ flex: 1 }} className={`${classes.panelFrame} ${classes.terminalFrame}`}>
            {renderTerminalFrame()}
          </div>
        </div>
      );
    }

    return (
      <PanelGroup
        orientation="horizontal"
        defaultLayout={savedLayout}
        onLayoutChanged={onLayoutChanged}
        className={classes.workspace}
      >
        <Panel defaultSize={50} minSize={20}>
          <div className={`${classes.panelFrame} ${classes.editorFrame}`}>
            {!ideLoaded && renderLoadingOverlay('Loading editor…')}
            <ContainerFrame
              src={s.ideUrl!}
              title="VS Code Editor"
              allow="clipboard-read; clipboard-write"
              onLoad={() => setIdeLoaded(true)}
            />
          </div>
        </Panel>
        <PanelResizeHandle className={classes.resizeHandle} onDoubleClick={toggleEditor}>
          <ActionIcon
            variant="subtle"
            size="xs"
            className={classes.collapseBtn}
            onClick={(e) => {
              e.stopPropagation();
              toggleEditor();
            }}
          >
            <IconChevronLeft size={12} />
          </ActionIcon>
        </PanelResizeHandle>
        <Panel defaultSize={50} minSize={20}>
          <div className={`${classes.panelFrame} ${classes.terminalFrame}`}>{renderTerminalFrame()}</div>
        </Panel>
      </PanelGroup>
    );
  };

  const frameLabel = `session #${s.id} · /workspace`;

  const maximizeLabel = maximized ? 'Exit full screen (Esc)' : 'Full screen (⌘⇧F)';
  const frameActions = (
    <>
      {maximized && renderCopyLinkButton(false)}
      {maximized && canFinish && (
        <Button
          size="compact-sm"
          leftSection={<IconSquareCheck size={14} />}
          onClick={handleFinish}
          loading={finishRequested}
        >
          {finishLabel}
        </Button>
      )}
      <Tooltip label={maximizeLabel} withinPortal={false}>
        <ActionIcon
          aria-label={maximizeLabel}
          aria-pressed={maximized}
          variant="subtle"
          size="sm"
          onClick={toggleMaximized}
        >
          {maximized ? <IconMinimize size={15} /> : <IconMaximize size={15} />}
        </ActionIcon>
      </Tooltip>
    </>
  );

  const frame = isTerminal ? (
    <ConsoleFrame
      className={classes.frame}
      label={frameLabel}
      ref={frameRef}
      actions={frameActions}
      maximized={maximized}
      footer={
        s.state === 'cancelled'
          ? 'Session cancelled'
          : s.state === 'failed'
            ? 'Session failed · workspace is read-only'
            : `Session finished · ${duration} · ${formatCost(s.costCents)} · read-only`
      }
    >
      {s.terminalLogUrl ? (
        <SessionTerminalReplay logUrl={s.terminalLogUrl} fill={maximized} />
      ) : (
        <Center h="100%" p="xl">
          <Text size="sm" c="dimmed">
            This session captured no terminal output.
          </Text>
        </Center>
      )}
    </ConsoleFrame>
  ) : (
    <ConsoleFrame
      className={`${classes.frame} ${classes.frameLive}`}
      label={frameLabel}
      live={isReady}
      ref={frameRef}
      actions={frameActions}
      maximized={maximized}
    >
      {renderWorkspace()}
    </ConsoleFrame>
  );

  return (
    <div className={classes.root}>
      {((finishRequested && !isQueued) || isFinishing) && (
        <div className={classes.finishingOverlay}>
          <Stack align="center" gap="sm">
            <Loader size="lg" />
            <Text fw={600}>Finishing session…</Text>
          </Stack>
        </div>
      )}

      {header}

      <div className={isTerminal ? classes.body : `${classes.body} ${classes.bodyLive}`}>
        {frame}

        {isTerminal && s.errorMessage && (
          <section className={classes.panel}>
            <h3 className={classes.panelTitle}>Error</h3>
            <div className={classes.errorBox}>{s.errorMessage}</div>
          </section>
        )}

        {workflowContext && s.initialPrompt && (
          <details className={`${classes.panel} ${classes.promptPanel}`}>
            <summary className={classes.promptSummary}>Prompt</summary>
            <p className={classes.promptBody}>{s.initialPrompt}</p>
          </details>
        )}

        {isTerminal && s.pendingArtifactsCount > 0 && (
          <section className={classes.panel}>
            <h3 className={classes.panelTitle}>Outputs</h3>
            <Group justify="space-between">
              <Text size="sm">
                {s.pendingArtifactsCount} {s.pendingArtifactsCount === 1 ? 'file is' : 'files are'} waiting for review.
              </Text>
              <Button variant="light" onClick={() => router.visit(ctx.artifactsPath)}>
                Review outputs
              </Button>
            </Group>
          </section>
        )}

        {!isTerminal && s.errorMessage && (
          <Box>
            <Tooltip label={s.errorMessage} maw={400} multiline>
              <Text size="xs" c="var(--app-danger-fg)" className={classes.errorTruncated}>
                {s.errorMessage}
              </Text>
            </Tooltip>
          </Box>
        )}
      </div>
    </div>
  );
}
