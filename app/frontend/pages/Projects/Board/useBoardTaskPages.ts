import { type Dispatch, type SetStateAction, useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectTasksPath } from 'shared/routes';

// Per-column pagination for the board. The board page props carry only the first page of every
// column plus each column's total, so this hook owns everything after that first page: it pulls
// the next page when a column is scrolled, and — once a filter is on — re-queries every column
// server-side, because a filter applied to the pages a column happens to have loaded would quietly
// hide matching tasks that live further down.

/** The task fields this hook needs; the caller's richer task type flows straight through. */
export interface PagedTask {
  id: number;
  boardColumnId: number;
  position: number;
}

interface PagedColumn {
  id: number;
  /** Total active tasks in the column, from the board props (BoardColumnResource#tasks_count). */
  tasksCount?: number;
}

export interface BoardTaskFilters {
  search: string;
  assigneeId: string | null;
  assigneeTeamId: string | null;
  taskType: string | null;
  priority: string | null;
  tags: string[];
  showArchived: boolean;
}

interface UseBoardTaskPagesOptions<T extends PagedTask> {
  projectId: number;
  /** False until the project has a board — nothing is fetched then. */
  enabled: boolean;
  columns: PagedColumn[];
  /** First page of every column, from the Inertia props. */
  initialTasks: T[];
  pageSize: number;
  filters: BoardTaskFilters;
  /** Applied to every task this hook fetches, so its shape matches the props payload. */
  normalize: (task: T) => T;
}

/** Where a dropped card was sent, as the move request states it. */
export interface PendingMove {
  fromColumnId: number;
  boardColumnId: number;
  position: number;
}

interface UseBoardTaskPagesResult<T extends PagedTask> {
  /** Every task the client holds, flat. Optimistic updates (drag, create) write here. */
  tasks: T[];
  setTasks: Dispatch<SetStateAction<T[]>>;
  /** Hold a dropped card where it was sent until the server shows it there. */
  pinMove: (taskId: number, move: PendingMove) => void;
  /** The move request answered: a saved move starts its expiry, a refused one lets go at once. */
  settleMove: (taskId: number, saved: boolean) => void;
  /** Total tasks per column — the unpaginated total, not what is loaded. */
  counts: Record<number, number>;
  hasMore: Record<number, boolean>;
  loading: Record<number, boolean>;
  loadMore: (columnId: number) => void;
  /** Whether the board is currently reading filtered results from the server. */
  filtered: boolean;
}

interface ColumnPage<T> {
  items: T[];
  total: number;
}

/** `GET /api/v1/projects/:id/tasks/by_column`: the first page and total of every column asked for. */
interface ByColumnResponse<T> {
  columns: { boardColumnId: number; total: number; tasks: T[] }[];
}

