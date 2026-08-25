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
}

interface PagedColumn {
  id: number;
  /** Total active tasks in the column, from the board props (BoardColumnResource#tasks_count). */
  tasksCount?: number;
}

export interface BoardTaskFilters {
  search: string;
  assigneeId: string | null;
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

interface UseBoardTaskPagesResult<T extends PagedTask> {
  /** Every task the client holds, flat. Optimistic updates (drag, create) write here. */
  tasks: T[];
  setTasks: Dispatch<SetStateAction<T[]>>;
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

/** Server-side spelling of the board filters. Empty when nothing is filtered. */
export function boardFilterParams(filters: BoardTaskFilters): URLSearchParams {
  const params = new URLSearchParams();
  // Plain attribute filters go through ransack (BoardTask.ransackable_attributes).
  if (filters.search) params.set('q[title_cont]', filters.search);
  if (filters.assigneeId) params.set('q[assignee_id_eq]', filters.assigneeId);
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

  // Rendering and drag-and-drop read this copy, which optimistic updates mutate in place; the
  // server-derived list above replaces it whenever fresh data lands.
  const [tasks, setTasks] = useState<T[]>(merged);
  useEffect(() => setTasks((prev) => (sameTasks(prev, merged) ? prev : merged)), [merged]);

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

  // Filtered view: every column is re-queried from the server. Re-runs when the filters change,
  // when the columns change, and when a cable refresh delivers new props (`baseTasks`) — the
  // board's signal that something on it moved.
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

    Promise.all(targets.map((id, i) => fetchPage(id, limits[i], 0).catch(() => null))).then((pages) => {
      if (cancelled) return;
      setQueryTasks(pages.flatMap((page) => page?.items ?? []));
      setQueryTotals(Object.fromEntries(targets.map((id, i) => [id, pages[i]?.total ?? 0])));
    });

    return () => {
      cancelled = true;
    };
  }, [enabled, filtered, filterKey, columnIdsKey, baseTasks, pageSize, fetchPage]);

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

  return { tasks, setTasks, counts, hasMore, loading, loadMore, filtered };
}
