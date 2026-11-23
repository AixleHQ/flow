import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Alert,
  Anchor,
  Badge,
  Box,
  Button,
  Center,
  Group,
  Loader,
  Stack,
  Text,
  Tooltip,
  useComputedColorScheme,
} from '@mantine/core';
import { type HotkeyItem, useClipboard, useHotkeys } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import {
  IconAlertTriangle,
  IconCheck,
  IconChevronLeft,
  IconChevronRight,
  IconCopy,
  IconEye,
  IconMaximize,
  IconMinimize,
  IconPlayerPause,
  IconPlus,
  IconRestore,
  IconSquareCheck,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Group as PanelGroup, Panel, Separator as PanelResizeHandle, useDefaultLayout } from 'react-resizable-panels';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiMutate } from 'shared/lib/apiFetch';
import { useElapsedTimer } from 'shared/lib/hooks/useElapsedTimer';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { ideThemeUrl, ideUrlWithScheme } from 'shared/lib/ideTheme';
import { isWaitingForSlot, launchWaitMessage } from 'shared/lib/launchStatus';
import { costColor, formatCost, formatDuration, formatTokens, shortModelName } from 'shared/lib/sessionFormat';
import { restoreDaysLeft, restoreSession } from 'shared/lib/sessionRestore';
import { useRunsOnMeta } from 'shared/resources/runners/useRunsOnMeta';
import {
  companyProjectSessionPath,
  companySessionPath,
  finishApiV1TerminalSessionPath,
  suspendApiV1TerminalSessionPath,
} from 'shared/routes';
import { ContainerFrame } from 'shared/ui/ContainerFrame';
import {
  agentLabel,
  ConsoleFrame,
  DetailHeader,
  LiveTerminal,
  StatusTag,
  type Crumb,
  type HeaderStat,
} from 'shared/ui/sessions';

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
  suspended: 'Suspended',
  restored: 'Restored',
};

/** How long before the 23-hour limit the live session warns that it will be suspended. */
const SUSPEND_WARNING_MS = 60 * 60 * 1000;

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

/** First line of the prompt — the session's own one-line description. */
function sessionTitle(s: TerminalSession, workflowContext?: SessionWorkflowContext | null): string {
  if (workflowContext?.stepName) return workflowContext.stepName;
  const firstLine = (s.initialPrompt ?? '').trim().split('\n')[0]?.trim();
  if (firstLine) return firstLine.length > 80 ? `${firstLine.slice(0, 80)}…` : firstLine;
  return 'Interactive session';
}

