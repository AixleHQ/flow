import '@testing-library/jest-dom/vitest';

import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardTask } from 'test/factories/boardTask';
import { act, renderHook, waitFor } from 'test/renderPage';
import type BoardTask from 'types/generated/BoardTask';

import { PIN_TTL_MS, boardFilterParams, useBoardTaskPages, type BoardTaskFilters } from './useBoardTaskPages';

const PROJECT_ID = 7;
const PAGE_SIZE = 2;

const BACKLOG = buildBoardColumn({ id: 100, name: 'Backlog', position: 0, tasksCount: 4 });
const IN_PROGRESS = buildBoardColumn({ id: 200, name: 'In Progress', position: 1, tasksCount: 1 });

const NO_FILTERS: BoardTaskFilters = {
  search: '',
  assigneeId: null,
  assigneeTeamId: null,
  taskType: null,
  priority: null,
  tags: [],
  showArchived: false,
};

const task = (id: number, boardColumnId: number, position: number): BoardTask =>
  buildBoardTask({ id, title: `Task ${id}`, boardColumnId, position });

// The first page the board props carry: two of Backlog's four, one of In Progress's one.
const initialTasks = [task(1, 100, 0), task(2, 100, 1), task(9, 200, 0)];
const NO_TASKS: BoardTask[] = [];

/**
 * Answers the tasks endpoints from `byColumn`: the per-column `index` with the `X-Total-Count`
 * header the column header reads its total from, and `by_column` with every column it is asked
 * for. A fresh Response per call: a body can only be read once.
 */
const stubTasksResponse = (byColumn: Record<number, BoardTask[]>, totals: Record<number, number> = {}) =>
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: RequestInfo | URL) => {
    const url = new URL(String(input), 'http://localhost');
    if (url.pathname.endsWith('/tasks/by_column')) {
      const columns = url.searchParams.getAll('board_column_ids[]').map((id) => {
        const items = byColumn[Number(id)] ?? [];
        return { boardColumnId: Number(id), total: totals[Number(id)] ?? items.length, tasks: items };
      });
      return new Response(JSON.stringify({ columns }), { status: 200 });
    }
    const columnId = Number(url.searchParams.get('board_column_id'));
    const items = byColumn[columnId] ?? [];
    return new Response(JSON.stringify(items), {
      status: 200,
      headers: { 'X-Total-Count': String(totals[columnId] ?? items.length) },
    });
  });

const renderPages = (filters: BoardTaskFilters = NO_FILTERS, tasks: BoardTask[] = initialTasks) =>
  renderHook(() =>
    useBoardTaskPages<BoardTask>({
      projectId: PROJECT_ID,
      enabled: true,
      columns: [BACKLOG, IN_PROGRESS],
      initialTasks: tasks,
      pageSize: PAGE_SIZE,
      filters,
      normalize: (t) => t,
    }),
  );

const urlOf = (call: Parameters<typeof fetch>) => String(call[0]);

describe('boardFilterParams', () => {
  it('is empty when nothing is filtered, so the board stays on its props payload', () => {
    expect(boardFilterParams(NO_FILTERS).toString()).toBe('');
  });

  it('spells the attribute filters as ransack predicates and tags as an all-match', () => {
    const params = boardFilterParams({
      search: 'auth',
      assigneeId: '3',
      assigneeTeamId: null,
      taskType: 'bug',
      priority: 'high',
      tags: ['api', 'ui'],
      showArchived: true,
    });

    expect(params.get('q[g][0][title_i_cont]')).toBe('auth');
    expect(params.get('q[g][0][m]')).toBe('or');
    // A non-numeric term emits no number_eq predicate.
    expect(params.get('q[g][0][number_eq]')).toBeNull();
    // The OR combinator lives inside the group, not at the top level, so sibling filters keep AND.
    expect(params.get('q[m]')).toBeNull();
    expect(params.get('q[assignee_id_eq]')).toBe('3');
    expect(params.get('q[task_type_eq]')).toBe('bug');
    expect(params.get('q[priority_eq]')).toBe('high');
    expect(params.getAll('tags[]')).toEqual(['api', 'ui']);
    expect(params.get('tags_match')).toBe('all');
    expect(params.get('archived')).toBe('all');
  });

  it('filters by the team a task is assigned to', () => {
    const params = boardFilterParams({ ...NO_FILTERS, assigneeTeamId: '7' });

    expect(params.get('q[assignee_team_id_eq]')).toBe('7');
    expect(params.get('q[assignee_id_eq]')).toBeNull();
  });
});

