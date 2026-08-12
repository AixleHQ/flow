import { router } from '@inertiajs/react';
import { ActionIcon, Badge, Box, Button, Center, Group, Loader, Stack, Text, Tooltip } from '@mantine/core';
import { useHotkeys } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { IconChevronLeft, IconChevronRight, IconCopy, IconEye, IconPlus, IconSquareCheck } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Group as PanelGroup, Panel, Separator as PanelResizeHandle, useDefaultLayout } from 'react-resizable-panels';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { costColor, formatCost, formatDuration, formatTokens, shortModelName } from 'shared/lib/sessionFormat';
import { finishApiV1TerminalSessionPath } from 'shared/routes';
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
  running: 'Starting',
  ready: 'Running',
  finishing: 'Finishing',
  finished: 'Finished',
  failed: 'Failed',
};

function useElapsedTimer(active: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
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
  const isTerminal = s.state === 'finished' || s.state === 'failed';
  const isFinishing = s.state === 'finishing';
  const isReady = s.state === 'ready';
  const isActive = isReady || s.state === 'running';

  const [ideLoaded, setIdeLoaded] = useState(false);
  const [termLoaded, setTermLoaded] = useState(false);
  const [finishRequested, setFinishRequested] = useState(false);
  const [editorCollapsed, setEditorCollapsed] = useState(false);

  const now = useElapsedTimer(isActive);

  useInertiaCableStream(cableStream, { only: ['session'], enabled: !isTerminal });

  const ttydUrl = useMemo(() => {
    if (!s.websocketUrl) return null;
    return s.websocketUrl.replace('wss://', 'https://').replace('ws://', 'http://').replace('/ws', '');
  }, [s.websocketUrl]);

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
  const canShowEditor = hasIde && !editorCollapsed;
  const canShowTerminal = !!ttydUrl;

  const handleFinish = useCallback(async () => {
    setFinishRequested(true);
    try {
      await apiFetch(finishApiV1TerminalSessionPath(s.id), { method: 'POST' });
      router.reload({ onFinish: () => setFinishRequested(false) });
    } catch (e) {
      setFinishRequested(false);
      throw e;
    }
  }, [s.id]);

  const handleCopyLink = useCallback(() => {
    navigator.clipboard.writeText(window.location.href);
    notifications.show({ message: 'Session link copied', color: 'green', autoClose: 2000 });
  }, []);

  const toggleEditor = useCallback(() => {
    if (hasIde) setEditorCollapsed((prev) => !prev);
  }, [hasIde]);

  useHotkeys([['mod+b', toggleEditor]]);

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
          <Tooltip label="Copy session link">
            <ActionIcon aria-label="Copy session link" variant="subtle" size="sm" onClick={handleCopyLink}>
              <IconCopy size={15} />
            </ActionIcon>
          </Tooltip>
          {/* Finish is owner-only at the API (`current_user.terminal_sessions`),
              so offering it to a viewer would only produce a failed request. */}
          {canExecute && isOwner && !isTerminal && !isFinishing && (
            <Button leftSection={<IconSquareCheck size={15} />} onClick={handleFinish} loading={finishRequested}>
              Finish session
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
      <iframe
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
              Starting session…
            </Text>
            <StatusTag state={s.state}>{SESSION_STATE_LABELS[s.state]}</StatusTag>
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
            <iframe
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

  const frame = isTerminal ? (
    <ConsoleFrame
      className={classes.frame}
      label={frameLabel}
      footer={
        s.state === 'failed'
          ? 'Session failed · workspace is read-only'
          : `Session finished · ${duration} · ${formatCost(s.costCents)} · read-only`
      }
    >
      {s.terminalLogUrl ? (
        <SessionTerminalReplay logUrl={s.terminalLogUrl} />
      ) : (
        <Center h="100%" p="xl">
          <Text size="sm" c="dimmed">
            This session captured no terminal output.
          </Text>
        </Center>
      )}
    </ConsoleFrame>
  ) : (
    <ConsoleFrame className={`${classes.frame} ${classes.frameLive}`} label={frameLabel} live={isReady}>
      {renderWorkspace()}
    </ConsoleFrame>
  );

  return (
    <div className={classes.root}>
      {(finishRequested || isFinishing) && (
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

        {isTerminal && workflowContext && s.initialPrompt && (
          <section className={classes.panel}>
            <h3 className={classes.panelTitle}>Prompt</h3>
            <p className={classes.promptBody}>{s.initialPrompt}</p>
          </section>
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
