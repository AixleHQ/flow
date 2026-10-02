import { router } from '@inertiajs/react';
import { Alert, Button, Select, Stack, Text, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useEffect, useState } from 'react';

import type { ProjectTracker } from '@/types/generated';

import { apiFetch } from 'shared/lib/apiFetch';
import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { apiV1ProjectWorkflowTriggersPath } from 'shared/routes';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

import { mentionBlocker } from './mentions';
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
  const board = useTrackerStatuses(projectId, tracker?.id ?? null);
  const mentionReason = tracker ? mentionBlocker(tracker) : null;
  // The trigger matches the column's name exactly, so typing one is the fallback
  // for a board whose columns could not be read.
  const typeColumn = board.failed || (!board.loading && board.statuses.length === 0);
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

  const ready = Boolean(workflowId && columnId && (entry === 'mention' ? !mentionReason : status.trim()));
  const dirty =
    entry !== 'status' ||
    status !== '' ||
    workflowId !== (workflows[0]?.id.toString() ?? null) ||
    columnId !== (boardColumns[0]?.id.toString() ?? null);
  const requestClose = useConfirmClose(dirty, onClose);

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
      router.reload({ only: ['triggers'] });
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <ResourceDrawer
      opened={Boolean(tracker)}
      onClose={requestClose}
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
          description={mentionReason ? `A mention cannot start a workflow yet. ${mentionReason}` : undefined}
          data={[
            { value: 'status', label: 'An issue moves to a column' },
            { value: 'mention', label: 'Aixle is mentioned in a comment', disabled: Boolean(mentionReason) },
          ]}
          value={entry}
          onChange={(v) => setEntry((v as Entry) ?? 'status')}
          allowDeselect={false}
        />
        {entry === 'status' &&
          (typeColumn ? (
            <TextInput
              label="Column"
              description="Aixle could not read the columns of the tracker's board, so this name is not checked. Type it exactly as the board shows it, including case."
              placeholder="Ready for AI"
              value={status}
              onChange={(e) => setStatus(e.currentTarget.value)}
              withAsterisk
            />
          ) : (
            <Select
              label="Column"
              description="A column of the tracker's board. Missing one such as “Ready for AI”? Add it on the board, then open this again."
              placeholder={board.loading ? 'Loading the board’s columns…' : 'Pick a column'}
              data={board.statuses}
              value={status || null}
              onChange={(v) => setStatus(v ?? '')}
              disabled={board.loading}
              searchable
              withAsterisk
            />
          ))}
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
