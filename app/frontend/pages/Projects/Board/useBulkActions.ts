import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { useCallback } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { bulkActionsApiV1ProjectTasksPath } from 'shared/routes';

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
    case 'move_to_done':
      return 'Moved';
    case 'move_to_column':
      return 'Moved';
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

  return { execute };
}
