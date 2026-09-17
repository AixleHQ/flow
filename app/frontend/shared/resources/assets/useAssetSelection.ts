import { useCallback, useState } from 'react';

/**
 * Bulk-selection state for the Assets folder view's multi-select bar. Off by default — the table
 * stays click-to-open until "Select" arms it — and file ids only: folders already carry their own
 * Rename/Move/Delete row actions, so bulk selection is scoped to files (mirrors the Board pattern
 * in `pages/Projects/Board/BoardPage.tsx`, `bulkMode`/`selectedIds`).
 */
export function useAssetSelection() {
  const [bulkMode, setBulkMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());

  const clearSelection = useCallback(() => setSelectedIds(new Set()), []);

  const toggle = useCallback((id: number) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const enterBulkMode = useCallback(() => setBulkMode(true), []);
  // Leaving bulk mode always drops the selection — a checkbox left checked under a view that no
  // longer shows checkboxes would silently apply to whatever the user next bulk-acts on.
  const exitBulkMode = useCallback(() => {
    setBulkMode(false);
    clearSelection();
  }, [clearSelection]);

  return { bulkMode, selectedIds, toggle, clearSelection, enterBulkMode, exitBulkMode };
}
