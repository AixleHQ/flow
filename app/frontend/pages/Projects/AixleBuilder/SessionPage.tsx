import { Deferred, Head, router, usePage } from '@inertiajs/react';
import { Badge, Box, Button, Group, Loader, Stack, Tabs, Text } from '@mantine/core';
import {
  IconChevronLeft,
  IconCircleFilled,
  IconColumns,
  IconGitBranch,
  IconListDetails,
  IconPlayerStop,
  IconRobot,
  IconSettings,
  IconWand,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import type { BoardColumn, Project, TerminalSession, Workflow } from '@/types/generated';

import { formatTime, parseDate } from 'shared/lib/formatDate';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { terminalPageUrl } from 'shared/lib/terminalPageUrl';
import { agentLabel, isAgentType } from 'shared/ui/agentRuntimes';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './SessionPage.module.css';

// ── Types ──────────────────────────────────────────

interface Props {
  project: Project;
  session: TerminalSession;
  cableStream: string;
  builderActivities?: MetaActivity[];
  workflows?: Workflow[];
  boardColumns?: BoardColumn[];
}

// ── Constants ──────────────────────────────────────

// ── Meta Activity Types ────────────────────────────

interface MetaActivity {
  action: string;
  entityType?: string;
  entityName?: string;
  entityId?: number;
  timestamp: string;
}

// Activities record the builder tool that made the change (`create_workflow_step`);
// sessions from before that recorded past-tense names (`created_step`).
const PAST_TENSE: Record<string, string> = {
  add: 'Added',
  approve: 'Approved',
  archive: 'Archived',
  cancel: 'Cancelled',
  create: 'Created',
  delete: 'Deleted',
  duplicate: 'Duplicated',
  install: 'Installed',
  move: 'Moved',
  reorder: 'Reordered',
  retry: 'Retried',
  setup: 'Set up',
  skip: 'Skipped',
  trigger: 'Triggered',
  uninstall: 'Uninstalled',
  update: 'Updated',
};

const formatActivityAction = (action: string): string => {
  const [verb, ...rest] = action.split('_');
  const label = [PAST_TENSE[verb] ?? verb.charAt(0).toUpperCase() + verb.slice(1), ...rest].join(' ');
  return label.replace(/\bmcp\b/g, 'MCP');
};

const ENTITY_ICONS: Record<string, typeof IconGitBranch> = {
  Workflow: IconGitBranch,
  Step: IconListDetails,
  SubStep: IconListDetails,
  Agent: IconRobot,
  Tool: IconSettings,
  Skill: IconSettings,
  MCPServer: IconSettings,
  BoardColumn: IconColumns,
  Board: IconColumns,
  ColumnWorkflowBinding: IconColumns,
  Trigger: IconColumns,
  BoardTask: IconColumns,
};

// ── Main Component ─────────────────────────────────

const SessionPage = () => {
  const {
    project,
    session: s,
    cableStream,
    builderActivities,
    workflows,
    boardColumns,
  } = usePage<{ props: Props }>().props as unknown as Props;

  const isActive = ['not_started', 'queued', 'running', 'ready'].includes(s.state);
  const isFinishing = s.state === 'finishing';
  const isTerminal = ['finished', 'failed', 'cancelled'].includes(s.state);
  const [finishRequested, setFinishRequested] = useState(false);
  const [tab, setTab] = useState<string | null>('activity');
  const [termLoaded, setTermLoaded] = useState(false);

  const basePath = `/company/projects/${project.id}`;

  useInertiaCableStream(cableStream, {
    only: ['session', 'builder_activities', 'workflows', 'board_columns'],
    enabled: !isTerminal,
  });

  const allActivities = useMemo(() => builderActivities ?? [], [builderActivities]);

  const ttydUrl = useMemo(
    () => terminalPageUrl({ terminalUrl: s.terminalUrl, websocketUrl: s.websocketUrl }),
    [s.terminalUrl, s.websocketUrl],
  );

  const canShowTerminal = !!ttydUrl && s.state === 'ready';
  const runtimeLabel = agentLabel(s.agentType);

  const handleFinish = useCallback(() => {
    setFinishRequested(true);
    router.post(
      `${basePath}/aixle_builder/${s.id}/finish`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setFinishRequested(false),
      },
    );
  }, [s.id, basePath]);

  // ── Render: Terminal panel ─────────────────────

  const renderMainPanel = () => {
    if (finishRequested || isFinishing) return null;

    if (!canShowTerminal) {
      return (
        <div className={classes.mainPanel}>
          <div className={classes.emptyState}>
            {isActive ? (
              <>
                <Loader size="sm" />
                <Text size="sm" c="dimmed">
                  {s.state === 'queued' ? 'Waiting for an available session slot' : 'Starting container...'}
                </Text>
                <Badge size="sm" variant="outline" color="blue">
                  {s.state}
                </Badge>
              </>
            ) : (
              <>
                <Text fw={500}>Session {s.state}</Text>
                {s.errorMessage && (
                  <Text size="sm" c="var(--app-danger-fg)">
                    {s.errorMessage}
                  </Text>
                )}
              </>
            )}
          </div>
        </div>
      );
    }

    return (
      <div className={classes.mainPanel}>
        <div className={`${classes.panelFrame} ${classes.terminalFrame}`}>
          {!termLoaded && (
            <div className={classes.loadingOverlay}>
              <Loader size="md" />
              <Text size="sm" c="dimmed">
                Connecting to terminal...
              </Text>
            </div>
          )}
          <iframe
            src={ttydUrl!}
            title="Terminal"
            allow="clipboard-read; clipboard-write"
            onLoad={() => setTermLoaded(true)}
          />
        </div>
      </div>
    );
  };

  // ── Render: Activity tab ──────────────────────

  const renderActivityTab = () => {
    if (allActivities.length === 0) {
      return (
        <div className={classes.emptyState}>
          <Text size="sm" c="dimmed">
            No builder activity yet
          </Text>
        </div>
      );
    }

    return (
      <Stack gap={0}>
        {allActivities.map((activity, idx) => {
          const entityType = activity.entityType || '';
          const entityName = activity.entityName || '';
          const IconComp = ENTITY_ICONS[entityType] || IconSettings;
          return (
            <div key={idx} className={classes.activityItem}>
              <div className={classes.activityIcon}>
                <IconComp size={14} />
              </div>
              <Box style={{ flex: 1, minWidth: 0 }}>
                <Text size="xs" fw={600} truncate>
                  {entityName}
                </Text>
                <Text size="xs" c="dimmed">
                  {formatActivityAction(activity.action)}
                </Text>
                <Text size="10px" c="dimmed">
                  {formatTime(activity.timestamp)}
                </Text>
              </Box>
            </div>
          );
        })}
      </Stack>
    );
  };

  // ── Render: Workflows tab ─────────────────────

  const renderWorkflowsContent = () => {
    const wfs = workflows ?? [];
    if (wfs.length === 0) {
      return (
        <div className={classes.emptyState}>
          <Text size="sm" c="dimmed">
            No workflows created yet
          </Text>
        </div>
      );
    }

    return (
      <Stack gap="xs">
        {wfs.map((w) => (
          <div key={w.id} className={classes.previewCard}>
            <Group justify="space-between">
              <Text size="sm" fw={500}>
                {w.name}
              </Text>
              <Badge size="xs" variant="outline">
                {w.stepsCount} steps
              </Badge>
            </Group>
            {w.description && (
              <Text size="xs" c="dimmed" lineClamp={2} mt={4}>
                {w.description}
              </Text>
            )}
          </div>
        ))}
      </Stack>
    );
  };

  // ── Render: Board tab ─────────────────────────

  const renderBoardContent = () => {
    const cols = boardColumns ?? [];
    if (cols.length === 0) {
      return (
        <div className={classes.emptyState}>
          <Text size="sm" c="dimmed">
            No board configured yet
          </Text>
        </div>
      );
    }

    return (
      <Stack gap="xs">
        {cols.map((col) => (
          <div key={col.id} className={classes.boardColumn}>
            <Text size="sm" fw={500}>
              {col.name}
            </Text>
            {col.purpose && (
              <Text size="xs" c="dimmed" lineClamp={2}>
                {col.purpose}
              </Text>
            )}
            {col.workflowBinding && (
              <Badge size="xs" variant="outline" mt={4}>
                {col.workflowBinding.triggerMode === 'auto' ? '⚡' : '👆'} {col.workflowBinding.workflowName}
              </Badge>
            )}
          </div>
        ))}
      </Stack>
    );
  };

  // ── Render: Ended state ───────────────────────

  const renderEndedState = () => (
    <div className={classes.centeredState}>
      <Stack align="center" gap="md">
        <IconWand size={48} style={{ opacity: 0.3 }} />
        <Text size="lg" fw={500}>
          Session {s.state}
        </Text>
        {s.errorMessage && (
          <Text size="sm" c="var(--app-danger-fg)" ta="center">
            {s.errorMessage}
          </Text>
        )}
        <Group gap="sm">
          <Button variant="outline" onClick={() => router.visit(`${basePath}/aixle_builder`)}>
            Back to Builder
          </Button>
          <Button onClick={() => router.visit(`${basePath}/aixle_builder`)}>Start New Build</Button>
        </Group>
      </Stack>
    </div>
  );

  // ── Main Render ───────────────────────────────

  return (
    <>
      <Head title={`Aixle Builder — ${project.name}`} />
      <div className={classes.root}>
        {((finishRequested && s.state !== 'queued') || isFinishing) && (
          <div className={classes.finishingOverlay}>
            <Stack align="center" gap="sm">
              <Loader color="yellow" size="lg" />
              <Text fw={600} c="yellow.8">
                Finishing session…
              </Text>
            </Stack>
          </div>
        )}

        {/* Header */}
        <div className={classes.header}>
          <div className={classes.headerLeft}>
            <Button
              variant="subtle"
              size="xs"
              leftSection={<IconChevronLeft size={14} />}
              onClick={() => router.visit(`${basePath}/aixle_builder`)}
            >
              Back
            </Button>
            <IconWand size={18} style={{ color: 'var(--mantine-color-blue-5)' }} />
            <Text fw={600} size="sm">
              Aixle Builder
            </Text>
            <StatusBadge state={s.state} size="sm" />
            <Text size="xs" c="dimmed" ff="monospace">
              #{s.id}
            </Text>
            {isActive && cableStream && (
              <Badge size="xs" color="green" variant="filled" leftSection={<IconCircleFilled size={6} />}>
                Live
              </Badge>
            )}
            {isActive && s.startedAt && (
              <Group gap={4}>
                <div className={classes.liveDot} />
                <ElapsedTimer startedAt={s.startedAt} />
              </Group>
            )}
          </div>
          <div className={classes.headerRight}>
            <Badge color={isAgentType(s.agentType) ? undefined : 'gray'} size="sm" variant="light">
              {runtimeLabel}
            </Badge>
            {isActive && (
              <Button
                size="xs"
                variant="outline"
                color="yellow"
                onClick={handleFinish}
                loading={finishRequested}
                leftSection={<IconPlayerStop size={14} />}
              >
                {s.state === 'queued' ? 'Cancel session' : 'Finish Session'}
              </Button>
            )}
          </div>
        </div>

        {/* Body */}
        {isTerminal ? (
          renderEndedState()
        ) : (
          <div className={classes.body}>
            {renderMainPanel()}

            {/* Side Panel */}
            <div className={classes.sidePanel}>
              <Tabs
                value={tab}
                onChange={setTab}
                styles={{
                  root: { flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0, overflow: 'hidden' },
                  list: { flexShrink: 0 },
                  panel: { flex: 1, minHeight: 0, overflowY: 'auto', padding: 8 },
                }}
              >
                <Tabs.List grow>
                  <Tabs.Tab value="activity">
                    Activity{allActivities.length > 0 ? ` (${allActivities.length})` : ''}
                  </Tabs.Tab>
                  <Tabs.Tab value="workflows">Workflows</Tabs.Tab>
                  <Tabs.Tab value="board">Board</Tabs.Tab>
                </Tabs.List>

                <Tabs.Panel value="activity">
                  <Deferred data="builderActivities" fallback={<Loader size="sm" m="auto" mt="xl" />}>
                    {renderActivityTab()}
                  </Deferred>
                </Tabs.Panel>
                <Tabs.Panel value="workflows">
                  <Deferred data="workflows" fallback={<Loader size="sm" m="auto" mt="xl" />}>
                    {renderWorkflowsContent()}
                  </Deferred>
                </Tabs.Panel>
                <Tabs.Panel value="board">
                  <Deferred data="boardColumns" fallback={<Loader size="sm" m="auto" mt="xl" />}>
                    {renderBoardContent()}
                  </Deferred>
                </Tabs.Panel>
              </Tabs>
            </div>
          </div>
        )}
      </div>
    </>
  );
};

// ── Elapsed Timer sub-component ────────────────────

function ElapsedTimer({ startedAt }: { startedAt: string }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);
  const seconds = Math.max(0, Math.round((now - (parseDate(startedAt)?.getTime() ?? now)) / 1000));
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

setPageLayout(SessionPage, persistentProjectLayout);

export default SessionPage;