describe('useBoardTaskPages', () => {
  afterEach(() => vi.restoreAllMocks());

  it('reports each column its real total and whether pages are missing', () => {
    const { result } = renderPages();

    expect(result.current.tasks).toHaveLength(3);
    expect(result.current.counts).toEqual({ 100: 4, 200: 1 });
    // Backlog holds two of four; In Progress is complete.
    expect(result.current.hasMore).toEqual({ 100: true, 200: false });
    expect(result.current.filtered).toBe(false);
  });

  it('appends the next page of a column without touching the others', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2), task(4, 100, 3)] }, { 100: 4 });
    const { result } = renderPages();

    act(() => result.current.loadMore(100));

    await waitFor(() => expect(result.current.tasks).toHaveLength(5));
    expect(urlOf(fetchSpy.mock.calls[0])).toBe(
      `/api/v1/projects/${PROJECT_ID}/tasks?board_column_id=100&limit=2&offset=2&view=card`,
    );
    // Page two lands in Backlog only, and the column is now complete.
    expect(result.current.tasks.filter((t) => t.boardColumnId === 100)).toHaveLength(4);
    expect(result.current.hasMore[100]).toBe(false);
  });

  it('does not re-request a column that has everything, or one already in flight', async () => {
    const fetchSpy = stubTasksResponse({});
    const { result } = renderPages();

    act(() => result.current.loadMore(200));
    // Two calls in a row for a column whose request has not resolved must collapse into one.
    act(() => {
      result.current.loadMore(100);
      result.current.loadMore(100);
    });

    await waitFor(() => expect(result.current.loading[100]).toBe(false));
    expect(fetchSpy.mock.calls.map(urlOf).filter((url) => url.includes('board_column_id=200'))).toHaveLength(0);
    expect(fetchSpy.mock.calls.map(urlOf).filter((url) => url.includes('board_column_id=100'))).toHaveLength(1);
  });

  it('re-queries every column server-side in one request once a filter is on, with the filtered totals', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2)], 200: [task(9, 200, 0)] }, { 100: 3 });
    const { result } = renderPages({ ...NO_FILTERS, search: 'auth' });

    // `tasks` is mirrored state: the answer lands in `queryTasks` — which `counts` reads in the
    // same commit — and only the effect after that copies it into `tasks`. Waiting on `counts`
    // and then reading `tasks` therefore races the copy, so wait on the list that settles last.
    // The props page is replaced by the server's answer rather than filtered in place.
    await waitFor(() => expect(result.current.tasks.map((t) => t.id)).toEqual([3, 9]));
    expect(result.current.filtered).toBe(true);
    expect(result.current.counts).toEqual({ 100: 3, 200: 1 });
    expect(result.current.hasMore).toEqual({ 100: true, 200: false });

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const url = new URL(urlOf(fetchSpy.mock.calls[0]), 'http://localhost');
    expect(url.pathname).toBe(`/api/v1/projects/${PROJECT_ID}/tasks/by_column`);
    expect(url.searchParams.get('q[g][0][title_i_cont]')).toBe('auth');
    expect(url.searchParams.getAll('board_column_ids[]')).toEqual(['100', '200']);
    // As much as each column already showed, never less than a page.
    expect(url.searchParams.get('limits[100]')).toBe('2');
    expect(url.searchParams.get('limits[200]')).toBe('2');
  });

  it('answers a cable refresh of the filtered board with one more request, not one per column', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2)], 200: [task(9, 200, 0)] });
    const filters = { ...NO_FILTERS, search: 'auth' };
    const { result, rerender } = renderHook(
      ({ tasks }: { tasks: BoardTask[] }) =>
        useBoardTaskPages<BoardTask>({
          projectId: PROJECT_ID,
          enabled: true,
          columns: [BACKLOG, IN_PROGRESS],
          initialTasks: tasks,
          pageSize: PAGE_SIZE,
          filters,
          normalize: (t) => t,
        }),
      { initialProps: { tasks: initialTasks } },
    );
    await waitFor(() => expect(result.current.tasks.map((t) => t.id)).toEqual([3, 9]));

    rerender({ tasks: [...initialTasks] });

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(2));
    for (const call of fetchSpy.mock.calls) expect(urlOf(call)).toContain('/tasks/by_column?');
  });

  it('keeps the filtered tasks and totals when a refresh of the filtered board fails', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2)], 200: [task(9, 200, 0)] });
    const filters = { ...NO_FILTERS, search: 'auth' };
    const { result, rerender } = renderHook(
      ({ tasks }: { tasks: BoardTask[] }) =>
        useBoardTaskPages<BoardTask>({
          projectId: PROJECT_ID,
          enabled: true,
          columns: [BACKLOG, IN_PROGRESS],
          initialTasks: tasks,
          pageSize: PAGE_SIZE,
          filters,
          normalize: (t) => t,
        }),
      { initialProps: { tasks: initialTasks } },
    );
    await waitFor(() => expect(result.current.tasks.map((t) => t.id)).toEqual([3, 9]));

    fetchSpy.mockResolvedValue(new Response('{}', { status: 500 }));
    rerender({ tasks: [...initialTasks] });

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(2));
    // Let the failed request settle before reading what it left behind.
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(result.current.tasks.map((t) => t.id)).toEqual([3, 9]);
    expect(result.current.counts).toEqual({ 100: 1, 200: 1 });
  });

  it('pulls the next filtered page of a column from the paginated index', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2), task(4, 100, 3)], 200: [] }, { 100: 3 });
    const { result } = renderPages({ ...NO_FILTERS, search: 'auth' });
    await waitFor(() => expect(result.current.tasks.map((t) => t.id)).toEqual([3, 4]));

    act(() => result.current.loadMore(100));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(2));
    const url = new URL(urlOf(fetchSpy.mock.calls[1]), 'http://localhost');
    expect(url.pathname).toBe(`/api/v1/projects/${PROJECT_ID}/tasks`);
    expect(url.searchParams.get('board_column_id')).toBe('100');
    expect(url.searchParams.get('offset')).toBe('2');
    expect(url.searchParams.get('q[g][0][title_i_cont]')).toBe('auth');
  });

  it('falls back to the props payload when the filters are cleared', async () => {
    stubTasksResponse({ 100: [task(3, 100, 2)] });
    const { result, rerender } = renderHook(
      ({ filters }: { filters: BoardTaskFilters }) =>
        useBoardTaskPages<BoardTask>({
          projectId: PROJECT_ID,
          enabled: true,
          columns: [BACKLOG, IN_PROGRESS],
          initialTasks,
          pageSize: PAGE_SIZE,
          filters,
          normalize: (t) => t,
        }),
      { initialProps: { filters: { ...NO_FILTERS, priority: 'high' } as BoardTaskFilters } },
    );

    await waitFor(() => expect(result.current.filtered).toBe(true));

    rerender({ filters: NO_FILTERS });

    // Same mirroring as above: `filtered` flips a commit before `tasks` carries the props page.
    await waitFor(() => expect(result.current.tasks.map((t) => t.id)).toEqual([1, 2, 9]));
    expect(result.current.filtered).toBe(false);
    expect(result.current.counts).toEqual({ 100: 4, 200: 1 });
  });

  it('keeps the scrolled-to pages when a cable refresh re-sends page one', async () => {
    stubTasksResponse({ 100: [task(3, 100, 2), task(4, 100, 3)] }, { 100: 4 });
    const { result, rerender } = renderHook(
      ({ tasks }: { tasks: BoardTask[] }) =>
        useBoardTaskPages<BoardTask>({
          projectId: PROJECT_ID,
          enabled: true,
          columns: [BACKLOG, IN_PROGRESS],
          initialTasks: tasks,
          pageSize: PAGE_SIZE,
          filters: NO_FILTERS,
          normalize: (t) => t,
        }),
      { initialProps: { tasks: initialTasks } },
    );

    act(() => result.current.loadMore(100));
    await waitFor(() => expect(result.current.tasks).toHaveLength(5));

    // A board update re-delivers page one as a fresh array; the pages below it must survive.
    rerender({ tasks: [...initialTasks] });

    await waitFor(() => expect(result.current.tasks).toHaveLength(5));
    expect(result.current.tasks.map((t) => t.id).sort()).toEqual([1, 2, 3, 4, 9]);
  });

  it('settles instead of re-deriving forever when the caller rebuilds its task array each render', async () => {
    let renderCount = 0;
    const { result } = renderHook(() => {
      renderCount += 1;
      return useBoardTaskPages<BoardTask>({
        projectId: PROJECT_ID,
        enabled: true,
        columns: [BACKLOG, IN_PROGRESS],
        // A caller spelling its fallback inline (`props.tasks ?? []`) hands over a new array every
        // render; the list is unchanged, so the hook must not treat it as new data.
        initialTasks: [],
        pageSize: PAGE_SIZE,
        filters: NO_FILTERS,
        normalize: (t) => t,
      });
    });

    await waitFor(() => expect(result.current.tasks).toEqual([]));

    // A render loop here does not fail an assertion, it exhausts the worker's heap — so the bound
    // is what keeps that from reaching CI as a mysterious OOM.
    expect(renderCount).toBeLessThan(10);
  });

  describe('a pinned move', () => {
    const renderWithServer = () =>
      renderHook(
        ({ tasks }: { tasks: BoardTask[] }) =>
          useBoardTaskPages<BoardTask>({
            projectId: PROJECT_ID,
            enabled: true,
            columns: [BACKLOG, IN_PROGRESS],
            initialTasks: tasks,
            pageSize: PAGE_SIZE,
            filters: NO_FILTERS,
            normalize: (t) => t,
          }),
        { initialProps: { tasks: initialTasks } },
      );
    const placeOf = (tasks: BoardTask[], id: number) => {
      const found = tasks.find((t) => t.id === id);
      return [found?.boardColumnId, found?.position];
    };

    afterEach(() => vi.useRealTimers());

    it('lets go at once when the save is refused', () => {
      const { result, rerender } = renderWithServer();

      act(() => {
        result.current.pinMove(1, { fromColumnId: 100, boardColumnId: 200, position: 1 });
        result.current.settleMove(1, false);
      });
      rerender({ tasks: [...initialTasks] });

      expect(placeOf(result.current.tasks, 1)).toEqual([100, 0]);
    });

    it('holds a reorder within a column until the server has the new position', () => {
      const { result, rerender } = renderWithServer();

      act(() => result.current.pinMove(1, { fromColumnId: 100, boardColumnId: 100, position: 1 }));
      rerender({ tasks: [...initialTasks] });
      expect(placeOf(result.current.tasks, 1)).toEqual([100, 1]);

      rerender({ tasks: [task(1, 100, 1), task(2, 100, 0), task(9, 200, 0)] });
      rerender({ tasks: [...initialTasks] });
      expect(placeOf(result.current.tasks, 1)).toEqual([100, 0]);
    });

    // Someone else moving the card on: the server never shows it where it was dropped.
    it('gives way to the server once the saved move has gone unconfirmed past its expiry', () => {
      vi.useFakeTimers({ toFake: ['Date'] });
      vi.setSystemTime(new Date('2026-11-20T10:00:00Z'));
      const { result, rerender } = renderWithServer();

      act(() => {
        result.current.pinMove(1, { fromColumnId: 100, boardColumnId: 200, position: 1 });
        result.current.settleMove(1, true);
      });
      rerender({ tasks: [...initialTasks] });
      expect(placeOf(result.current.tasks, 1)).toEqual([200, 1]);

      vi.setSystemTime(new Date(Date.now() + PIN_TTL_MS + 1));
      rerender({ tasks: [...initialTasks] });
      expect(placeOf(result.current.tasks, 1)).toEqual([100, 0]);
    });
  });

  it('fetches nothing until the project has a board', () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const { result } = renderHook(() =>
      useBoardTaskPages<BoardTask>({
        projectId: PROJECT_ID,
        enabled: false,
        columns: [BACKLOG, IN_PROGRESS],
        initialTasks: NO_TASKS,
        pageSize: PAGE_SIZE,
        filters: { ...NO_FILTERS, search: 'auth' },
        normalize: (t) => t,
      }),
    );

    act(() => result.current.loadMore(100));

    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
