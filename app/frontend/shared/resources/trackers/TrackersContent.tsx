import { Link, router } from '@inertiajs/react';
import { ActionIcon, Anchor, Badge, Box, Button, Group, Stack, Table, Text, Tooltip } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconColumns,
  IconLink,
  IconLock,
  IconLockOpen,
  IconPencil,
  IconPlus,
  IconStar,
  IconTicket,
  IconUnlink,
} from '@tabler/icons-react';
import { useState } from 'react';

import type { ProjectTracker } from '@/types/generated';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { builderCompanyProjectWorkflowPath, companyProjectIntegrationsPath } from 'shared/routes';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';

import { AddTrackerDrawer, type AvailableScopeGroup } from './AddTrackerDrawer';
import { ConnectColumnDrawer, type IntakeOption } from './ConnectColumnDrawer';
import { EditHandleDrawer } from './EditHandleDrawer';

// A tracker trigger as the Trackers page lists it; projectTrackerId null listens to every tracker.
export interface TrackerTriggerSummary {
  id: number;
  workflowId: number;
  workflowName: string;
  projectTrackerId: number | null;
  eventType: string;
  enabled: boolean;
  statuses: string[];
  mentionsOnly: boolean;
}

interface Props {
  projectId: number;
  trackers: ProjectTracker[];
  availableScopes: AvailableScopeGroup[];
  triggers?: TrackerTriggerSummary[];
  workflows?: IntakeOption[];
  boardColumns?: IntakeOption[];
  basePath: string;
}

type TrackerChanges = { status: 'active' } | { primary: true } | { access: 'read_write' | 'read_only' };

const PROVIDER_LABELS: Record<string, string> = {
  azure_devops: 'Azure Boards',
  github: 'GitHub Projects',
  jira: 'Jira',
  linear: 'Linear',
};

const triggerLabel = (trigger: TrackerTriggerSummary) => {
  switch (trigger.eventType) {
    case 'tracker.issue.status_changed':
      return trigger.statuses.length > 0 ? `moves to ${trigger.statuses.join(', ')}` : 'moves to any status';
    case 'tracker.issue.created':
      return 'issue is created';
    case 'tracker.issue.assigned':
      return 'issue is assigned';
    case 'tracker.comment.created':
      return trigger.mentionsOnly ? 'comment mentions Aixle' : 'comment is added';
    default:
      return trigger.eventType;
  }
};

const TriggerList = ({ projectId, triggers }: { projectId: number; triggers: TrackerTriggerSummary[] }) => {
  if (triggers.length === 0)
    return (
      <Text fz={12} c="dimmed">
        None
      </Text>
    );
  return (
    <Stack gap={4}>
      {triggers.map((trigger) => (
        <Box key={trigger.id}>
          <Anchor
            component={Link}
            href={builderCompanyProjectWorkflowPath(projectId, trigger.workflowId, { tab: 'triggers' })}
            fz={13}
            c={trigger.enabled ? undefined : 'dimmed'}
          >
            {trigger.workflowName}
          </Anchor>
          <Text fz={12} c="dimmed">
            {triggerLabel(trigger)}
            {trigger.projectTrackerId === null && ' · any tracker'}
            {!trigger.enabled && ' · off'}
          </Text>
        </Box>
      ))}
    </Stack>
  );
};

const statusBadge = (tracker: ProjectTracker) => {
  if (tracker.status === 'detached')
    return (
      <Badge color="gray" variant="light">
        Detached
      </Badge>
    );
  if (!tracker.usable)
    return (
      <Badge color="orange" variant="light">
        Connection inactive
      </Badge>
    );
  return (
    <Badge color="green" variant="light">
      Active
    </Badge>
  );
};

