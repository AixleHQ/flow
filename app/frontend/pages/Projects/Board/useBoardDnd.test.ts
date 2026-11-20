import '@testing-library/jest-dom/vitest';

import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardTask } from 'test/factories/boardTask';
import { answerFetch } from 'test/fetchStub';
import { act, renderHook, waitFor } from 'test/renderPage';
import type BoardColumn from 'types/generated/BoardColumn';
import type BoardTask from 'types/generated/BoardTask';

import { useBoardDnd } from './useBoardDnd';
import { useBoardTaskPages, type BoardTaskFilters } from './useBoardTaskPages';

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

const pickUpColumn = (column: BoardColumn): DragStartEvent =>
  ({ active: { id: `col-${column.id}`, data: { current: { type: 'column' } } } }) as unknown as DragStartEvent;

const dropColumnOn = (dragged: BoardColumn, over: BoardColumn): DragEndEvent =>
  ({
    active: { id: `col-${dragged.id}`, data: { current: { type: 'column' } } },
    over: { id: `col-${over.id}`, data: { current: { type: 'column' } } },
  }) as unknown as DragEndEvent;

// Mirrors how BoardPage wires the hook: the board owns the task/column state, the hook reads it and
// writes back through the setters. Keeping real state here is what makes the "created after mount"
// case meaningful — the hook must see the appended task, not the list it was first rendered with.
const useBoardHarness = (initialTasks: BoardTask[], initialColumns: BoardColumn[] = [BACKLOG, IN_PROGRESS]) => {
  const [tasks, setTasks] = useState<BoardTask[]>(initialTasks);
  const [columns, setColumns] = useState<BoardColumn[]>(initialColumns);
  const dnd = useBoardDnd({ projectId: PROJECT_ID, enabled: true, tasks, setTasks, columns, setColumns });
  return { tasks, setTasks, columns, setColumns, ...dnd };
};

const NO_FILTERS: BoardTaskFilters = {
  search: '',
  assigneeId: null,
  assigneeTeamId: null,
  taskType: null,
  priority: null,
  tags: [],
  showArchived: false,
};

// BoardPage's real wiring: the task list comes from useBoardTaskPages — the props page in, every
// board reload replacing it — and the drag hook writes into that list and pins what it moves.
const useWiredBoard = (serverTasks: BoardTask[]) => {
  const pages = useBoardTaskPages<BoardTask>({
    projectId: PROJECT_ID,
    enabled: true,
    columns: [BACKLOG, IN_PROGRESS],
    initialTasks: serverTasks,
    pageSize: 25,
    filters: NO_FILTERS,
    normalize: (t) => t,
  });
  const [columns, setColumns] = useState<BoardColumn[]>([BACKLOG, IN_PROGRESS]);
  const dnd = useBoardDnd({
    projectId: PROJECT_ID,
    enabled: true,
    tasks: pages.tasks,
    setTasks: pages.setTasks,
    columns,
    setColumns,
    pinMove: pages.pinMove,
    settleMove: pages.settleMove,
  });
  return { ...pages, ...dnd };
};

type FetchCall = Parameters<typeof fetch>;

const moveCalls = (calls: FetchCall[], taskId: number) =>
  calls.filter(([url]) => url === `/api/v1/projects/${PROJECT_ID}/tasks/${taskId}/move`);

const reorderCalls = (calls: FetchCall[]) =>
  calls.filter(([url]) => url === `/api/v1/projects/${PROJECT_ID}/columns/reorder`);

const moveBody = (call: FetchCall) => JSON.parse((call[1] as RequestInit).body as string);

