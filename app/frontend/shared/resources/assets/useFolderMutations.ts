import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';

interface ErrorBody {
  error?: string;
  itemCount?: number;
}

async function parseError(res: Response, fallback: string): Promise<ErrorBody> {
  try {
    const body = (await res.json()) as ErrorBody;
    return { error: body.error ?? fallback, itemCount: body.itemCount };
  } catch {
    return { error: fallback };
  }
}

/**
 * Create / relocate (rename or move) / destroy mutations for the Assets folder view, against
 * `FolderService`'s three endpoints (`POST`/`PATCH .../relocate`/`DELETE` on `foldersApiBase`).
 * Reloads only the `assets`/`folders` Inertia props on success — nothing else on the page refetches.
 */
export function useFolderMutations(foldersApiBase: string) {
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = () => router.reload({ only: ['assets', 'folders'] });

  const create = async (path: string): Promise<boolean> => {
    setSubmitting(true);
    setError(null);
    try {
      const res = await apiFetch(foldersApiBase, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder: { path } }),
      });
      if (!res.ok) {
        const { error: message } = await parseError(res, 'Failed to create folder');
        setError(message ?? 'Failed to create folder');
        return false;
      }
      reload();
      return true;
    } catch {
      setError('Failed to create folder');
      return false;
    } finally {
      setSubmitting(false);
    }
  };

  const relocate = async (fromPath: string, toPath: string): Promise<boolean> => {
    setSubmitting(true);
    setError(null);
    try {
      const res = await apiFetch(`${foldersApiBase}/relocate`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ from_path: fromPath, to_path: toPath }),
      });
      if (!res.ok) {
        const { error: message } = await parseError(res, 'Failed to rename folder');
        setError(message ?? 'Failed to rename folder');
        return false;
      }
      reload();
      return true;
    } catch {
      setError('Failed to rename folder');
      return false;
    } finally {
      setSubmitting(false);
    }
  };

  const destroy = async (path: string, recursive: boolean): Promise<{ ok: boolean; itemCount?: number }> => {
    setSubmitting(true);
    try {
      const res = await apiFetch(foldersApiBase, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path, recursive }),
      });
      if (!res.ok) {
        const { error: message, itemCount } = await parseError(res, 'Failed to delete folder');
        if (itemCount === undefined)
          notifications.show({ message: message ?? 'Failed to delete folder', color: 'red' });
        return { ok: false, itemCount };
      }
      notifications.show({ message: recursive ? 'Folder and its contents deleted' : 'Folder deleted', color: 'green' });
      reload();
      return { ok: true };
    } catch {
      notifications.show({ message: 'Failed to delete folder', color: 'red' });
      return { ok: false };
    } finally {
      setSubmitting(false);
    }
  };

  return { submitting, error, setError, create, relocate, destroy };
}