export function SessionShowContent({ session: s, cableStream, context: ctx, workflowContext = null }: Props) {
  const { canExecute } = useProjectPermissions();
  const isTerminal = ['finished', 'failed', 'cancelled', 'suspended', 'restored'].includes(s.state);
  const isQueued = s.state === 'queued';
  const waitingForSlot = isWaitingForSlot(s.launchPhase);
  const isFinishing = s.state === 'finishing';
  const isReady = s.state === 'ready';
  const isActive = isReady || s.state === 'running';

  const [ideLoaded, setIdeLoaded] = useState(false);
  const [finishRequested, setFinishRequested] = useState(false);
  const [suspendRequested, setSuspendRequested] = useState(false);
  const [restoreRequested, setRestoreRequested] = useState(false);
  const [editorCollapsed, setEditorCollapsed] = useState(false);
  const [maximized, setMaximized] = useState(false);
  const frameRef = useRef<HTMLDivElement>(null);
  const clipboard = useClipboard({ timeout: 2000 });
  const runsOnMeta = useRunsOnMeta(s.runner, s.runnerId, s.projectId);

  const now = useElapsedTimer(isActive);

  useInertiaCableStream(cableStream, { only: ['session'], enabled: !isTerminal });

  // Someone else's session, shared with this viewer. They get to watch: the
  // terminal takes no keystrokes (the server hands them ttyd's read-only `view`
  // surface anyway), the editor is not offered at all — an overlay on VS Code
  // is just a broken editor — and Finish is hidden, because the API scopes that
  // action to the owner anyway.
  const isOwner = s.ownedByViewer;
  const colorScheme = useComputedColorScheme('dark', { getInitialValueInEffect: false });
  // The IDE opens in the theme of the moment. A later change is applied in place by
  // a hidden theme page: a new src would reopen the editor and drop unsaved work.
  const [openedInScheme] = useState(colorScheme);
  const [ideThemeChanged, setIdeThemeChanged] = useState(false);
  useEffect(() => {
    if (colorScheme !== openedInScheme) setIdeThemeChanged(true);
  }, [colorScheme, openedInScheme]);
  const themeUrl = ideThemeChanged && s.ideUrl ? ideThemeUrl(s.ideUrl, colorScheme) : null;
  const hasIde = !!s.ideUrl && isOwner;
  // Full screen is for the agent's terminal alone; the editor comes back with
  // the split it had once the console is restored.
  const canShowEditor = hasIde && !editorCollapsed && !maximized;
  const canShowTerminal = !!s.websocketUrl;

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

  const handleSuspend = useCallback(async () => {
    exitMaximized();
    setSuspendRequested(true);
    if (
      await apiMutate(suspendApiV1TerminalSessionPath(s.id), { method: 'POST' }, 'The session could not be suspended')
    ) {
      router.reload({ onFinish: () => setSuspendRequested(false) });
    } else {
      setSuspendRequested(false);
    }
  }, [s.id, exitMaximized]);

  const handleRestore = useCallback(async () => {
    setRestoreRequested(true);
    if (!(await restoreSession(s.id))) setRestoreRequested(false);
  }, [s.id]);

  const handleCopyLink = useCallback(() => {
    clipboard.copy(window.location.href);
    notifications.show({ message: 'Session link copied', color: 'green', autoClose: 2000 });
  }, [clipboard]);

  const toggleEditor = useCallback(() => {
    if (hasIde) setEditorCollapsed((prev) => !prev);
  }, [hasIde]);

  // These skip the terminal's input (a textarea) and the VS Code iframe, so
  // Ctrl+B there stays tmux's prefix; the terminal passes on the one
  // combination it takes back itself (terminalHotkeys).
  useHotkeys([
    ['mod+b', toggleEditor],
    ['mod+shift+F', toggleMaximized],
  ]);
  const terminalHotkeys = useMemo<HotkeyItem[]>(() => [['mod+shift+F', toggleMaximized]], [toggleMaximized]);

  // Capture phase: an open Mantine tooltip (the one on the button just
  // clicked) stops Escape's propagation, which would take two presses to exit.
  useEffect(() => {
    if (!maximized) return undefined;
    // Esc typed into the terminal is the CLI's (it interrupts Claude Code).
    const onKeyDown = (event: KeyboardEvent) => {
      const inTerminal = event.target instanceof Element && event.target.closest('.xterm');
      if (event.key === 'Escape' && !inTerminal) setMaximized(false);
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
  const canSuspend = canExecute && s.suspendable && !isFinishing && !finishRequested;
  const isSuspending = suspendRequested || s.suspending;
  const suspendsAt = s.suspendsAt ? new Date(s.suspendsAt).getTime() : null;
  const suspendWarning = isReady && suspendsAt !== null && now >= suspendsAt - SUSPEND_WARNING_MS;
  const daysLeft = restoreDaysLeft(s.restoreExpiresAt);
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
      extraMeta={runsOnMeta}
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
          {canSuspend && (
            <Tooltip label="Stop the container and keep its files and conversation for 30 days">
              <Button
                variant="default"
                leftSection={<IconPlayerPause size={15} />}
                onClick={handleSuspend}
                loading={suspendRequested}
              >
                Suspend
              </Button>
            </Tooltip>
          )}
          {canFinish && (
            <Button leftSection={<IconSquareCheck size={15} />} onClick={handleFinish} loading={finishRequested}>
              {finishLabel}
            </Button>
          )}
          {s.restorable && canExecute && (
            <Button leftSection={<IconRestore size={15} />} onClick={handleRestore} loading={restoreRequested}>
              Restore
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
    <LiveTerminal url={s.websocketUrl!} readOnly={!isOwner} hotkeys={terminalHotkeys} uploadUrl={s.uploadUrl} />
  );

  const renderWorkspace = () => {
    if (finishRequested || isFinishing || suspendRequested) return null;

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
              src={ideUrlWithScheme(s.ideUrl!, openedInScheme)}
              title="VS Code Editor"
              allow="clipboard-read; clipboard-write"
              onLoad={() => setIdeLoaded(true)}
            />
            {themeUrl && <iframe key={colorScheme} src={themeUrl} title="VS Code theme" hidden />}
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
      {maximized && canSuspend && (
        <Button
          size="compact-sm"
          variant="default"
          leftSection={<IconPlayerPause size={14} />}
          onClick={handleSuspend}
          loading={suspendRequested}
        >
          Suspend
        </Button>
      )}
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
            : s.state === 'suspended'
              ? `Session suspended · ${duration} · ${formatCost(s.costCents)} · read-only`
              : s.state === 'restored'
                ? 'Session restored · read-only'
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
      {((finishRequested && !isQueued) || isFinishing || suspendRequested) && (
        <div className={classes.finishingOverlay}>
          <Stack align="center" gap="sm">
            <Loader size="lg" />
            <Text fw={600}>{isSuspending ? 'Saving files and conversation…' : 'Finishing session…'}</Text>
          </Stack>
        </div>
      )}

      {header}

      <div className={isTerminal ? classes.body : `${classes.body} ${classes.bodyLive}`}>
        {suspendWarning && (
          <Alert
            color="yellow"
            variant="light"
            icon={<IconPlayerPause size={16} />}
            title="This session will be suspended soon"
          >
            <Text size="sm">
              At {new Date(suspendsAt!).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} it reaches the
              23-hour limit. Its files, its repositories&rsquo; changes and the conversation are kept for 30 days, and
              Restore continues from there. Running processes are not kept.
            </Text>
          </Alert>
        )}

        {s.state === 'suspended' && (
          <Alert
            color="yellow"
            variant="light"
            icon={<IconPlayerPause size={16} />}
            title={
              daysLeft === null
                ? 'Suspended'
                : `Suspended · ${daysLeft} ${daysLeft === 1 ? 'day' : 'days'} left to restore`
            }
          >
            <Stack gap={6}>
              <Text size="sm">
                {s.checkpoint?.reason === 'user'
                  ? 'You suspended this session.'
                  : 'This session reached its 23-hour limit.'}{' '}
                {s.checkpoint
                  ? `Saved ${formatBytes(s.checkpoint.bytes)}: the conversation${
                      s.checkpoint.repositories > 0
                        ? `, ${s.checkpoint.repositories} ${s.checkpoint.repositories === 1 ? 'repository' : 'repositories'} with unpushed work`
                        : ''
                    }${s.checkpoint.workspaceIncluded ? ' and the files under /workspace' : ''}.`
                  : ''}
                {s.checkpoint &&
                  !s.checkpoint.workspaceIncluded &&
                  ' The other files under /workspace were too large to keep.'}
              </Text>
              {s.restoreExpiresAt && (
                <Text size="xs" c="dimmed">
                  Restore before {new Date(s.restoreExpiresAt).toLocaleDateString()}. After that the saved files are
                  deleted, and anything in outputs becomes an asset of this session.
                </Text>
              )}
            </Stack>
          </Alert>
        )}

        {s.state === 'restored' && s.restoredSessionId && (
          <Alert color="gray" variant="light" icon={<IconRestore size={16} />} title="Restored">
            <Anchor
              size="sm"
              href={
                s.projectId
                  ? companyProjectSessionPath(s.projectId, s.restoredSessionId)
                  : companySessionPath(s.restoredSessionId)
              }
            >
              Continued in session #{s.restoredSessionId}
            </Anchor>
          </Alert>
        )}

        {s.restoredFromSessionId && (
          <Alert
            color="gray"
            variant="light"
            icon={<IconRestore size={16} />}
            title={`Continues session #${s.restoredFromSessionId}`}
          >
            <Stack gap={4}>
              <Text size="sm">
                Its files, repositories and conversation were put back. Running processes and anything outside
                /workspace were not kept.
              </Text>
              {s.restoreNotes.map((note) => (
                <Text key={note} size="sm" c="dimmed">
                  {note}
                </Text>
              ))}
            </Stack>
          </Alert>
        )}

        {s.authNotice?.state === 'expired' && (
          <Alert
            color="yellow"
            variant="light"
            icon={<IconAlertTriangle size={16} />}
            title={`The ${agentLabel(s.authNotice.agentType)} login was refused`}
          >
            <Stack gap={4}>
              <Text size="sm">
                The agent is waiting at its prompt and nothing is lost. Sign in again and this session gets the new
                login by itself.
              </Text>
              <Anchor size="sm" href={`/profile?authenticate=${encodeURIComponent(s.authNotice.agentType)}`}>
                Sign in again
              </Anchor>
            </Stack>
          </Alert>
        )}

        {s.authNotice?.state === 'renewed' && (
          <Alert color="green" variant="light" icon={<IconCheck size={16} />} title="Login renewed">
            <Text size="sm">The agent has the new login. Send your last message again to carry on.</Text>
          </Alert>
        )}

        {s.failedRepositories.length > 0 && (
          <Alert
            color="orange"
            variant="light"
            icon={<IconAlertTriangle size={16} />}
            title={
              s.failedRepositories.length === 1
                ? 'A repository did not clone'
                : `${s.failedRepositories.length} repositories did not clone`
            }
          >
            <Stack gap={4}>
              {s.failedRepositories.map((repo) => (
                <Text key={repo.id} size="sm" style={{ wordBreak: 'break-word' }}>
                  <b>{repo.fullName}</b> — {repo.error}
                </Text>
              ))}
              <Text size="xs" c="dimmed">
                The agent has no checkout of {s.failedRepositories.length === 1 ? 'it' : 'them'}. Check the connection
                on the project&rsquo;s Integrations page and the repository&rsquo;s source branch, then start a new
                session.
              </Text>
            </Stack>
          </Alert>
        )}

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
