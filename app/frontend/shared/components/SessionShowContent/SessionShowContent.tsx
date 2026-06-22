import { router } from '@inertiajs/react';
import { ActionIcon, Badge, Box, Button, Card, Center, Group, Loader, Stack, Text, Tooltip } from '@mantine/core';
import { useHotkeys } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { IconArrowLeft, IconChevronLeft, IconChevronRight, IconCopy, IconPlus } from '@tabler/icons-react';
import { type ReactNode, useCallback, useEffect, useMemo, useState } from 'react';
import { Group as PanelGroup, Panel, Separator as PanelResizeHandle, useDefaultLayout } from 'react-resizable-panels';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { finishApiV1TerminalSessionPath } from 'shared/routes';

import classes from './SessionShowContent.module.css';

export interface SessionShowContext {
  backPath: string;
  newSessionPath: string;
  artifactsPath: string;
}

interface Props {
  session: TerminalSession;
  cableStream: string;
  context: SessionShowContext;
}

const AGENT_LABELS: Record<string, string> = {
  claude_code: 'Claude Code',
  cursor_cli: 'Cursor CLI',
  codex: 'Codex',
  gemini_cli: 'Gemini CLI',
};

const AGENT_COLORS: Record<string, string> = {
  claude_code: 'orange',
  cursor_cli: 'violet',
  codex: 'teal',
  gemini_cli: 'blue',
};

const STATE_COLORS: Record<string, string> = {
  not_started: 'gray',
  running: 'blue',
  ready: 'green',
  finishing: 'yellow',
  finished: 'gray',
  failed: 'red',
};

