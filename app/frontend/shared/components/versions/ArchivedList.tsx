import { router } from '@inertiajs/react';
import { ActionIcon, Box, Button, Checkbox, Group, Modal, Stack, Table, Text, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArchive, IconHistory, IconRestore } from '@tabler/icons-react';
import { useState } from 'react';

import type { EntityVersion } from '@/types/generated';

import { apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';
import type { VersionableType } from 'shared/lib/versionSchemas';
import { EmptyState } from 'shared/ui/EmptyState';
import { ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';

import { VersionHistoryDrawer } from './VersionHistoryDrawer';

export interface ArchivedItem {
  id: number;
  name: string;
  detail?: string | null;
  archivedAt: string | null;
}

interface ArchivedListProps {
  projectId: number;
  versionableType: VersionableType;
  items: ArchivedItem[];
  /** e.g. "agents" — used in the empty state. */
  noun: string;
  canRestore: boolean;
}

async function restore(projectId: number, type: VersionableType, id: number, enableTriggerIds: number[] = []) {
  await apiRequest(`/api/v1/projects/${projectId}/entity_versions/restore`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ versionable_type: type, versionable_id: id, enable_trigger_ids: enableTriggerIds }),
  });
}

/** Triggers archiving switched off: named by the latest archived version. */
async function disabledTriggerIds(projectId: number, id: number): Promise<number[]> {
  const page = await apiRequest<{ versions: EntityVersion[] }>(
    `/api/v1/projects/${projectId}/entity_versions?versionable_type=Workflow&versionable_id=${id}`,
  );
  return page.versions.find((version) => version.event === 'archived')?.disabledTriggerIds ?? [];
}

/** The Archived tab of a list screen: archived entities with their history and a Restore button. */
export function ArchivedList({ projectId, versionableType, items, noun, canRestore }: ArchivedListProps) {
  const [busyId, setBusyId] = useState<number | null>(null);
  const [historyFor, setHistoryFor] = useState<ArchivedItem | null>(null);
  const [triggerPrompt, setTriggerPrompt] = useState<{ item: ArchivedItem; triggerIds: number[] } | null>(null);
  const [enableTriggers, setEnableTriggers] = useState(true);

  const finishRestore = async (item: ArchivedItem, triggerIds: number[] = []) => {
    setBusyId(item.id);
    try {
      await restore(projectId, versionableType, item.id, triggerIds);
      notifications.show({ color: 'green', message: `${item.name} restored` });
      setTriggerPrompt(null);
      router.reload();
    } catch (error) {
      notifyApiFailure(error, `${item.name} could not be restored`);
    } finally {
      setBusyId(null);
    }
  };

  const startRestore = async (item: ArchivedItem) => {
    if (versionableType !== 'Workflow') return finishRestore(item);
    setBusyId(item.id);
    try {
      const triggerIds = await disabledTriggerIds(projectId, item.id);
      if (triggerIds.length === 0) return finishRestore(item);
      setEnableTriggers(true);
      setTriggerPrompt({ item, triggerIds });
    } catch (error) {
      notifyApiFailure(error, `${item.name} could not be restored`);
    } finally {
      setBusyId(null);
    }
  };

  if (items.length === 0) {
    return (
      <Box
        style={{
          border: '1px solid var(--app-border-default)',
          borderRadius: 'var(--mantine-radius-md)',
          backgroundColor: 'var(--app-bg-paper)',
        }}
      >
        <EmptyState
          icon={<IconArchive size={22} />}
          title={`No archived ${noun}`}
          description={`Archived ${noun} keep their history and can be restored here.`}
        />
      </Box>
    );
  }

  return (
    <>
      <ResourceTableShell>
        <Table highlightOnHover>
          <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
            <Table.Tr>
              <ResourceTh>Name</ResourceTh>
              <ResourceTh>Archived</ResourceTh>
              <ResourceTh align="right" w={160}>
                Actions
              </ResourceTh>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((item) => (
              <Table.Tr key={item.id}>
                <Table.Td>
                  <Text fz={14} fw={500}>
                    {item.name}
                  </Text>
                  {item.detail && (
                    <Text fz={12} c="dimmed" ff="JetBrains Mono, monospace">
                      {item.detail}
                    </Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Text fz={13} c="dimmed">
                    {formatDateTime(item.archivedAt)}
                  </Text>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} justify="flex-end" wrap="nowrap">
                    <Tooltip label="History">
                      <ActionIcon
                        variant="subtle"
                        color="gray"
                        aria-label={`History of ${item.name}`}
                        onClick={() => setHistoryFor(item)}
                      >
                        <IconHistory size={16} />
                      </ActionIcon>
                    </Tooltip>
                    {canRestore && (
                      <Button
                        size="xs"
                        variant="light"
                        leftSection={<IconRestore size={14} />}
                        loading={busyId === item.id}
                        onClick={() => void startRestore(item)}
                      >
                        Restore
                      </Button>
                    )}
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </ResourceTableShell>

      {historyFor && (
        <VersionHistoryDrawer
          opened
          onClose={() => setHistoryFor(null)}
          projectId={projectId}
          versionableType={versionableType}
          versionableId={historyFor.id}
          title={historyFor.name}
          canRevert={false}
        />
      )}

      <Modal opened={triggerPrompt !== null} onClose={() => setTriggerPrompt(null)} title="Restore workflow">
        {triggerPrompt && (
          <Stack gap="md">
            <Text fz={14}>
              Archiving switched off {triggerPrompt.triggerIds.length}{' '}
              {triggerPrompt.triggerIds.length === 1 ? 'trigger' : 'triggers'} of {triggerPrompt.item.name}.
            </Text>
            <Checkbox
              label="Switch them back on"
              description="Schedules and webhooks start runs again as soon as they are on."
              checked={enableTriggers}
              onChange={(event) => setEnableTriggers(event.currentTarget.checked)}
            />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setTriggerPrompt(null)}>
                Cancel
              </Button>
              <Button
                loading={busyId === triggerPrompt.item.id}
                onClick={() => void finishRestore(triggerPrompt.item, enableTriggers ? triggerPrompt.triggerIds : [])}
              >
                Restore
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>
    </>
  );
}
