import { Alert, Autocomplete, Button, Select, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useEffect, useState } from 'react';

import type { ProjectTracker } from '@/types/generated';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectWorkflowTriggersPath } from 'shared/routes';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

import { useTrackerStatuses } from './useTrackerStatuses';

export interface IntakeOption {
  id: number;
  name: string;
}

interface Props {
  projectId: number;
  tracker: ProjectTracker | null;
  workflows: IntakeOption[];
  boardColumns: IntakeOption[];
  onClose: () => void;
}

type Entry = 'status' | 'mention';

// The one-column intake (docs/design/task-tracker-integrations.md §6.8): an
// ordinary tracker trigger, set up in three choices.
export const ConnectColumnDrawer = ({ projectId, tracker, workflows, boardColumns, onClose }: Props) => {
  const statuses = useTrackerStatuses(projectId, tracker?.id ?? null);
  const [entry, setEntry] = useState<Entry>('status');
  const [status, setStatus] = useState('');
  const [workflowId, setWorkflowId] = useState<string | null>(null);
  const [columnId, setColumnId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!tracker) return;
    setEntry('status');
    setStatus('');
    setWorkflowId(workflows[0]?.id.toString() ?? null);
    setColumnId(boardColumns[0]?.id.toString() ?? null);
    setError(null);
  }, [tracker, workflows, boardColumns]);

  const ready = Boolean(workflowId && columnId && (entry === 'mention' || status.trim()));

  const submit = async () => {
    if (!tracker || !workflowId) return;
    setSaving(true);
    setError(null);
    const trigger =
      entry === 'status'
        ? {
            event_type: 'tracker.issue.status_changed',
            filter_predicate: { 'change.to.name': { op: 'in', value: [status.trim()] } },
          }
        : { event_type: 'tracker.comment.created', filter_predicate: { 'comment.mentions_me': true } };
    try {
      const res = await apiFetch(apiV1ProjectWorkflowTriggersPath(projectId, Number(workflowId)), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trigger: {
            kind: 'tracker',
            ...trigger,
            project_tracker_id: tracker.id,
            subject_policy: 'find_or_create_task',
            subject_column_id: columnId,
            aixle_changes: 'ignore',
          },
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError((data.errors ?? ['Failed to connect the column']).join(', '));
        return;
      }
      notifications.show({ message: 'Column connected', color: 'green' });
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <ResourceDrawer
      opened={Boolean(tracker)}
      onClose={onClose}
      title={`Connect ${tracker?.name ?? 'a tracker'}`}
      footer={
        <Button fullWidth loading={saving} disabled={!ready} onClick={submit}>
          Connect
        </Button>
      }
    >
      <Stack gap="md">
        {error && <Alert color="red">{error}</Alert>}
        <Select
          label="Start a workflow when"
          data={[
            { value: 'status', label: 'An issue moves to a column' },
            { value: 'mention', label: 'Aixle is mentioned in a comment' },
          ]}
          value={entry}
          onChange={(v) => setEntry((v as Entry) ?? 'status')}
          allowDeselect={false}
        />
        {entry === 'status' && (
          <Autocomplete
            label="Column"
            description="A column on the tracker's board. Add one such as “Ready for AI” for Aixle."
            placeholder="Ready for AI"
            data={statuses}
            value={status}
            onChange={setStatus}
            withAsterisk
          />
        )}
        <Select
          label="Workflow"
          data={workflows.map((w) => ({ value: w.id.toString(), label: w.name }))}
          value={workflowId}
          onChange={setWorkflowId}
          allowDeselect={false}
          withAsterisk
        />
        <Select
          label="Task column"
          description="Where the issue's board task is created, the first time."
          data={boardColumns.map((c) => ({ value: c.id.toString(), label: c.name }))}
          value={columnId}
          onChange={setColumnId}
          allowDeselect={false}
          withAsterisk
        />
        <Text size="xs" c="dimmed">
          The workflow moves the issue on with its tracker tools; changes it makes do not start it again.
        </Text>
      </Stack>
    </ResourceDrawer>
  );
};