function formatTokens(n: number): string {
  if (!n || n === 0) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function formatCost(cents: number): string {
  if (!cents || cents === 0) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

function formatElapsed(startedAt: string | null, finishedAt: string | null, now: Date): string {
  if (!startedAt) return '—';
  const start = new Date(startedAt);
  const end = finishedAt ? new Date(finishedAt) : now;
  const seconds = Math.max(0, Math.round((end.getTime() - start.getTime()) / 1000));
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

function useElapsedTimer(active: boolean): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}

export function SessionShowContent({ session: s, cableStream, context: ctx }: Props) {
  const agentLabel = AGENT_LABELS[s.agentType ?? ''] ?? s.agentType ?? '—';
  const agentColor = AGENT_COLORS[s.agentType ?? ''] ?? 'gray';
  const stateColor = STATE_COLORS[s.state] ?? 'gray';
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

  const hasIde = !!s.ideUrl;
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

  const hasCacheTokens = s.cacheReadTokens > 0 || s.cacheWriteTokens > 0;
  const hasTokens = s.totalTokens > 0 || s.costCents > 0;

  const renderSummaryRow = (label: string, value: ReactNode) => (
    <div className={classes.summaryRow}>
      <Text size="sm" c="dimmed">
        {label}
      </Text>
      {typeof value === 'string' ? (
        <Text size="sm" fw={500}>
          {value}
        </Text>
      ) : (
        value
      )}
    </div>
  );

  const renderHeader = () => (
    <div className={classes.header}>
      <div className={classes.headerLeft}>
        <ActionIcon variant="subtle" size="sm" onClick={() => router.visit(ctx.backPath)}>
          <IconArrowLeft size={16} />
        </ActionIcon>
        <Text fw={600} size="sm">
          {agentLabel}
        </Text>
        <Badge color={stateColor} size="sm" variant="outline">
          {s.state}
        </Badge>
        <Text size="xs" c="dimmed" ff="monospace">
          #{s.id}
        </Text>
        {s.containerId && (
          <Text size="xs" c="dimmed" ff="monospace">
            {s.containerId.slice(0, 12)}
          </Text>
        )}
        {s.errorMessage && !isTerminal && (
          <Tooltip label={s.errorMessage} maw={400} multiline>
            <Text size="xs" c="red" className={classes.errorTruncated}>
              {s.errorMessage}
            </Text>
          </Tooltip>
        )}
        <Tooltip label="Copy session link">
          <ActionIcon variant="subtle" size="xs" onClick={handleCopyLink}>
            <IconCopy size={14} />
          </ActionIcon>
        </Tooltip>
        {isActive && (
          <Text size="xs" c="dimmed" ff="monospace" className={classes.elapsed}>
            {formatElapsed(s.startedAt, null, now)}
          </Text>
        )}
      </div>
      <div className={classes.headerRight}>
        {!isTerminal && !isFinishing && (
          <Button size="xs" variant="outline" color="red" onClick={handleFinish} loading={finishRequested}>
            Finish
          </Button>
        )}
        <Button size="xs" leftSection={<IconPlus size={14} />} onClick={() => router.visit(ctx.newSessionPath)}>
          New Session
        </Button>
      </div>
    </div>
  );

  const renderCompletionCard = () => (
    <div className={classes.centeredState}>
      <Card withBorder p="xl" className={classes.completionCard}>
        <Stack align="center" gap="md">
          <Group gap="sm">
            <Badge color={agentColor} size="lg" variant="filled">
              {agentLabel}
            </Badge>
            <Badge color={stateColor} size="lg" variant="outline">
              {s.state === 'failed' ? 'Failed' : 'Completed'}
            </Badge>
          </Group>

          {s.errorMessage && (
            <Text c="red" size="sm" ta="center">
              {s.errorMessage}
            </Text>
          )}

          <Stack gap="xs" w="100%">
            {s.mode && renderSummaryRow('Mode', s.mode === 'interactive' ? 'Interactive' : 'Automatic')}
            {renderSummaryRow(
              'Duration',
              <Text size="sm" ff="monospace">
                {formatElapsed(s.startedAt, s.finishedAt, now)}
              </Text>,
            )}
            {renderSummaryRow(
              'Cost',
              <Text size="sm" ff="monospace" fw={600} c={s.costCents > 0 ? 'green' : undefined}>
                {formatCost(s.costCents)}
              </Text>,
            )}
            {s.models.length > 0 &&
              renderSummaryRow(
                'Models',
                <Group gap={4}>
                  {s.models.map((m) => (
                    <Badge key={m} size="xs" variant="outline">
                      {m}
                    </Badge>
                  ))}
                </Group>,
              )}
            {s.pendingArtifactsCount > 0 &&
              renderSummaryRow(
                'Pending Outputs',
                <Badge color="yellow" size="sm">
                  {s.pendingArtifactsCount} files
                </Badge>,
              )}
          </Stack>

          {hasTokens && (
            <Stack gap={4} w="100%">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase">
                Token Usage
              </Text>
              <div className={`${classes.tokenGrid} ${hasCacheTokens ? classes.tokenGridWide : ''}`}>
                <Text size="xs" c="dimmed">
                  Input
                </Text>
                <Text size="xs" ff="monospace" ta="right">
                  {formatTokens(s.inputTokens)}
                </Text>
                {hasCacheTokens && <Box />}
                {hasCacheTokens && (
                  <Text size="xs" c="dimmed">
                    Cache read
                  </Text>
                )}
                {hasCacheTokens && (
                  <Text size="xs" ff="monospace" ta="right">
                    {formatTokens(s.cacheReadTokens)}
                  </Text>
                )}
                <Text size="xs" c="dimmed">
                  Output
                </Text>
                <Text size="xs" ff="monospace" ta="right">
                  {formatTokens(s.outputTokens)}
                </Text>
                {hasCacheTokens && <Box />}
                {hasCacheTokens && (
                  <Text size="xs" c="dimmed">
                    Cache write
                  </Text>
                )}
                {hasCacheTokens && (
                  <Text size="xs" ff="monospace" ta="right">
                    {formatTokens(s.cacheWriteTokens)}
                  </Text>
                )}
              </div>
              <div className={classes.tokenTotal}>
                <Text size="xs" c="dimmed">
                  Total
                </Text>
                <Text size="xs" ff="monospace" fw={600}>
                  {formatTokens(s.totalTokens)} tokens
                </Text>
              </div>
            </Stack>
          )}

          {s.initialPrompt && (
            <Box w="100%">
              <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb={4}>
                Prompt
              </Text>
              <Text size="xs" ff="monospace" c="dimmed" lineClamp={3} style={{ whiteSpace: 'pre-wrap' }}>
                {s.initialPrompt}
              </Text>
            </Box>
          )}

          <Group mt="md" gap="sm">
            {s.pendingArtifactsCount > 0 && (
              <Button color="yellow" variant="filled" onClick={() => router.visit(ctx.artifactsPath)}>
                Review Outputs ({s.pendingArtifactsCount} files)
              </Button>
            )}
            <Button variant="outline" onClick={() => router.visit(ctx.backPath)}>
              All Sessions
            </Button>
            <Button onClick={() => router.visit(ctx.newSessionPath)}>New Session</Button>
          </Group>
        </Stack>
      </Card>
    </div>
  );

  const renderLoadingOverlay = (label: string) => (
    <div className={classes.loadingOverlay}>
      <Loader size="md" />
      <Text size="sm" c="dimmed">
        {label}
      </Text>
    </div>
  );

  const renderWaiting = () => (
    <Box className={classes.panelContainer}>
      <Center h="100%">
        <Stack align="center" gap="md">
          <Loader size="md" />
          <Text size="lg" fw={500}>
            Starting session...
          </Text>
          <Badge color={stateColor} size="sm" variant="light">
            {s.state}
          </Badge>
        </Stack>
      </Center>
    </Box>
  );

  const renderTerminalPanels = () => {
    if (!isReady || !canShowTerminal) return renderWaiting();

    if (!hasIde) {
      return (
        <Box className={classes.panelContainer}>
          <div className={`${classes.panelFrame} ${classes.terminalFrame}`}>
            {!termLoaded && renderLoadingOverlay('Connecting to terminal...')}
            <iframe src={ttydUrl!} title="Terminal" onLoad={() => setTermLoaded(true)} />
          </div>
        </Box>
      );
    }

    if (!canShowEditor && canShowTerminal) {
      return (
        <Box className={classes.panelContainer} style={{ display: 'flex' }}>
          {editorCollapsed && hasIde && (
            <div className={classes.collapseStrip}>
              <Tooltip label="Show editor (⌘B)">
                <ActionIcon variant="subtle" size="sm" onClick={toggleEditor}>
                  <IconChevronRight size={14} />
                </ActionIcon>
              </Tooltip>
            </div>
          )}
          <div style={{ flex: 1 }} className={`${classes.panelFrame} ${classes.terminalFrame}`}>
            {!termLoaded && renderLoadingOverlay('Connecting to terminal...')}
            <iframe src={ttydUrl!} title="Terminal" onLoad={() => setTermLoaded(true)} />
          </div>
        </Box>
      );
    }

    return (
      <PanelGroup
        orientation="horizontal"
        defaultLayout={savedLayout}
        onLayoutChanged={onLayoutChanged}
        className={classes.panelContainer}
      >
        <Panel defaultSize={50} minSize={20}>
          <div className={`${classes.panelFrame} ${classes.editorFrame}`}>
            {!ideLoaded && renderLoadingOverlay('Loading editor...')}
            <iframe src={s.ideUrl!} title="VS Code Editor" onLoad={() => setIdeLoaded(true)} />
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
          <div className={`${classes.panelFrame} ${classes.terminalFrame}`}>
            {!termLoaded && renderLoadingOverlay('Connecting to terminal...')}
            <iframe src={ttydUrl!} title="Terminal" onLoad={() => setTermLoaded(true)} />
          </div>
        </Panel>
      </PanelGroup>
    );
  };

  return (
    <div className={classes.root}>
      {(finishRequested || isFinishing) && (
        <div className={classes.finishingOverlay}>
          <Stack align="center" gap="sm">
            <Loader color="yellow" size="lg" />
            <Text fw={600} c="yellow.8">
              Finishing session…
            </Text>
          </Stack>
        </div>
      )}

      {renderHeader()}

      {isTerminal ? renderCompletionCard() : renderTerminalPanels()}
    </div>
  );
}
