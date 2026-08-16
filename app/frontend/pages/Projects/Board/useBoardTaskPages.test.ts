import '@testing-library/jest-dom/vitest';

import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardTask } from 'test/factories/boardTask';
import { act, renderHook, waitFor } from 'test/renderPage';
import type BoardTask from 'types/generated/BoardTask';

import { boardFilterParams, useBoardTaskPages, type BoardTaskFilters } from './useBoardTaskPages';

const PROJECT_ID = 7;
const PAGE_SIZE = 2;

const BACKLOG = buildBoardColumn({ id: 100, name: 'Backlog', position: 0, tasksCount: 4 });
const IN_PROGRESS = buildBoardColumn({ id: 200, name: 'In Progress', position: 1, tasksCount: 1 });

const NO_FILTERS: BoardTaskFilters = {
  search: '',
  assigneeId: null,
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
 * Answers the per-column tasks endpoint from `byColumn`, with the `X-Total-Count` header the
 * column header reads its total from. A fresh Response per call: a body can only be read once,
 * and every column asks separately.
 */
const stubTasksResponse = (byColumn: Record<number, BoardTask[]>, totals: Record<number, number> = {}) =>
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: RequestInfo | URL) => {
    const columnId = Number(new URL(String(input), 'http://localhost').searchParams.get('board_column_id'));
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
      taskType: 'bug',
      priority: 'high',
      tags: ['api', 'ui'],
      showArchived: true,
    });

    expect(params.get('q[title_cont]')).toBe('auth');
    expect(params.get('q[assignee_id_eq]')).toBe('3');
    expect(params.get('q[task_type_eq]')).toBe('bug');
    expect(params.get('q[priority_eq]')).toBe('high');
    expect(params.getAll('tags[]')).toEqual(['api', 'ui']);
    expect(params.get('tags_match')).toBe('all');
    expect(params.get('archived')).toBe('all');
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
      `/api/v1/projects/${PROJECT_ID}/tasks?board_column_id=100&limit=2&offset=2`,
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

  it('re-queries every column server-side once a filter is on, and reports the filtered totals', async () => {
    const fetchSpy = stubTasksResponse({ 100: [task(3, 100, 2)], 200: [task(9, 200, 0)] });
    const { result } = renderPages({ ...NO_FILTERS, search: 'auth' });

    await waitFor(() => expect(result.current.filtered).toBe(true));
    await waitFor(() => expect(result.current.counts).toEqual({ 100: 1, 200: 1 }));

    const urls = fetchSpy.mock.calls.map(urlOf);
    expect(urls).toHaveLength(2);
    for (const url of urls) expect(url).toContain('q%5Btitle_cont%5D=auth');
    // The props page is replaced by the server's answer rather than filtered in place.
    expect(result.current.tasks.map((t) => t.id)).toEqual([3, 9]);
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

    await waitFor(() => expect(result.current.filtered).toBe(false));
    expect(result.current.tasks.map((t) => t.id)).toEqual([1, 2, 9]);
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
