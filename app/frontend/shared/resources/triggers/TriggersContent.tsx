import { Alert, Box, Button, Group, Loader, Select, Text } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconBolt, IconInfoCircle, IconPlus } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import {
  apiV1ProjectTriggersPath,
  apiV1ProjectWorkflowTriggerPath,
  builderCompanyProjectWorkflowPath,
} from 'shared/routes';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';

import { CHAT_PROVIDER_LABELS, SOURCE_LABELS, triggerSource, triggerTitle } from './describeTrigger';
import type { TrackerOption } from './trackerTrigger';
import { TriggerCards } from './TriggerCards';
import { TriggerFormPanel } from './TriggerFormPanel';
import type { ChatProviderOption, Trigger, TriggerColumnOption, TriggerWorkflowOption } from './types';

interface Props {
  projectId: number;
  workflows: TriggerWorkflowOption[];
  columns: TriggerColumnOption[];
  trackers: TrackerOption[];
  chatProviders?: ChatProviderOption[];
}

const ALL = 'all';

// A source filter value: a source, or chat narrowed to one messenger ("chat:slack").
function filterValue(t: Trigger): string {
  const source = triggerSource(t);
  return source === 'chat' && t.chat_provider ? `chat:${t.chat_provider}` : source;
}

function filterLabel(value: string): string {
  if (value.startsWith('chat:')) {
    const provider = value.slice('chat:'.length);
    return `Chat · ${CHAT_PROVIDER_LABELS[provider] ?? provider}`;
  }
  return SOURCE_LABELS[value] ?? value;
}

const triggerUrl = (projectId: number, t: Trigger) =>
  apiV1ProjectWorkflowTriggerPath(projectId, t.workflow_id ?? 0, t.id, t.kind === 'column' ? { kind: 'column' } : {});

export function TriggersContent({ projectId, workflows, columns, trackers, chatProviders = [] }: Props) {
  const { canExecute } = useProjectPermissions();
  const readOnly = !canExecute;
  const [triggers, setTriggers] = useState<Trigger[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [source, setSource] = useState<string>(ALL);
  const [workflowId, setWorkflowId] = useState<string>(ALL);
  const [panel, setPanel] = useState<{ editing: Trigger | null } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await apiFetch(apiV1ProjectTriggersPath(projectId));
      if (!res.ok) throw new Error(res.statusText);
      const data = await res.json();
      setTriggers(data.triggers ?? []);
      setFailed(false);
    } catch {
      setFailed(true);
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    load();
  }, [load]);

  const sourceOptions = useMemo(() => {
    const values = Array.from(new Set(triggers.map(filterValue)));
    return [{ value: ALL, label: 'All sources' }, ...values.map((v) => ({ value: v, label: filterLabel(v) }))];
  }, [triggers]);

  const workflowOptions = useMemo(
    () => [
      { value: ALL, label: 'All workflows' },
      ...workflows.map((w) => ({ value: w.id.toString(), label: w.name })),
    ],
    [workflows],
  );

  const shown = triggers.filter(
    (t) =>
      (source === ALL || filterValue(t) === source) && (workflowId === ALL || t.workflow_id?.toString() === workflowId),
  );

  const remove = (t: Trigger) => {
    modals.openConfirmModal({
      title: 'Delete trigger',
      children: (
        <Text size="sm">
          Delete <b>{triggerTitle(t)}</b>? It stops starting <b>{t.workflow_name ?? 'its workflow'}</b>. The workflow
          itself is not changed.
        </Text>
      ),
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        const res = await apiFetch(triggerUrl(projectId, t), { method: 'DELETE' });
        if (!res.ok) {
          notifications.show({ message: 'Failed to delete the trigger', color: 'red' });
          return;
        }
        setTriggers((prev) => prev.filter((x) => x.id !== t.id || x.kind !== t.kind));
        notifications.show({ message: 'Trigger deleted', color: 'green' });
      },
    });
  };

  const toggle = async (t: Trigger, enabled: boolean) => {
    const res = await apiFetch(triggerUrl(projectId, t), {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ trigger: { enabled } }),
    });
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      notifications.show({ message: (data.errors ?? ['Failed to update the trigger']).join(', '), color: 'red' });
      return;
    }
    setTriggers((prev) => prev.map((x) => (x.id === t.id && x.kind === t.kind ? { ...x, enabled } : x)));
  };

  const addButton = !readOnly && workflows.length > 0 && (
    <Button leftSection={<IconPlus size={16} />} onClick={() => setPanel({ editing: null })}>
      Add trigger
    </Button>
  );

  return (
    <Box>
      <PageHeader
        title="Triggers"
        subtitle="Every way a workflow of this project starts: board columns, chat, task trackers, schedules and webhooks"
        actions={addButton}
      />

      <Alert variant="light" color="gray" icon={<IconInfoCircle size={16} />} mb="lg">
        A workflow can also be started by hand — the run button on a board task, Run on the workflow, or an agent
        through the MCP tools. Those starts have no trigger to edit.
      </Alert>

      {loading ? (
        <Group justify="center" py="xl">
          <Loader size="sm" aria-label="Loading triggers" />
        </Group>
      ) : failed ? (
        <Alert color="red">The triggers could not be loaded. Reload the page to try again.</Alert>
      ) : triggers.length === 0 ? (
        <EmptyState
          icon={<IconBolt size={22} />}
          title="No triggers"
          description={
            workflows.length === 0
              ? 'Create a workflow first: a trigger is what starts it.'
              : 'Nothing starts a workflow of this project on its own yet.'
          }
          action={addButton}
        />
      ) : (
        <>
          <Group mb="md" gap="sm">
            <Select
              aria-label="Filter by source"
              data={sourceOptions}
              value={source}
              onChange={(v) => setSource(v ?? ALL)}
              allowDeselect={false}
              w={220}
            />
            <Select
              aria-label="Filter by workflow"
              data={workflowOptions}
              value={workflowId}
              onChange={(v) => setWorkflowId(v ?? ALL)}
              allowDeselect={false}
              searchable
              w={260}
            />
            <Text fz={12} c="dimmed">
              {shown.length} of {triggers.length}
            </Text>
          </Group>
          {shown.length === 0 ? (
            <Text fz={13} c="dimmed">
              No trigger matches these filters.
            </Text>
          ) : (
            <TriggerCards
              triggers={shown}
              trackers={trackers}
              chatProviders={chatProviders}
              readOnly={readOnly}
              onEdit={(t) => setPanel({ editing: t })}
              onDelete={remove}
              onToggle={toggle}
              workflowHref={(t) =>
                t.workflow_id ? builderCompanyProjectWorkflowPath(projectId, t.workflow_id, { tab: 'triggers' }) : null
              }
            />
          )}
        </>
      )}

      {panel && !readOnly && (
        <TriggerFormPanel
          projectId={projectId}
          workflows={workflows}
          columns={columns}
          trackers={trackers}
          chatProviders={chatProviders}
          editing={panel.editing}
          defaultKind="column"
          onClose={() => setPanel(null)}
          onSaved={() => {
            setPanel(null);
            load();
          }}
        />
      )}
    </Box>
  );
}
