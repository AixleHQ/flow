import '@testing-library/jest-dom/vitest';

import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core';
import { useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardTask } from 'test/factories/boardTask';
import { act, renderHook, waitFor } from 'test/renderPage';
import type BoardColumn from 'types/generated/BoardColumn';
import type BoardTask from 'types/generated/BoardTask';

import { useBoardDnd } from './useBoardDnd';

const PROJECT_ID = 7;
const BACKLOG = buildBoardColumn({ id: 100, name: 'Backlog', position: 0 });
const IN_PROGRESS = buildBoardColumn({ id: 200, name: 'In Progress', position: 1 });

// dnd-kit hands the handlers an Active/Over pair; only `id` and `data.current` are read, so these
// build the minimum the board's drag logic consumes rather than a full sensor-produced event.
const pickUp = (task: BoardTask): DragStartEvent =>
  ({ active: { id: `task-${task.id}`, data: { current: { type: 'task', task } } } }) as unknown as DragStartEvent;

const dropOnColumn = (task: BoardTask, column: BoardColumn): DragEndEvent =>
  ({
    active: { id: `task-${task.id}`, data: { current: { type: 'task', task } } },
    over: { id: `column-${column.id}`, data: { current: { columnId: column.id } } },
  }) as unknown as DragEndEvent;

const dropOnCard = (task: BoardTask, overTask: BoardTask): DragEndEvent =>
  ({
    active: { id: `task-${task.id}`, data: { current: { type: 'task', task } } },
    over: { id: `task-${overTask.id}`, data: { current: { type: 'task', task: overTask } } },
  }) as unknown as DragEndEvent;

// Mirrors how BoardPage wires the hook: the board owns the task/column state, the hook reads it and
// writes back through the setters. Keeping real state here is what makes the "created after mount"
// case meaningful — the hook must see the appended task, not the list it was first rendered with.
const useBoardHarness = (initialTasks: BoardTask[]) => {
  const [tasks, setTasks] = useState<BoardTask[]>(initialTasks);
  const [columns, setColumns] = useState<BoardColumn[]>([BACKLOG, IN_PROGRESS]);
  const dnd = useBoardDnd({ projectId: PROJECT_ID, enabled: true, tasks, setTasks, columns, setColumns });
  return { tasks, setTasks, ...dnd };
};

type FetchCall = Parameters<typeof fetch>;

const moveCalls = (calls: FetchCall[], taskId: number) =>
  calls.filter(([url]) => url === `/api/v1/projects/${PROJECT_ID}/tasks/${taskId}/move`);

const moveBody = (call: FetchCall) => JSON.parse((call[1] as RequestInit).body as string);

describe('useBoardDnd', () => {
  afterEach(() => vi.restoreAllMocks());

  it('persists the move of a task created after mount, without a reload', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const existing = buildBoardTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 });
    const { result } = renderHook(() => useBoardHarness([existing]));

    // The create-task form appends the POST response to the board state — no page reload.
    const created = buildBoardTask({ id: 99, title: 'Freshly created', boardColumnId: 100, position: 1 });
    act(() => result.current.setTasks((prev) => [...prev, created]));

    // Drag it straight into the next column.
    act(() => result.current.handleDragStart(pickUp(created)));
    await act(async () => {
      await result.current.handleDragEnd(dropOnColumn(created, IN_PROGRESS));
    });

    await waitFor(() => expect(moveCalls(fetchSpy.mock.calls, created.id)).toHaveLength(1));
    expect(moveBody(moveCalls(fetchSpy.mock.calls, created.id)[0])).toEqual({ columnId: 200, position: 1 });
    expect(result.current.tasks.find((t) => t.id === created.id)?.boardColumnId).toBe(200);
  });

  it('moves an existing card onto another card and persists the target position', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const dragged = buildBoardTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 });
    const target = buildBoardTask({ id: 2, title: 'Render dashboard charts', boardColumnId: 200, position: 0 });
    const { result } = renderHook(() => useBoardHarness([dragged, target]));

    act(() => result.current.handleDragStart(pickUp(dragged)));
    await act(async () => {
      await result.current.handleDragEnd(dropOnCard(dragged, target));
    });

    await waitFor(() => expect(moveCalls(fetchSpy.mock.calls, dragged.id)).toHaveLength(1));
    expect(moveBody(moveCalls(fetchSpy.mock.calls, dragged.id)[0])).toEqual({ columnId: 200, position: 0 });
    expect(result.current.tasks.find((t) => t.id === dragged.id)?.boardColumnId).toBe(200);
  });

  it('restores the pre-drag board when the move request fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'));
    const task = buildBoardTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 });
    const { result } = renderHook(() => useBoardHarness([task]));

    act(() => result.current.handleDragStart(pickUp(task)));
    await act(async () => {
      await result.current.handleDragEnd(dropOnColumn(task, IN_PROGRESS));
    });

    await waitFor(() => expect(result.current.tasks.find((t) => t.id === task.id)?.boardColumnId).toBe(100));
  });
});