export const TrackersContent = ({
  projectId,
  trackers,
  availableScopes,
  triggers = [],
  workflows = [],
  boardColumns = [],
  basePath,
}: Props) => {
  const { canExecute } = useProjectPermissions();
  const [addOpen, setAddOpen] = useState(false);
  const [intakeFor, setIntakeFor] = useState<ProjectTracker | null>(null);
  const [handleFor, setHandleFor] = useState<ProjectTracker | null>(null);
  const connectColumnBlocker =
    boardColumns.length === 0
      ? 'Add a board to this project first: the issue gets a task in one of its columns'
      : workflows.length === 0
        ? 'Create a workflow first: moving an issue to the column starts it'
        : null;

  const update = (tracker: ProjectTracker, changes: TrackerChanges, message: string) => {
    router.patch(
      `${basePath}/${tracker.id}`,
      { tracker: changes },
      {
        preserveScroll: true,
        onSuccess: () => notifications.show({ message, color: 'green' }),
        onError: (errors) =>
          notifications.show({ message: Object.values(errors)[0] ?? 'Failed to update tracker', color: 'red' }),
      },
    );
  };

  const detach = (tracker: ProjectTracker) => {
    modals.openConfirmModal({
      title: 'Detach tracker',
      children: (
        <Text size="sm">
          Detach <b>{tracker.name}</b>? Agents stop reaching its issues, and its triggers stop firing until you attach
          it again. Nothing changes in the tracker.
        </Text>
      ),
      labels: { confirm: 'Detach', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () =>
        router.delete(`${basePath}/${tracker.id}`, {
          preserveScroll: true,
          onSuccess: () => notifications.show({ message: 'Tracker detached', color: 'green' }),
          onError: () => notifications.show({ message: 'Failed to detach tracker', color: 'red' }),
        }),
    });
  };

  const addButton = canExecute && availableScopes.length > 0 && (
    <Button leftSection={<IconPlus size={16} />} onClick={() => setAddOpen(true)}>
      Add tracker
    </Button>
  );

  return (
    <Box>
      <PageHeader
        title="Trackers"
        subtitle="Task trackers agents can read and write, and that can start workflows"
        actions={addButton}
      />

      {trackers.length === 0 ? (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
          }}
        >
          <EmptyState
            icon={<IconTicket size={22} />}
            title="No trackers"
            description="Connect Azure DevOps, Jira or Linear on the Integrations page, or pick GitHub Projects on a GitHub connection; each project or team a connection covers becomes a tracker here."
            action={addButton}
          />
        </Box>
      ) : (
        <>
          <Group mb="lg" justify="space-between">
            <ResourceCount>
              {trackers.length} {trackers.length === 1 ? 'tracker' : 'trackers'}
            </ResourceCount>
            {canExecute && availableScopes.length === 0 && (
              <Text fz={12} c="dimmed">
                Each project a connection covers is a tracker here. To add one, add the project to its connection on{' '}
                <Anchor component={Link} href={companyProjectIntegrationsPath(projectId)} fz={12}>
                  Integrations
                </Anchor>
                .
              </Text>
            )}
          </Group>
          <ResourceTableShell>
            <Table highlightOnHover>
              <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
                <Table.Tr>
                  <ResourceTh>Tracker</ResourceTh>
                  <ResourceTh>Connection</ResourceTh>
                  <ResourceTh>Triggers</ResourceTh>
                  <ResourceTh>Status</ResourceTh>
                  <ResourceTh align="right" w={160}>
                    Actions
                  </ResourceTh>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {trackers.map((tracker) => {
                  const detached = tracker.status === 'detached';
                  const readOnly = tracker.access === 'read_only';
                  return (
                    <Table.Tr key={tracker.id}>
                      <Table.Td>
                        <Group gap={6} wrap="nowrap">
                          <Text fz={14} fw={500} c="var(--app-text-primary)">
                            {tracker.name}
                          </Text>
                          {tracker.primary && (
                            <Badge size="xs" variant="light">
                              Primary
                            </Badge>
                          )}
                          {readOnly && (
                            <Badge size="xs" variant="light" color="gray">
                              Read-only
                            </Badge>
                          )}
                        </Group>
                        <Text fz={12} c="dimmed" ff="monospace">
                          {tracker.handle}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Text fz={13}>{tracker.integrationName}</Text>
                        <Text fz={12} c="dimmed">
                          {PROVIDER_LABELS[tracker.provider] ?? tracker.provider}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <TriggerList
                          projectId={projectId}
                          triggers={triggers.filter(
                            (t) => t.projectTrackerId === tracker.id || t.projectTrackerId === null,
                          )}
                        />
                      </Table.Td>
                      <Table.Td>{statusBadge(tracker)}</Table.Td>
                      <Table.Td>
                        {canExecute && (
                          <Group gap={4} justify="flex-end" wrap="nowrap">
                            <Tooltip label="Edit handle">
                              <ActionIcon
                                aria-label="Edit handle"
                                variant="subtle"
                                size="sm"
                                onClick={() => setHandleFor(tracker)}
                              >
                                <IconPencil size={16} />
                              </ActionIcon>
                            </Tooltip>
                            {detached ? (
                              <Tooltip label="Attach again">
                                <ActionIcon
                                  aria-label="Attach again"
                                  variant="subtle"
                                  size="sm"
                                  onClick={() => update(tracker, { status: 'active' }, 'Tracker attached')}
                                >
                                  <IconLink size={16} />
                                </ActionIcon>
                              </Tooltip>
                            ) : (
                              <>
                                {/* data-disabled, not disabled: a disabled button gets no hover, so the tooltip could not say why. */}
                                {tracker.usable && (
                                  <Tooltip label={connectColumnBlocker ?? 'Connect a board column'}>
                                    <ActionIcon
                                      aria-label="Connect a board column"
                                      aria-disabled={connectColumnBlocker ? true : undefined}
                                      data-disabled={connectColumnBlocker ? true : undefined}
                                      variant="subtle"
                                      size="sm"
                                      onClick={() => !connectColumnBlocker && setIntakeFor(tracker)}
                                    >
                                      <IconColumns size={16} />
                                    </ActionIcon>
                                  </Tooltip>
                                )}
                                {!tracker.primary && (
                                  <Tooltip label="Make primary">
                                    <ActionIcon
                                      aria-label="Make primary"
                                      variant="subtle"
                                      size="sm"
                                      onClick={() => update(tracker, { primary: true }, 'Primary tracker changed')}
                                    >
                                      <IconStar size={16} />
                                    </ActionIcon>
                                  </Tooltip>
                                )}
                                <Tooltip label={readOnly ? 'Allow writes' : 'Make read-only'}>
                                  <ActionIcon
                                    aria-label={readOnly ? 'Allow writes' : 'Make read-only'}
                                    variant="subtle"
                                    size="sm"
                                    onClick={() =>
                                      update(
                                        tracker,
                                        { access: readOnly ? 'read_write' : 'read_only' },
                                        readOnly ? 'Writes allowed' : 'Tracker is read-only',
                                      )
                                    }
                                  >
                                    {readOnly ? <IconLockOpen size={16} /> : <IconLock size={16} />}
                                  </ActionIcon>
                                </Tooltip>
                                <Tooltip label="Detach">
                                  <ActionIcon
                                    aria-label="Detach"
                                    variant="subtle"
                                    size="sm"
                                    color="red"
                                    onClick={() => detach(tracker)}
                                  >
                                    <IconUnlink size={16} />
                                  </ActionIcon>
                                </Tooltip>
                              </>
                            )}
                          </Group>
                        )}
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </ResourceTableShell>
        </>
      )}

      <ConnectColumnDrawer
        projectId={projectId}
        tracker={intakeFor}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={() => setIntakeFor(null)}
      />
      <EditHandleDrawer tracker={handleFor} basePath={basePath} onClose={() => setHandleFor(null)} />
      <AddTrackerDrawer
        opened={addOpen}
        onClose={() => setAddOpen(false)}
        basePath={basePath}
        availableScopes={availableScopes}
      />
    </Box>
  );
};
