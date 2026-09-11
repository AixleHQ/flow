import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';

export interface BulkResult {
  succeeded: number[];
  skipped: Array<{ id: number; reason: string }>;
}

interface ErrorBody {
  error?: string;
}

async function parseError(res: Response, fallback: string): Promise<string> {
  try {
    const body = (await res.json()) as ErrorBody;
    return body.error ?? fallback;
  } catch {
    return fallback;
  }
}

/**
 * Single move (`PATCH .../assets/:id`) and bulk move/delete (`POST .../assets/bulk_actions`) for
 * the Assets folder view — the "Move to folder" row action, drag-and-drop, and the multi-select bar.
 */
export function useAssetMutations(apiBasePath: string) {
  const [submitting, setSubmitting] = useState(false);

  const reload = () => router.reload({ only: ['assets', 'folders'] });

  const move = async (assetId: number, folder: string): Promise<boolean> => {
    setSubmitting(true);
    try {
      const res = await apiFetch(`${apiBasePath}/${assetId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ asset: { folder } }),
      });
      if (!res.ok) {
        notifications.show({ message: await parseError(res, 'Failed to move asset'), color: 'red' });
        return false;
      }
      reload();
      return true;
    } catch {
      notifications.show({ message: 'Failed to move asset', color: 'red' });
      return false;
    } finally {
      setSubmitting(false);
    }
  };

  const bulk = async (
    actionType: 'move' | 'delete',
    assetIds: number[],
    folder?: string,
  ): Promise<BulkResult | null> => {
    setSubmitting(true);
    try {
      const res = await apiFetch(`${apiBasePath}/bulk_actions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action_type: actionType, asset_ids: assetIds, folder }),
      });
      if (!res.ok) {
        notifications.show({ message: await parseError(res, 'Bulk action failed'), color: 'red' });
        return null;
      }
      const result = (await res.json()) as BulkResult;
      const verb = actionType === 'delete' ? 'moved to trash' : 'moved';
      if (result.skipped.length > 0) {
        notifications.show({
          message: `${result.succeeded.length} ${verb}, ${result.skipped.length} skipped`,
          color: result.succeeded.length > 0 ? 'yellow' : 'red',
        });
      } else {
        notifications.show({ message: `${result.succeeded.length} ${verb}`, color: 'green' });
      }
      reload();
      return result;
    } catch {
      notifications.show({ message: 'Bulk action failed', color: 'red' });
      return null;
    } finally {
      setSubmitting(false);
    }
  };

  return { submitting, move, bulk };
}
