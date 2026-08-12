import type { DragEndEvent, DragOverEvent, DragStartEvent } from '@dnd-kit/core';
import { arrayMove } from '@dnd-kit/sortable';
import { router } from '@inertiajs/react';
import { type Dispatch, type SetStateAction, useCallback, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { moveApiV1ProjectTaskPath, reorderApiV1ProjectColumnsPath } from 'shared/routes';

const jsonHeaders = { 'Content-Type': 'application/json' };

// The board's drag-and-drop lives here rather than inline in BoardPage so the move/reorder
// behaviour can be driven directly in tests: dnd-kit's pointer and keyboard sensors both need
// real element geometry, which jsdom does not provide, so a rendered board can never produce a
// drag. The hook's inputs are the drag events themselves, which a test can build.

// The board card fields the drag logic reads. Callers pass their own richer task/column type;
// it flows straight back out (`activeTask`) so the drag overlay still renders a full card.
export interface DndTask {
  id: number;
  boardColumnId: number;
  position: number;
}

export interface DndColumn {
  id: number;
}

interface UseBoardDndOptions<T extends DndTask, C extends DndColumn> {
  projectId: number;
  /** False until the project has a board — a drop then persists nothing. */
  enabled: boolean;
  tasks: T[];
  setTasks: Dispatch<SetStateAction<T[]>>;
  columns: C[];
  setColumns: Dispatch<SetStateAction<C[]>>;
}

interface UseBoardDndResult<T extends DndTask> {
  /** The card being dragged, for the drag overlay. */
  activeTask: T | null;
  /** The column the pointer is currently over, for the drop-target outline. */
  hoverColumnId: number | null;
  handleDragStart: (event: DragStartEvent) => void;
  handleDragOver: (event: DragOverEvent) => void;
  handleDragEnd: (event: DragEndEvent) => Promise<void>;
}

export function useBoardDnd<T extends DndTask, C extends DndColumn>({
  projectId,
  enabled,
  tasks,
  setTasks,
  columns,
  setColumns,
}: UseBoardDndOptions<T, C>): UseBoardDndResult<T> {
  const [activeTask, setActiveTask] = useState<T | null>(null);
  const [hoverColumnId, setHoverColumnId] = useState<number | null>(null);

  const preDragSnapshotRef = useRef<T[]>([]);
  const draggedIdRef = useRef<number | null>(null);
  const dragTypeRef = useRef<'task' | 'column' | null>(null);

  // The pre-drag snapshot has to be taken from the *current* task list. It used to be captured
  // through a `useCallback([])` closure, which froze the list at first render: a task created
  // after mount was missing from the snapshot, so `handleDragEnd` found no `origTask` and bailed
  // out before the PATCH — the card moved on screen (optimistic `handleDragOver`) but the move
  // never persisted until a reload rebuilt the closure. A ref keeps the handler identity stable
  // (it is a DndContext prop) while always reading the latest list.
  const tasksRef = useRef<T[]>(tasks);
  tasksRef.current = tasks;

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const data = event.active.data.current;
    if (data?.type === 'column') {
      dragTypeRef.current = 'column';
      setActiveTask(null);
    } else {
      dragTypeRef.current = 'task';
      const taskData = data?.task as T | undefined;
      setActiveTask(taskData ?? null);
      draggedIdRef.current = taskData?.id ?? null;
      preDragSnapshotRef.current = tasksRef.current.map((t) => ({ ...t }));
    }
    setHoverColumnId(null);
  }, []);

  const handleDragOver = useCallback(
    (event: DragOverEvent) => {
      if (dragTypeRef.current === 'column') return; // columns handled in dragEnd only

      const { over } = event;
      if (!over) {
        setHoverColumnId(null);
        return;
      }

      let targetColumnId: number | null = null;
      if (over.data.current?.columnId) {
        targetColumnId = over.data.current.columnId as number;
      } else if (over.data.current?.task) {
        const overTask = over.data.current.task as T;
        targetColumnId = overTask.boardColumnId;
      }

      setHoverColumnId(targetColumnId);

      if (targetColumnId == null) return;
      const activeId = draggedIdRef.current;
      if (activeId == null) return;

      setTasks((prev) => {
        const activeItem = prev.find((t) => t.id === activeId);
        if (!activeItem || activeItem.boardColumnId === targetColumnId) return prev;

        const targetTasks = prev.filter((t) => t.boardColumnId === targetColumnId);
        const maxPos = targetTasks.reduce((max, t) => Math.max(max, t.position), -1);

        return prev.map((t) =>
          t.id === activeId ? { ...t, boardColumnId: targetColumnId!, position: maxPos + 1 } : t,
        );
      });
    },
    [setTasks],
  );

  const handleDragEnd = useCallback(
    async (event: DragEndEvent) => {
      setActiveTask(null);
      setHoverColumnId(null);
      const { active, over } = event;

      // ── Column reorder ──────────────────────────────────────────────────────
      if (dragTypeRef.current === 'column') {
        dragTypeRef.current = null;
        if (!over || active.id === over.id) return;

        const oldIdx = columns.findIndex((c) => `col-${c.id}` === active.id);
        const newIdx = columns.findIndex((c) => `col-${c.id}` === over.id);
        if (oldIdx === -1 || newIdx === -1) return;

        const newOrder = arrayMove(columns, oldIdx, newIdx);
        setColumns(newOrder);

        // persist to server with error recovery
        apiFetch(reorderApiV1ProjectColumnsPath(projectId), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ columnIds: newOrder.map((c) => c.id) }),
        })
          .then(() => router.reload({ only: ['columns'] }))
          .catch(() => {
            setColumns(columns); // revert on error
            // Error toast would be shown by global error handler
          });
        return;
      }

      // ── Task move ──────────────────────────────────────────────────────────
      dragTypeRef.current = null;
      if (!over || !enabled) {
        draggedIdRef.current = null;
        return;
      }

      const origTask = preDragSnapshotRef.current.find((t) => t.id === draggedIdRef.current);
      draggedIdRef.current = null;
      if (!origTask) return;

      let targetColumnId: number;
      let targetPosition: number | undefined;

      if (over.data.current?.task) {
        const overTask = over.data.current.task as T;
        targetColumnId = overTask.boardColumnId;
        targetPosition = overTask.position;
      } else if (over.data.current?.columnId) {
        targetColumnId = over.data.current.columnId as number;
      } else {
        return;
      }

      const sameColumn = targetColumnId === origTask.boardColumnId;
      if (sameColumn && targetPosition === undefined) return;
      if (sameColumn && targetPosition === origTask.position) return;

      const snapshot = preDragSnapshotRef.current;
      const maxInTargetColumn = snapshot
        .filter((t) => t.boardColumnId === targetColumnId && t.id !== origTask.id)
        .reduce((max, t) => Math.max(max, t.position), 0);
      const position = targetPosition ?? maxInTargetColumn + 1;

      setTasks((prev) => {
        const next = prev.map((t) => ({ ...t }));
        const dragged = next.find((t) => t.id === origTask.id);
        if (!dragged) return prev;

        for (const t of next) {
          if (t.id === origTask.id) continue;
          if (t.boardColumnId === targetColumnId) {
            if (t.position >= position) t.position += 1;
          }
        }
        dragged.boardColumnId = targetColumnId;
        dragged.position = position;

        const colTasks = next.filter((t) => t.boardColumnId === targetColumnId).sort((a, b) => a.position - b.position);
        colTasks.forEach((t, i) => {
          t.position = i;
        });

        if (!sameColumn) {
          const oldColTasks = next
            .filter((t) => t.boardColumnId === origTask.boardColumnId)
            .sort((a, b) => a.position - b.position);
          oldColTasks.forEach((t, i) => {
            t.position = i;
          });
        }

        return next;
      });

      try {
        await apiFetch(moveApiV1ProjectTaskPath(projectId, origTask.id), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ columnId: targetColumnId, position }),
        });
        // cable confirms via board.touch → broadcast_refresh_to(board) → only: ['tasks', 'columns', 'recent_activities']
      } catch {
        setTasks(preDragSnapshotRef.current);
      }
    },
    [enabled, projectId, columns, setColumns, setTasks],
  );

  return { activeTask, hoverColumnId, handleDragStart, handleDragOver, handleDragEnd };
}