/** Server-side spelling of the board filters. Empty when nothing is filtered. */
export function boardFilterParams(filters: BoardTaskFilters): URLSearchParams {
  const params = new URLSearchParams();
  // Plain attribute filters go through ransack (BoardTask.ransackable_attributes).
  // Search matches either the title or the board-local task number. The two predicates live in a
  // ransack OR grouping (`q[g][0][...]` with the combinator `q[g][0][m]=or` set inside the group) so
  // the OR stays scoped to search and does not leak into the sibling filters below, which keep
  // ANDing at the top level via ransack's default. A term is treated as a number only when
  // it is a plain integer (one optional leading `#`, matching the displayed `#N` format); title
  // matching always uses the raw term.
  if (filters.search) {
    params.set('q[g][0][m]', 'or');
    params.set('q[g][0][title_i_cont]', filters.search);
    const numberTerm = filters.search.trim().replace(/^#/, '');
    if (/^\d+$/.test(numberTerm)) params.set('q[g][0][number_eq]', numberTerm);
  }
  if (filters.assigneeId) params.set('q[assignee_id_eq]', filters.assigneeId);
  if (filters.assigneeTeamId) params.set('q[assignee_team_id_eq]', filters.assigneeTeamId);
  if (filters.taskType) params.set('q[task_type_eq]', filters.taskType);
  if (filters.priority) params.set('q[priority_eq]', filters.priority);
  if (filters.tags.length > 0) {
    for (const tag of filters.tags) params.append('tags[]', tag);
    // The board's tag filter means "carries all of these", not "any of these".
    params.set('tags_match', 'all');
  }
  // Archived is a view toggle rather than a narrowing filter: it *adds* archived tasks.
  if (filters.showArchived) params.set('archived', 'all');
  return params;
}

function mergeById<T extends PagedTask>(primary: T[], extra: T[]): T[] {
  const ids = new Set(primary.map((t) => t.id));
  return [...primary, ...extra.filter((t) => !ids.has(t.id))];
}

/**
 * Whether two task lists are the same objects in the same order. The guard below needs this
 * because a caller that rebuilds its `initialTasks` array every render (a `?? []` fallback, say)
 * would otherwise drive an endless render → setTasks → render cycle.
 */
function sameTasks<T extends PagedTask>(a: T[], b: T[]): boolean {
  return a === b || (a.length === b.length && a.every((task, i) => task === b[i]));
}

// Clearing state has to be a no-op once it is already clear. Writing a fresh `[]`/`{}` would be a
// new identity every time, and these clears run from effects that re-fire on new props — enough to
// spin render → clear → render forever.
function clearedList<T>(prev: T[]): T[] {
  return prev.length === 0 ? prev : [];
}

function clearedMap(prev: Record<number, number>): Record<number, number> {
  return Object.keys(prev).length === 0 ? prev : {};
}

// A board reload already on its way when a card is dropped answers with the card in its old column,
// and taking that list as it is snaps the card back until the next reload (#309). So a dropped card
// keeps the place it was sent to until the server shows it there — or, when someone else has moved
// it meanwhile, until this long after the save.
export const PIN_TTL_MS = 10_000;

interface Pin extends PendingMove {
  savedAt: number | null;
}

function serverShowsMove(task: PagedTask, pin: Pin): boolean {
  if (task.boardColumnId !== pin.boardColumnId) return false;
  // Across columns, the column alone tells: no stale list has the card there yet. Within one, only
  // the position the request sent does.
  return pin.fromColumnId !== pin.boardColumnId || task.position === pin.position;
}

function holdPinned<T extends PagedTask>(server: T[], pins: Map<number, Pin>, now: number): T[] {
  if (pins.size === 0) return server;
  return server.map((task) => {
    const pin = pins.get(task.id);
    if (!pin) return task;
    const expired = pin.savedAt !== null && now - pin.savedAt > PIN_TTL_MS;
    if (expired || serverShowsMove(task, pin)) {
      pins.delete(task.id);
      return task;
    }
    return { ...task, boardColumnId: pin.boardColumnId, position: pin.position };
  });
}

function countByColumn(tasks: PagedTask[]): Record<number, number> {
  const counts: Record<number, number> = {};
  for (const task of tasks) counts[task.boardColumnId] = (counts[task.boardColumnId] ?? 0) + 1;
  return counts;
}

export function useBoardTaskPages<T extends PagedTask>({
  projectId,
  enabled,
  columns,
  initialTasks,
  pageSize,
  filters,
  normalize,
}: UseBoardTaskPagesOptions<T>): UseBoardTaskPagesResult<T> {
  const filterKey = boardFilterParams(filters).toString();
  const filtered = filterKey !== '';
  // The columns array is rebuilt on every render; this key is what actually changes about it, and
  // is what the fetching effects below key off instead of the array identity.
  const columnIdsKey = columns.map((c) => c.id).join(',');

  // Values read inside fetches without making them a dependency of every effect: the filter key
  // and the column keys already say when a refetch is due.
  const filtersRef = useRef(filters);
  filtersRef.current = filters;
  const normalizeRef = useRef(normalize);
  normalizeRef.current = normalize;
  const columnsRef = useRef(columns);
  columnsRef.current = columns;

  const fetchPage = useCallback(
    async (columnId: number, limit: number, offset: number): Promise<ColumnPage<T>> => {
      const params = boardFilterParams(filtersRef.current);
      params.set('board_column_id', String(columnId));
      params.set('limit', String(limit));
      params.set('offset', String(offset));
      params.set('view', 'card');

      const res = await apiFetch(`${apiV1ProjectTasksPath(projectId)}?${params.toString()}`);
      if (!res.ok) throw new Error(`Failed to load tasks for column ${columnId}`);

      const data = await res.json();
      const items = (Array.isArray(data) ? (data as T[]) : []).map((t) => normalizeRef.current(t));
      // X-Total-Count is the column's total before limit/offset. Falling back to what this page
      // holds keeps a response without the header (a test stub, an older backend) from claiming
      // there is more to load than there is.
      const headerTotal = Number(res.headers.get('X-Total-Count'));
      return { items, total: Number.isFinite(headerTotal) && headerTotal >= 0 ? headerTotal : offset + items.length };
    },
    [projectId],
  );

  const fetchColumns = useCallback(
    async (columnIds: number[], limits: number[]): Promise<ByColumnResponse<T>['columns']> => {
      const params = boardFilterParams(filtersRef.current);
      columnIds.forEach((id, i) => {
        params.append('board_column_ids[]', String(id));
        params.set(`limits[${id}]`, String(limits[i]));
      });

      // Spelled by hand because shared/routes.ts (generated) gains byColumnApiV1ProjectTasksPath only
      // on the next `bin/rails ts:routes`; switch to that helper once it is there.
      const res = await apiFetch(`${apiV1ProjectTasksPath(projectId)}/by_column?${params.toString()}`);
      if (!res.ok) throw new Error('Failed to load the board columns');

      const data = (await res.json()) as Partial<ByColumnResponse<T>>;
      return (data.columns ?? []).map((column) => ({
        ...column,
        tasks: column.tasks.map((t) => normalizeRef.current(t)),
      }));
    },
    [projectId],
  );

  // Pages pulled by scrolling, in the unfiltered view. Kept apart from the props page so a cable
  // refresh (which re-sends page one) cannot throw away the pages the user scrolled to.
  const [extraTasks, setExtraTasks] = useState<T[]>([]);
  // The whole task list in the filtered view — there the server, not the props, decides membership.
  const [queryTasks, setQueryTasks] = useState<T[] | null>(null);
  const [queryTotals, setQueryTotals] = useState<Record<number, number>>({});
  const [loading, setLoading] = useState<Record<number, boolean>>({});

  const extraTasksRef = useRef<T[]>(extraTasks);
  extraTasksRef.current = extraTasks;

  const baseTasks = useMemo(() => initialTasks.map((t) => normalizeRef.current(t)), [initialTasks]);

  const merged = useMemo(
    () => (filtered ? (queryTasks ?? []) : mergeById(baseTasks, extraTasks)),
    [filtered, queryTasks, baseTasks, extraTasks],
  );

  const pinsRef = useRef<Map<number, Pin>>(new Map());
  const pinMove = useCallback((taskId: number, move: PendingMove) => {
    pinsRef.current.set(taskId, { ...move, savedAt: null });
  }, []);
  const settleMove = useCallback((taskId: number, saved: boolean) => {
    const pin = pinsRef.current.get(taskId);
    if (!pin) return;
    if (saved) pin.savedAt = Date.now();
    else pinsRef.current.delete(taskId);
  }, []);

  // Rendering and drag-and-drop read this copy, which optimistic updates mutate in place; the
  // server-derived list above replaces it whenever fresh data lands, except for cards still pinned.
  const [tasks, setTasks] = useState<T[]>(merged);
  useEffect(() => {
    const next = holdPinned(merged, pinsRef.current, Date.now());
    setTasks((prev) => (sameTasks(prev, next) ? prev : next));
  }, [merged]);

  const loadedByColumn = useMemo(() => countByColumn(tasks), [tasks]);
  const loadedRef = useRef(loadedByColumn);
  loadedRef.current = loadedByColumn;

  const counts = useMemo(() => {
    if (filtered) return queryTotals;
    const propCounts: Record<number, number> = {};
    for (const column of columns) propCounts[column.id] = column.tasksCount ?? loadedByColumn[column.id] ?? 0;
    return propCounts;
  }, [filtered, queryTotals, columns, loadedByColumn]);

  const hasMore = useMemo(() => {
    const more: Record<number, boolean> = {};
    for (const column of columns) more[column.id] = (loadedByColumn[column.id] ?? 0) < (counts[column.id] ?? 0);
    return more;
  }, [columns, loadedByColumn, counts]);

  const hasMoreRef = useRef(hasMore);
  hasMoreRef.current = hasMore;
  // In-flight columns live in a ref, not in `loading` state: a scroll fires many events before
  // React re-renders, and a state flag would still read false on every one of them.
  const inFlightRef = useRef<Set<number>>(new Set());

  const loadMore = useCallback(
    (columnId: number) => {
      if (!enabled || inFlightRef.current.has(columnId) || !hasMoreRef.current[columnId]) return;

      const offset = loadedRef.current[columnId] ?? 0;
      inFlightRef.current.add(columnId);
      setLoading((prev) => ({ ...prev, [columnId]: true }));

      fetchPage(columnId, pageSize, offset)
        .then(({ items, total }) => {
          setQueryTotals((prev) => ({ ...prev, [columnId]: total }));
          if (filtered) setQueryTasks((prev) => mergeById(prev ?? [], items));
          else setExtraTasks((prev) => mergeById(prev, items));
        })
        .catch(() => {
          /* leave the column as it was; the next scroll retries */
        })
        .finally(() => {
          inFlightRef.current.delete(columnId);
          setLoading((prev) => ({ ...prev, [columnId]: false }));
        });
    },
    [enabled, filtered, pageSize, fetchPage],
  );

  // Filtered view: every column is re-queried from the server, all in one request. Re-runs when the
  // filters change, when the columns change, and when a cable refresh delivers new props
  // (`baseTasks`) — the board's signal that something on it moved.
  useEffect(() => {
    if (!enabled || !filtered) {
      setQueryTasks(null);
      setQueryTotals(clearedMap);
      return;
    }

    let cancelled = false;
    const targets = columnsRef.current.map((c) => c.id);
    // Ask for as much as the column already showed, so a refresh does not collapse it back to a
    // single page under the user.
    const limits = targets.map((id) => Math.max(pageSize, loadedRef.current[id] ?? 0));

    fetchColumns(targets, limits)
      .then((pages) => {
        if (cancelled) return;
        const byId = new Map(pages.map((page) => [page.boardColumnId, page]));
        setQueryTasks(pages.flatMap((page) => page.tasks));
        setQueryTotals(Object.fromEntries(targets.map((id) => [id, byId.get(id)?.total ?? 0])));
      })
      .catch(() => {
        /* one request answers for every column, so a failure keeps what the board shows instead of emptying it */
      });

    return () => {
      cancelled = true;
    };
  }, [enabled, filtered, filterKey, columnIdsKey, baseTasks, pageSize, fetchColumns]);

  // Unfiltered view: the props carry page one, so only the scrolled-to pages need re-pulling when
  // a cable refresh lands. Columns the user never scrolled cost nothing.
  useEffect(() => {
    if (!enabled || filtered) {
      setExtraTasks(clearedList);
      return;
    }

    const loadedExtras = extraTasksRef.current;
    if (loadedExtras.length === 0) return;

    let cancelled = false;
    const perColumn = countByColumn(loadedExtras);
    const targets = Object.keys(perColumn).map(Number);

    Promise.all(targets.map((id) => fetchPage(id, perColumn[id], pageSize).catch(() => null))).then((pages) => {
      if (cancelled) return;
      setExtraTasks(pages.flatMap((page) => page?.items ?? []));
    });

    return () => {
      cancelled = true;
    };
  }, [enabled, filtered, baseTasks, pageSize, fetchPage]);

  return { tasks, setTasks, pinMove, settleMove, counts, hasMore, loading, loadMore, filtered };
}
