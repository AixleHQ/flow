import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { useCallback } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectTaskPath, bulkActionsApiV1ProjectTasksPath } from 'shared/routes';

import type { BulkAction } from './SelectionBar';

interface BulkActionResult {
  succeeded: number[];
  skipped: Array<{ task_id: number; reason: string }>;
}

function actionLabel(action: BulkAction): string {
  switch (action) {
    case 'delete':
      return 'Deleted';
    case 'archive':
      return 'Archived';
    case 'move_to_column':
      return 'Moved';
    case 'set_priority':
      return 'Updated priority for';
    case 'set_assignee':
      return 'Updated assignee for';
    case 'add_tag':
      return 'Tagged';
  }
}

interface UseBulkActionsOptions {
  projectId: number;
  onSuccess: () => void;
}

export function useBulkActions({ projectId, onSuccess }: UseBulkActionsOptions) {
  const execute = useCallback(
    async (action: BulkAction, taskIds: number[], columnId?: number) => {
      try {
        const res = await apiFetch(bulkActionsApiV1ProjectTasksPath(projectId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action_type: action,
            task_ids: taskIds,
            column_id: columnId,
          }),
        });

        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          notifications.show({
            color: 'red',
            title: 'Bulk action failed',
            message: (err as { errors?: string[] }).errors?.[0] ?? 'An error occurred.',
          });
          return;
        }

        const data: BulkActionResult = await res.json();
        const total = data.succeeded.length + data.skipped.length;

        if (data.skipped.length > 0) {
          notifications.show({
            color: 'yellow',
            title: 'Partial success',
            message: `${actionLabel(action)} ${data.succeeded.length} of ${total} task${total === 1 ? '' : 's'}. ${data.skipped.length} skipped (active agent run).`,
          });
        } else {
          notifications.show({
            color: 'green',
            message: `${actionLabel(action)} ${data.succeeded.length} task${data.succeeded.length === 1 ? '' : 's'}.`,
          });
        }

        onSuccess();
        router.reload({ only: ['tasks'] });
      } catch {
        notifications.show({
          color: 'red',
          message: 'Bulk action failed. Please try again.',
        });
      }
    },
    [projectId, onSuccess],
  );

  // Bulk set priority: calls single-task PATCH for each selected task
  const bulkSetPriority = useCallback(
    async (taskIds: number[], priority: string | null) => {
      try {
        await Promise.all(
          taskIds.map((id) =>
            apiFetch(apiV1ProjectTaskPath(projectId, id), {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ board_task: { priority } }),
            }),
          ),
        );

        notifications.show({
          color: 'green',
          message: `Updated priority for ${taskIds.length} task${taskIds.length === 1 ? '' : 's'}.`,
        });

        router.reload({ only: ['tasks'] });
      } catch {
        notifications.show({
          color: 'red',
          message: 'Failed to update priority. Please try again.',
        });
      }
    },
    [projectId],
  );

  // Bulk assign: calls single-task PATCH for each selected task
  const bulkAssign = useCallback(
    async (taskIds: number[], assigneeId: number | null) => {
      try {
        await Promise.all(
          taskIds.map((id) =>
            apiFetch(apiV1ProjectTaskPath(projectId, id), {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ board_task: { assignee_id: assigneeId } }),
            }),
          ),
        );

        notifications.show({
          color: 'green',
          message: `Updated assignee for ${taskIds.length} task${taskIds.length === 1 ? '' : 's'}.`,
        });

        router.reload({ only: ['tasks'] });
      } catch {
        notifications.show({
          color: 'red',
          message: 'Failed to update assignee. Please try again.',
        });
      }
    },
    [projectId],
  );

  // Bulk add tag: calls bulk_actions endpoint with add_tag action
  const bulkAddTag = useCallback(
    async (taskIds: number[], tag: string) => {
      try {
        const res = await apiFetch(bulkActionsApiV1ProjectTasksPath(projectId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action_type: 'add_tag',
            task_ids: taskIds,
            tag,
          }),
        });

        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          notifications.show({
            color: 'red',
            title: 'Bulk action failed',
            message: (err as { errors?: string[] }).errors?.[0] ?? 'An error occurred.',
          });
          return;
        }

        const data: BulkActionResult = await res.json();

        notifications.show({
          color: 'green',
          message: `Tagged ${data.succeeded.length} task${data.succeeded.length === 1 ? '' : 's'}.`,
        });

        router.reload({ only: ['tasks'] });
      } catch {
        notifications.show({
          color: 'red',
          message: 'Failed to add tag. Please try again.',
        });
      }
    },
    [projectId],
  );

  return { execute, bulkSetPriority, bulkAssign, bulkAddTag };
}