describe('useBoardDnd', () => {
  afterEach(() => vi.restoreAllMocks());

  it('persists the move of a task created after mount, without a reload', async () => {
    const fetchSpy = answerFetch({ 'PATCH /api/v1/projects/:project/tasks/:task/move': {} });
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
    const fetchSpy = answerFetch({ 'PATCH /api/v1/projects/:project/tasks/:task/move': {} });
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

  // #309: a board reload that left before the save comes back with the card in its old column.
  it('keeps a dropped card in its new column when a reload from before the save lands', async () => {
    answerFetch({ 'PATCH /api/v1/projects/:project/tasks/:task/move': {} });
    const card = buildBoardTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 });
    const other = buildBoardTask({ id: 2, title: 'Render dashboard charts', boardColumnId: 200, position: 0 });
    const { result, rerender } = renderHook(({ server }: { server: BoardTask[] }) => useWiredBoard(server), {
      initialProps: { server: [card, other] },
    });
    const columnOf = (id: number) => result.current.tasks.find((t) => t.id === id)?.boardColumnId;

    act(() => result.current.handleDragStart(pickUp(card)));
    await act(async () => {
      await result.current.handleDragEnd(dropOnColumn(card, IN_PROGRESS));
    });

    rerender({ server: [{ ...card }, { ...other }] });
    expect(columnOf(card.id)).toBe(200);

    // The reload that has the move confirms it; from then on the server's word goes again.
    rerender({ server: [{ ...card, boardColumnId: 200, position: 1 }, { ...other }] });
    expect(columnOf(card.id)).toBe(200);
    rerender({ server: [{ ...card }, { ...other }] });
    expect(columnOf(card.id)).toBe(100);
  });

  // fetch resolves for a refusal too; a 403/422 must not leave the card where it was dropped.
  it("puts the card back and shows the server's reason when the move is refused", async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'Task has an active agent run' }), {
        status: 422,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const task = buildBoardTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 });
    const { result } = renderHook(() => useBoardHarness([task]));

    act(() => result.current.handleDragStart(pickUp(task)));
    await act(async () => {
      await result.current.handleDragEnd(dropOnColumn(task, IN_PROGRESS));
    });

    await waitFor(() => expect(result.current.tasks.find((t) => t.id === task.id)?.boardColumnId).toBe(100));
    expect(show).toHaveBeenCalledWith(expect.objectContaining({ message: 'Task has an active agent run' }));
  });

  // Regression for #580: dragging a column used to persist via `setColumns` *and* trigger a
  // follow-up `router.reload({ only: ['columns'] })`. That reload is an async Inertia partial
  // reload with no ordering guarantee against any other in-flight one (e.g. the reload the
  // "add column" flow fires right after creating a column) — whichever response lands last wins,
  // so a reload fired here could be clobbered by a slightly earlier, now-stale one and the drag
  // would appear to revert. The fix drops the reload and trusts the optimistic order, which
  // already matches what the server persists.
  it('persists a column reorder without triggering a page reload', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));
    // A column "just created" in this session — the exact scenario the bug report calls out.
    const created = buildBoardColumn({ id: 300, name: 'Done', position: 2 });
    const { result } = renderHook(() => useBoardHarness([], [BACKLOG, IN_PROGRESS, created]));

    act(() => result.current.handleDragStart(pickUpColumn(created)));
    await act(async () => {
      await result.current.handleDragEnd(dropColumnOn(created, BACKLOG));
    });

    await waitFor(() => expect(reorderCalls(fetchSpy.mock.calls)).toHaveLength(1));
    expect(JSON.parse((reorderCalls(fetchSpy.mock.calls)[0][1] as RequestInit).body as string)).toEqual({
      columnIds: [300, 100, 200],
    });
    expect(result.current.columns.map((c) => c.id)).toEqual([300, 100, 200]);
    expect(router.reload).not.toHaveBeenCalled();
  });

  it('restores the pre-drag column order when the reorder request fails', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'));
    const created = buildBoardColumn({ id: 300, name: 'Done', position: 2 });
    const { result } = renderHook(() => useBoardHarness([], [BACKLOG, IN_PROGRESS, created]));

    act(() => result.current.handleDragStart(pickUpColumn(created)));
    await act(async () => {
      await result.current.handleDragEnd(dropColumnOn(created, BACKLOG));
    });

    await waitFor(() => expect(result.current.columns.map((c) => c.id)).toEqual([100, 200, 300]));
  });

  it('restores the column order when the server refuses the reorder', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'You cannot change this board' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const created = buildBoardColumn({ id: 300, name: 'Done', position: 2 });
    const { result } = renderHook(() => useBoardHarness([], [BACKLOG, IN_PROGRESS, created]));

    act(() => result.current.handleDragStart(pickUpColumn(created)));
    await act(async () => {
      await result.current.handleDragEnd(dropColumnOn(created, BACKLOG));
    });

    await waitFor(() => expect(result.current.columns.map((c) => c.id)).toEqual([100, 200, 300]));
  });
});
