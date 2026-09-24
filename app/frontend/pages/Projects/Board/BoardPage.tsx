import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
  PointerSensor,
  closestCorners,
  pointerWithin,
  useSensor,
  useSensors,
  type CollisionDetection,
} from '@dnd-kit/core';
import { SortableContext, horizontalListSortingStrategy, sortableKeyboardCoordinates } from '@dnd-kit/sortable';
import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Box,
  Button,
  Checkbox,
  Drawer,
  Group,
  Menu,
  Select,
  Text,
  TextInput,
  Textarea,
  Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import {
  IconActivity,
  IconArrowsMaximize,
  IconArrowsMinimize,
  IconAlertCircle,
  IconBolt,
  IconCheck,
  IconCheckbox,
  IconFlag,
  IconLayoutGrid,
  IconListDetails,
  IconPlus,
  IconSearch,
  IconSettings,
  IconUser,
  IconX,
} from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { z } from 'zod';

import type Board from 'types/generated/Board';
import type BoardActivity from 'types/generated/BoardActivity';
import type BoardMember from 'types/generated/BoardMember';
import type BoardPreset from 'types/generated/BoardPreset';
import type BoardTask from 'types/generated/BoardTask';
import type BoardViewPreset from 'types/generated/BoardViewPreset';
import type BoardWorkflow from 'types/generated/BoardWorkflow';
import type Project from 'types/generated/Project';
import type TaskAsset from 'types/generated/TaskAsset';
import type TaskComment from 'types/generated/TaskComment';
import type TaskDetail from 'types/generated/TaskDetail';
import type TaskStatistics from 'types/generated/TaskStatistics';
import type TaskWorkflowRun from 'types/generated/TaskWorkflowRun';

import { apiMutate, apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useLocalStorageSet } from 'shared/lib/hooks/useLocalStorage';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import {
  apiV1ProjectTasksPath,
  apiV1ProjectTaskPath,
  triggerWorkflowApiV1ProjectTaskPath,
  apiV1ProjectColumnsPath,
  apiV1ProjectColumnPath,
  reorderApiV1ProjectColumnsPath,
} from 'shared/routes';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import { ActivityFeedPanel } from './ActivityFeedPanel';
import { BoardColumn } from './BoardColumn';
import styles from './BoardPage.module.css';
import { BoardPresetPicker } from './BoardPresetPicker';
import { BoardSettingsDialog } from './BoardSettingsDialog';
import { SelectionBar } from './SelectionBar';
import { TagFilterCombobox } from './TagFilterCombobox';
import { TaskCardUI } from './TaskCardUI';
import { TaskDetailSidebar } from './TaskDetailSidebar';
import { jsonHeaders, type BoardFilters, type Column, type Task } from './types';
import { useBoardDnd } from './useBoardDnd';
import { useBoardTaskPages } from './useBoardTaskPages';
import { useBulkActions } from './useBulkActions';
import { ViewPresetMenu } from './ViewPresetMenu';

// Props a task-open/close visit needs — everything the sidebar renders, and nothing about
// the board list itself. Passed as Inertia's `only` so opening a card doesn't re-run the
// board/columns/tags/epics/members/workflows/view_presets queries on every click.
const TASK_DETAIL_PROPS = [
  'selected_task',
  'task_comments',
  'task_assets',
  'task_activities',
  'task_workflow_runs',
  'task_statistics',
  'task_cable_stream',
];

interface Props {
  project: Project;
  board: Board | null;
  boardPresets?: BoardPreset[];
  columns: Column[];
  // First page of each column only; the rest arrives through useBoardTaskPages.
  tasks: BoardTask[];
  tasksPageSize?: number;
  // Board-wide filter/picker options, which can no longer be derived from `tasks`.
  boardTags?: string[];
  epics?: Array<{ id: number; title: string }>;
  members: BoardMember[];
  workflows: BoardWorkflow[];
  viewPresets?: BoardViewPreset[];
  currentUserId?: number;
  cableStream?: string;
  taskCableStream?: string | null;
  recentActivities?: BoardActivity[];
  selectedTask?: TaskDetail | null;
  taskComments?: TaskComment[];
  taskAssets?: TaskAsset[];
  taskActivities?: BoardActivity[];
  taskWorkflowRuns?: TaskWorkflowRun[];
  taskStatistics?: TaskStatistics | null;
  [key: string]: unknown;
}

const EMPTY_FILTERS: BoardFilters = {
  assigneeId: null,
  taskType: null,
  priority: null,
  tags: [],
  search: '',
  showArchived: false,
};

const taskSchema = z.object({
  title: z.string().min(1, 'Title is required'),
  description: z.string().optional(),
  taskType: z.string().optional(),
  priority: z.string().optional(),
  assigneeId: z.string().nullable().optional(),
  parentTaskId: z.string().nullable().optional(),
  boardColumnId: z.string().min(1, 'Column is required'),
});

type TaskFormValues = z.infer<typeof taskSchema>;

function normalizeTask(t: Task): Task {
  return {
    ...t,
    title: t.title ?? '',
    tags: t.tags ?? [],
    archived: t.archived ?? false,
    pendingGates: t.pendingGates ?? [],
    ciGates: t.ciGates ?? [],
    recentWorkflowRuns: t.recentWorkflowRuns ?? [],
    assetsCount: t.assetsCount ?? 0,
    childrenCount: t.childrenCount ?? 0,
    commentsCount: t.commentsCount ?? 0,
  };
}

// Mirrors BoardTask::PAGE_SIZE. Only used when the prop is missing (a partial reload of a page
// rendered before the prop existed) — the server's value wins.
const DEFAULT_TASKS_PAGE_SIZE = 25;

// Stable fallbacks: useBoardTaskPages keys its work off array identity, so a fresh `[]` per render
// would have it re-derive its state on every render for nothing.
const NO_TASKS: Task[] = [];
const NO_COLUMNS: Column[] = [];
const NO_EPICS: Array<{ id: number; title: string }> = [];

const BoardPage = () => {
  const {
    project,
    board,
    boardPresets,
    columns,
    tasks: serverTasks,
    tasksPageSize,
    boardTags,
    epics,
    members,
    viewPresets,
    currentUserId,
    cableStream,
    taskCableStream,
    recentActivities,
    selectedTask: selectedTaskProp,
    taskComments,
    taskAssets: taskAssetsProp,
    taskActivities,
    taskWorkflowRuns,
    taskStatistics,
  } = usePage<Props>().props;
  const { canExecute } = useProjectPermissions();

  const [filters, setFilters] = useState<BoardFilters>(EMPTY_FILTERS);

  // Typing must not fire a request per keystroke now that search runs server-side.
  const [debouncedSearch] = useDebouncedValue(filters.search, 300);
  const serverFilters = useMemo(() => ({ ...filters, search: debouncedSearch }), [filters, debouncedSearch]);

  // Columns load a page at a time: the props carry the first page of each, this hook fetches the
  // rest as columns are scrolled, and re-queries the board server-side whenever a filter is on
  // (including "Show archived", which is how archived tasks reach the board at all).
  const {
    tasks: localTasks,
    setTasks: setLocalTasks,
    counts: columnCounts,
    hasMore: columnHasMore,
    loading: columnLoading,
    loadMore: loadMoreColumn,
  } = useBoardTaskPages<Task>({
    projectId: project.id,
    enabled: !!board,
    columns: columns ?? NO_COLUMNS,
    initialTasks: serverTasks ?? NO_TASKS,
    pageSize: tasksPageSize ?? DEFAULT_TASKS_PAGE_SIZE,
    filters: serverFilters,
    normalize: normalizeTask,
  });

  const [localColumns, setLocalColumns] = useState<Column[]>(() => columns ?? []);
  useEffect(() => {
    setLocalColumns(columns ?? []);
  }, [columns]);

  const selectedTask = selectedTaskProp ? normalizeTask(selectedTaskProp) : null;

  // Sync the updated selectedTask into localTasks after partial reloads that only refresh
  // the selected task (e.g. editing fields, triggering a workflow, removing a wait).
  // Without this, task cards in the board columns would show stale data until the next
  // full-tasks reload.
  useEffect(() => {
    if (!selectedTaskProp) return;

    const nextTask = normalizeTask(selectedTaskProp);

    setLocalTasks((prev) => prev.map((t) => (t.id === nextTask.id ? nextTask : t)));
  }, [selectedTaskProp, setLocalTasks]);

  const boardUrl = `/company/projects/${project.id}/board`;

  useInertiaCableStream(cableStream, {
    only: ['tasks', 'columns', 'recent_activities'],
    enabled: !!board,
  });

  useInertiaCableStream(taskCableStream ?? undefined, {
    only: ['selected_task', 'task_comments', 'task_assets', 'task_activities', 'task_workflow_runs', 'task_statistics'],
    enabled: !!selectedTaskProp,
  });

  const [createOpen, setCreateOpen] = useState(false);
  const [activityOpen, setActivityOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const collapsedColumnsStorageKey = board ? `board:${board.id}:collapsedColumns` : null;
  const [collapsedColumns, setCollapsedColumns] = useLocalStorageSet<number>(collapsedColumnsStorageKey, new Set());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  // Explicit bulk-selection mode. Off by default: the board stays click-to-open / drag until the
  // user arms it from the "Bulk" toolbar button, so hovering a dense column never reveals or
  // reflows a checkbox (issue #581).
  const [bulkMode, setBulkMode] = useState(false);

  const toggleSelect = useCallback((id: number, checked: boolean) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (checked) next.add(id);
      else next.delete(id);
      return next;
    });
  }, []);

  const clearSelection = useCallback(() => setSelectedIds(new Set()), []);

  // Leaving bulk mode always drops the selection — a checkbox left checked under a board that no
  // longer shows checkboxes would be invisible state.
  const exitBulkMode = useCallback(() => {
    setBulkMode(false);
    setSelectedIds(new Set());
  }, []);

  const toggleBulkMode = useCallback(() => {
    setBulkMode((on) => {
      if (on) setSelectedIds(new Set());
      return !on;
    });
  }, []);

  const {
    execute: executeBulkAction,
    bulkSetPriority,
    bulkAssign,
    bulkAddTag,
  } = useBulkActions({
    projectId: project.id,
    onSuccess: clearSelection,
  });

  const toggleColumn = useCallback((_columnId: number, taskIds: number[], select: boolean) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      for (const id of taskIds) {
        if (select) next.add(id);
        else next.delete(id);
      }
      return next;
    });
  }, []);

  // The task id a click just requested but whose props haven't landed yet — drives the sidebar
  // skeleton below. Cleared on the request's own `onFinish`, guarded by id so a stale response
  // for an already-superseded click can't clear a newer one's pending state.
  const [pendingTaskId, setPendingTaskId] = useState<number | null>(null);

  // Opening by id, for a task the board may not hold a card for — an epic's child or parent that
  // lives on a page no column has loaded.
  //
  // Scoped to just the selected task's own props: the board list, columns, tags, epics,
  // members, etc. don't move when a card is opened or closed. Without this `only`, every
  // click re-ran the full board query set (issue #563).
  const openTaskById = useCallback(
    (taskId: number) => {
      setPendingTaskId(taskId);
      router.get(
        boardUrl,
        { task: taskId },
        {
          preserveState: true,
          preserveScroll: true,
          only: TASK_DETAIL_PROPS,
          onFinish: () => setPendingTaskId((id) => (id === taskId ? null : id)),
        },
      );
    },
    [boardUrl],
  );

  const openTask = useCallback(
    (task: Task | null) => {
      const taskId = task?.id ?? null;
      setPendingTaskId(taskId);
      router.get(
        boardUrl,
        { task: taskId },
        {
          preserveState: true,
          preserveScroll: true,
          only: TASK_DETAIL_PROPS,
          onFinish: () => setPendingTaskId((id) => (id === taskId ? null : id)),
        },
      );
    },
    [boardUrl],
  );

  // URL each task card links to. Kept in sync with openTask so a plain click and
  // "open in new tab" land on the same task detail view.
  const taskHref = useCallback((task: Task) => `${boardUrl}?task=${task.id}`, [boardUrl]);

  const closeTask = useCallback(() => {
    setPendingTaskId(null);
    router.get(boardUrl, {}, { preserveState: true, preserveScroll: true, only: TASK_DETAIL_PROPS });
  }, [boardUrl]);

  const pointerSensor = useSensor(PointerSensor, { activationConstraint: { distance: 8 } });
  // Dropping a card into an automated column is how a workflow gets started, so
  // a pointer-only board meant keyboard and screen-reader users could not run
  // one at all. Space/Enter picks a card up, arrows move it, Space drops it.
  const keyboardSensor = useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates });
  // Viewers cannot reorder/move tasks: register no sensors so drag never activates.
  const sensors = useSensors(...(canExecute ? [pointerSensor, keyboardSensor] : []));

  const collisionDetection = useCallback<CollisionDetection>((args) => {
    const pw = pointerWithin(args);
    if (pw.length > 0) return pw;
    return closestCorners(args);
  }, []);

  const hasActiveFilters = !!(
    filters.assigneeId ||
    filters.taskType ||
    filters.priority ||
    filters.tags.length > 0 ||
    filters.search
  );

  // Every tag on the board, not only the tags of the loaded pages — otherwise a filter could not
  // reach a tag that only exists further down a column.
  const allTags = useMemo(() => [...(boardTags ?? [])].sort(), [boardTags]);

  // Shared by the toolbar combobox and the tag chips on cards, so both paths add and remove the
  // same filter entry — clicking a tag twice (anywhere) clears it.
  const toggleTagFilter = useCallback((tag: string) => {
    setFilters((f) => ({
      ...f,
      tags: f.tags.includes(tag) ? f.tags.filter((t) => t !== tag) : [...f.tags, tag],
    }));
  }, []);

  const clearTagFilter = useCallback(() => setFilters((f) => ({ ...f, tags: [] })), []);

  // Filtering itself is server-side (see useBoardTaskPages); the loaded tasks only need bucketing.
  const tasksByColumn = useMemo(() => {
    const map: Record<number, Task[]> = {};
    for (const col of columns) map[col.id] = [];
    for (const task of localTasks) {
      if (map[task.boardColumnId]) map[task.boardColumnId].push(task);
    }
    for (const col of columns) map[col.id].sort((a, b) => a.position - b.position);
    return map;
  }, [columns, localTasks]);

  const form = useForm<TaskFormValues>({
    validate: zodResolver(taskSchema),
    initialValues: {
      title: '',
      description: '',
      taskType: 'not_specified',
      priority: '',
      assigneeId: null,
      parentTaskId: null,
      boardColumnId: '',
    },
  });

  // Epics available as a parent in the create drawer. Nesting is one level deep, so an epic
  // itself never gets a parent — the field is hidden when Type is Epic (see below). The list comes
  // from the board rather than the loaded tasks, which hold only a page per column.
  const epicOptions = useMemo(() => (epics ?? []).map((e) => ({ value: String(e.id), label: e.title })), [epics]);

  const handleCreateTask = useCallback(
    async (values: TaskFormValues) => {
      if (!board) return;
      setLoading(true);
      try {
        const isEpic = (values.taskType || 'not_specified') === 'epic';
        const created = await apiRequest<BoardTask>(apiV1ProjectTasksPath(project.id), {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            boardTask: {
              title: values.title,
              description: values.description,
              taskType: values.taskType || 'not_specified',
              priority: values.priority || null,
              assigneeId: values.assigneeId ? Number(values.assigneeId) : null,
              parentTaskId: !isEpic && values.parentTaskId ? Number(values.parentTaskId) : null,
              boardColumnId: Number(values.boardColumnId),
            },
          }),
        });
        setCreateOpen(false);
        form.reset();
        setLocalTasks((prev) => [...prev, normalizeTask(created)]);
        // cable will confirm with authoritative server state
      } catch (error) {
        notifyApiFailure(error, 'The task was not created');
      }
      setLoading(false);
    },
    [board, project.id, form, setLocalTasks],
  );

  const handleDeleteTask = useCallback(
    async (taskId: number) => {
      if (await apiMutate(apiV1ProjectTaskPath(project.id, taskId), { method: 'DELETE' })) closeTask();
    },
    [project.id, closeTask],
  );

  // Drag-and-drop (task moves + column reorder) lives in useBoardDnd so its behaviour is
  // testable without element geometry, which jsdom cannot provide for dnd-kit's sensors.
  const { activeTask, hoverColumnId, handleDragStart, handleDragOver, handleDragEnd } = useBoardDnd({
    projectId: project.id,
    enabled: !!board,
    tasks: localTasks,
    setTasks: setLocalTasks,
    columns: localColumns,
    setColumns: setLocalColumns,
  });

  const openCreateForColumn = (columnId: number) => {
    form.setFieldValue('boardColumnId', String(columnId));
    setCreateOpen(true);
  };

  const handleToggleCollapse = useCallback(
    (colId: number) => {
      setCollapsedColumns((prev) => {
        const next = new Set(prev);
        if (next.has(colId)) next.delete(colId);
        else next.add(colId);
        return next;
      });
    },
    [setCollapsedColumns],
  );

  const handleToggleAll = useCallback(() => {
    // Drive the id list off localColumns — it is the live list (reorders, renames and freshly
    // added columns land there first), so the `columns` prop can lag behind it.
    const allIds = localColumns.map((c) => c.id);
    setCollapsedColumns((prev) => (prev.size === allIds.length ? new Set() : new Set(allIds)));
  }, [localColumns, setCollapsedColumns]);

  // Whether every column is currently collapsed — drives the Collapse all / Expand all toggle
  // and the compact "add column" strip.
  const allColumnsCollapsed = localColumns.length > 0 && localColumns.every((c) => collapsedColumns.has(c.id));

  const handleRetryTask = useCallback(
    async (task: Task) => {
      const retried = await apiMutate(triggerWorkflowApiV1ProjectTaskPath(project.id, task.id), {
        method: 'POST',
        headers: jsonHeaders,
      });
      if (retried) router.reload({ only: ['tasks', 'selected_task', 'task_workflow_runs'] });
    },
    [project.id, jsonHeaders],
  );

  const handleRenameColumn = useCallback(
    async (columnId: number, name: string) => {
      await apiMutate(apiV1ProjectColumnPath(project.id, columnId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({ boardColumn: { name } }),
      });
      router.reload({ only: ['columns'] });
    },
    [project.id],
  );

  const handleDeleteColumn = useCallback(
    (columnId: number) => {
      modals.openConfirmModal({
        title: 'Delete column',
        children: <Text size="sm">Tasks inside will be moved to the first column. This action cannot be undone.</Text>,
        labels: { confirm: 'Delete', cancel: 'Cancel' },
        confirmProps: { color: 'red' },
        onConfirm: async () => {
          await apiMutate(apiV1ProjectColumnPath(project.id, columnId), { method: 'DELETE' });
          router.reload({ only: ['columns', 'tasks'] });
        },
      });
    },
    [project.id],
  );

  const handleAddColumnInline = useCallback(async () => {
    try {
      // Append the created column straight from the response instead of reloading the
      // `columns` prop: a reload fired here is an async Inertia partial reload with no
      // ordering guarantee against another one, so it can race a column-reorder reload
      // fired moments later (e.g. the user immediately drags the new column) and land
      // second, clobbering the persisted reorder with this stale, pre-drag order (#580).
      const created = await apiRequest<Column>(apiV1ProjectColumnsPath(project.id), {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ boardColumn: { name: 'New column' } }),
      });
      setLocalColumns((prev) => [...prev, created]);
    } catch (error) {
      notifyApiFailure(error, 'The column was not created');
    }
  }, [project.id]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (e.target as HTMLElement)?.isContentEditable)
        return;

      if (e.key === 'n' && !e.ctrlKey && !e.metaKey) {
        if (!canExecute) return;
        e.preventDefault();
        setCreateOpen(true);
      } else if (e.key === '/' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        searchInputRef.current?.focus();
      } else if (e.key === 'Escape') {
        if (bulkMode) {
          exitBulkMode();
          return;
        }
        closeTask();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [closeTask, canExecute, bulkMode, exitBulkMode]);

  if (!board) {
    return (
      <>
        <Head title={`Board — ${project.name}`} />
        <BoardPresetPicker projectId={project.id} presets={boardPresets ?? []} />
      </>
    );
  }

  return (
    <>
      <Head title={`Board — ${project.name}`} />
      <Box className={styles.boardRoot}>
        {/* Page header */}
        <PageHeader
          title="Tasks"
          subtitle="Plan manual and agent work side by side — drop a task into an automated column to run its workflow, and track every run's progress, status, and cost right on the card."
          mb={16}
        />

        {/* Filter toolbar. `wrap` matters: with nowrap, nine controls squeezed
            into 390px and every button label got clipped to an empty pill. */}
        <Group gap={6} mb="sm" wrap="wrap" align="center">
          {/* Search */}
          <TextInput
            ref={searchInputRef}
            placeholder="Search tasks"
            aria-label="Search tasks"
            leftSection={<IconSearch size={12} />}
            value={filters.search}
            onChange={(e) => {
              // Capture before the functional updater — see the Archived toggle below.
              const search = e.currentTarget.value;
              setFilters((f) => ({ ...f, search }));
            }}
            size="xs"
            w={{ base: '100%', xs: 180 }}
          />

          {/* Presets */}
          <ViewPresetMenu
            projectId={project.id}
            viewPresets={viewPresets ?? []}
            currentUserId={currentUserId ?? 0}
            filters={filters}
            onApplyFilters={setFilters}
          />

          {/* Assignee */}
          <Menu shadow="md" width={180} position="bottom-start">
            <Menu.Target>
              <Button
                variant="default"
                size="xs"
                leftSection={<IconUser size={12} />}
                styles={{
                  root: {
                    fontWeight: 400,
                    color: filters.assigneeId ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
                  },
                }}
              >
                Assignee:{' '}
                {filters.assigneeId
                  ? (members.find((m) => String(m.id) === filters.assigneeId)?.name ?? 'Unknown')
                  : 'All'}
              </Button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Item onClick={() => setFilters((f) => ({ ...f, assigneeId: null }))}>All</Menu.Item>
              {members.map((m) => (
                <Menu.Item
                  key={m.id}
                  onClick={() => setFilters((f) => ({ ...f, assigneeId: String(m.id) }))}
                  fw={filters.assigneeId === String(m.id) ? 600 : 400}
                >
                  {m.name}
                </Menu.Item>
              ))}
            </Menu.Dropdown>
          </Menu>

          {/* Type */}
          <Menu shadow="md" width={160} position="bottom-start">
            <Menu.Target>
              <Button
                variant="default"
                size="xs"
                leftSection={<IconLayoutGrid size={12} />}
                styles={{
                  root: {
                    fontWeight: 400,
                    color: filters.taskType ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
                  },
                }}
              >
                Type: {filters.taskType ? filters.taskType.charAt(0).toUpperCase() + filters.taskType.slice(1) : 'All'}
              </Button>
            </Menu.Target>
            <Menu.Dropdown>
              {[
                { value: null, label: 'All' },
                { value: 'epic', label: 'Epic' },
                { value: 'story', label: 'Story' },
                { value: 'bug', label: 'Bug' },
              ].map(({ value, label }) => (
                <Menu.Item
                  key={label}
                  onClick={() => setFilters((f) => ({ ...f, taskType: value }))}
                  fw={filters.taskType === value ? 600 : 400}
                >
                  {label}
                </Menu.Item>
              ))}
            </Menu.Dropdown>
          </Menu>

          {/* Priority */}
          <Menu shadow="md" width={160} position="bottom-start">
            <Menu.Target>
              <Button
                variant="default"
                size="xs"
                leftSection={<IconFlag size={12} />}
                styles={{
                  root: {
                    fontWeight: 400,
                    color: filters.priority ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
                  },
                }}
              >
                Priority:{' '}
                {filters.priority ? filters.priority.charAt(0).toUpperCase() + filters.priority.slice(1) : 'All'}
              </Button>
            </Menu.Target>
            <Menu.Dropdown>
              {[
                { value: null, label: 'All' },
                { value: 'critical', label: 'Critical' },
                { value: 'high', label: 'High' },
                { value: 'medium', label: 'Medium' },
                { value: 'low', label: 'Low' },
              ].map(({ value, label }) => (
                <Menu.Item
                  key={label}
                  onClick={() => setFilters((f) => ({ ...f, priority: value }))}
                  fw={filters.priority === value ? 600 : 400}
                >
                  {label}
                </Menu.Item>
              ))}
            </Menu.Dropdown>
          </Menu>

          {/* Tags — only when there are tags */}
          {allTags.length > 0 && (
            <TagFilterCombobox
              allTags={allTags}
              selected={filters.tags}
              onToggle={toggleTagFilter}
              onClear={clearTagFilter}
            />
          )}

          {/* Show archived toggle */}
          <Checkbox
            label="Archived"
            size="xs"
            checked={filters.showArchived}
            onChange={(e) => {
              // Read the event synchronously — the functional updater below runs
              // after React has recycled the synthetic event, so reading
              // e.currentTarget inside it would throw on a null target.
              const checked = e.currentTarget.checked;
              setFilters((f) => ({ ...f, showArchived: checked }));
            }}
          />

          {/* Clear active filters */}
          {(hasActiveFilters || filters.showArchived) && (
            <ActionIcon
              variant="subtle"
              size="sm"
              color="gray"
              aria-label="Clear filters"
              onClick={() => setFilters(EMPTY_FILTERS)}
            >
              <IconX size={12} />
            </ActionIcon>
          )}

          <Box style={{ flex: 1 }} />

          {/* Bulk — arms explicit selection mode. Hidden for view-only members, who get no
              selection affordance at all (issue #581). */}
          {canExecute && (
            <Button
              variant="default"
              size="xs"
              leftSection={bulkMode ? <IconCheck size={12} /> : <IconCheckbox size={12} />}
              onClick={toggleBulkMode}
              styles={
                bulkMode
                  ? {
                      root: {
                        backgroundColor: 'var(--mantine-color-brand-light)',
                        color: 'var(--mantine-color-brand-6)',
                        borderColor: 'var(--mantine-color-brand-light-hover)',
                      },
                    }
                  : undefined
              }
            >
              {bulkMode ? 'Done' : 'Bulk'}
            </Button>
          )}

          {/* Collapse all */}
          <Button
            variant="default"
            size="xs"
            leftSection={allColumnsCollapsed ? <IconArrowsMaximize size={12} /> : <IconArrowsMinimize size={12} />}
            onClick={handleToggleAll}
          >
            {allColumnsCollapsed ? 'Expand all' : 'Collapse all'}
          </Button>

          {/* Activity */}
          <Button
            variant="default"
            size="xs"
            leftSection={<IconActivity size={12} />}
            onClick={() => setActivityOpen(true)}
          >
            Activity
          </Button>

          {/* Board settings — the only entry point to BoardSettingsDialog */}
          {canExecute && (
            <Tooltip label="Board settings">
              <ActionIcon variant="subtle" size="sm" aria-label="Board settings" onClick={() => setSettingsOpen(true)}>
                <IconSettings size={16} />
              </ActionIcon>
            </Tooltip>
          )}
        </Group>

        {/* Selection toolbar — second row, visible only when tasks are selected */}
        <SelectionBar
          active={bulkMode}
          selectedCount={selectedIds.size}
          selectedIds={selectedIds}
          columns={localColumns}
          members={members}
          canExecute={canExecute}
          onAction={(action, columnId) => executeBulkAction(action, [...selectedIds], columnId)}
          onBulkPriority={(priority) => bulkSetPriority([...selectedIds], priority)}
          onBulkAssign={(assigneeId) => bulkAssign([...selectedIds], assigneeId)}
          onBulkTag={(tag) => bulkAddTag([...selectedIds], tag)}
          onClear={clearSelection}
        />

        {/* Board area */}
        <DndContext
          sensors={sensors}
          collisionDetection={collisionDetection}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
        >
          <Box className={styles.boardArea}>
            <SortableContext items={localColumns.map((c) => `col-${c.id}`)} strategy={horizontalListSortingStrategy}>
              {/*
                A collapsed column still renders its tickets as compact draggable chips, so tickets
                can always be dragged out to another column instead of being trapped there.
              */}
              {localColumns.map((col, idx) => (
                <BoardColumn
                  key={col.id}
                  column={col}
                  tasks={tasksByColumn[col.id] ?? []}
                  totalCount={columnCounts[col.id] ?? (tasksByColumn[col.id] ?? []).length}
                  hasMore={columnHasMore[col.id] ?? false}
                  loadingMore={columnLoading[col.id] ?? false}
                  onLoadMore={loadMoreColumn}
                  taskHref={taskHref}
                  onAddTask={openCreateForColumn}
                  onTaskClick={openTask}
                  onRetryTask={handleRetryTask}
                  onTagClick={toggleTagFilter}
                  activeTags={filters.tags}
                  collapsed={collapsedColumns.has(col.id)}
                  onToggleCollapse={handleToggleCollapse}
                  onMoveLeft={
                    idx > 0
                      ? () => {
                          const reordered = [...localColumns];
                          [reordered[idx - 1], reordered[idx]] = [reordered[idx], reordered[idx - 1]];
                          setLocalColumns(reordered);
                          // No follow-up reload: the optimistic order above already matches what
                          // gets persisted, and a reload here could race another in-flight one
                          // and clobber it with stale data (#580) — see useBoardDnd's column
                          // reorder for the full explanation.
                          void apiMutate(reorderApiV1ProjectColumnsPath(project.id), {
                            method: 'PATCH',
                            headers: jsonHeaders,
                            body: JSON.stringify({ columnIds: reordered.map((c) => c.id) }),
                          }).then((saved) => {
                            if (!saved) setLocalColumns(localColumns);
                          });
                        }
                      : undefined
                  }
                  onMoveRight={
                    idx < localColumns.length - 1
                      ? () => {
                          const reordered = [...localColumns];
                          [reordered[idx], reordered[idx + 1]] = [reordered[idx + 1], reordered[idx]];
                          setLocalColumns(reordered);
                          void apiMutate(reorderApiV1ProjectColumnsPath(project.id), {
                            method: 'PATCH',
                            headers: jsonHeaders,
                            body: JSON.stringify({ columnIds: reordered.map((c) => c.id) }),
                          }).then((saved) => {
                            if (!saved) setLocalColumns(localColumns);
                          });
                        }
                      : undefined
                  }
                  onDeleteColumn={() => handleDeleteColumn(col.id)}
                  onRenameColumn={handleRenameColumn}
                  isFiltered={hasActiveFilters}
                  isDropTarget={hoverColumnId === col.id}
                  canExecute={canExecute}
                  selectedIds={selectedIds}
                  onToggleSelect={canExecute && bulkMode ? toggleSelect : undefined}
                  onToggleColumn={canExecute && bulkMode ? toggleColumn : undefined}
                  selectionMode={canExecute && bulkMode}
                />
              ))}
            </SortableContext>

            {/* Add column button — vertical strip once the board has columns, pill on an empty board */}
            {localColumns.length > 0 ? (
              <Box
                onClick={handleAddColumnInline}
                className={styles.addColumnBtn}
                data-testid="add-column-control"
                data-orientation="vertical"
                style={{
                  flex: '0 0 46px',
                  minWidth: 46,
                  maxWidth: 46,
                  alignSelf: 'stretch',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'flex-start',
                  gap: 10,
                  padding: '12px 0',
                }}
              >
                <IconPlus size={15} />
                <div
                  style={{
                    writingMode: 'vertical-rl',
                    fontSize: 13,
                    fontWeight: 500,
                    userSelect: 'none',
                  }}
                >
                  Add column
                </div>
              </Box>
            ) : (
              <Box
                onClick={handleAddColumnInline}
                className={styles.addColumnBtn}
                data-testid="add-column-control"
                data-orientation="horizontal"
                style={{
                  flex: '0 0 220px',
                  minWidth: 220,
                  alignSelf: 'flex-start',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 6,
                  height: 44,
                  fontSize: 13,
                  fontWeight: 500,
                }}
              >
                <IconPlus size={15} />
                Add column
              </Box>
            )}
          </Box>
          <DragOverlay dropAnimation={{ duration: 200, easing: 'cubic-bezier(0.25, 1, 0.5, 1)' }}>
            {activeTask ? (
              <Box w={280} style={{ transform: 'rotate(2deg)', filter: 'drop-shadow(0 8px 16px rgba(0,0,0,0.3))' }}>
                <TaskCardUI task={activeTask} isDragOverlay />
              </Box>
            ) : null}
          </DragOverlay>
        </DndContext>

        <ActivityFeedPanel
          projectId={project.id}
          initialActivities={recentActivities ?? []}
          opened={activityOpen}
          onClose={() => setActivityOpen(false)}
        />
      </Box>

      <TaskDetailSidebar
        task={selectedTask}
        pendingTaskId={pendingTaskId}
        allTasks={localTasks}
        epics={epics ?? NO_EPICS}
        knownTags={allTags}
        onClose={closeTask}
        onDelete={handleDeleteTask}
        onOpenTaskId={openTaskById}
        projectId={project.id}
        columns={columns}
        members={members}
        comments={taskComments ?? []}
        activities={taskActivities ?? []}
        taskAssets={taskAssetsProp ?? []}
        workflowRuns={taskWorkflowRuns ?? []}
        stats={taskStatistics ?? null}
        canExecute={canExecute}
      />
      <BoardSettingsDialog
        opened={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        projectId={project.id}
        columns={columns}
      />

      {/* Create Task Drawer (AC-15) */}
      <Drawer
        opened={canExecute && createOpen}
        onClose={() => {
          setCreateOpen(false);
          form.reset();
        }}
        position="right"
        size={620}
        withCloseButton
        title={
          <Text fw={600} size="sm" style={{ letterSpacing: '-0.01em' }}>
            Create task
          </Text>
        }
        styles={{
          header: { borderBottom: '1px solid var(--app-border-default)', padding: '12px 16px' },
          body: { padding: 0, display: 'flex', flexDirection: 'column', height: 'calc(100% - 53px)' },
        }}
      >
        <form
          onSubmit={form.onSubmit(handleCreateTask)}
          style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}
        >
          {/* Scrollable body */}
          <Box style={{ flex: 1, overflowY: 'auto', padding: 20, display: 'flex', flexDirection: 'column', gap: 14 }}>
            {/* Title — large ghost input */}
            <Box>
              <TextInput
                placeholder="Task title"
                required
                {...form.getInputProps('title')}
                styles={{
                  input: {
                    fontSize: 19,
                    fontWeight: 700,
                    letterSpacing: '-0.02em',
                    padding: '2px 8px',
                    marginLeft: -8,
                    background: 'transparent',
                    border: '1px solid transparent',
                    borderRadius: 5,
                    color: 'var(--mantine-color-text)',
                    transition: 'border-color .12s, background .12s',
                  },
                  wrapper: { marginBottom: form.errors.title ? 4 : 0 },
                }}
                variant="unstyled"
              />
              {form.errors.title && (
                <Text size="xs" c="var(--app-danger-fg)" style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                  <IconAlertCircle size={13} /> {form.errors.title}
                </Text>
              )}
            </Box>

            {/* Description */}
            <Textarea
              placeholder="Add a description…"
              autosize
              minRows={2}
              styles={{
                input: {
                  background: 'transparent',
                  borderColor: 'transparent',
                  padding: '6px 8px',
                  marginLeft: -8,
                  fontSize: 14,
                  lineHeight: 1.6,
                  resize: 'vertical',
                  minHeight: 60,
                  transition: 'border-color .12s, background .12s',
                },
              }}
              variant="unstyled"
              {...form.getInputProps('description')}
            />

            {/* Properties section */}
            <Box>
              <Box
                style={{
                  fontSize: 12,
                  fontWeight: 600,
                  letterSpacing: '0.04em',
                  textTransform: 'uppercase',
                  color: 'var(--mantine-color-dimmed)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  paddingBottom: 10,
                  borderBottom: '1px solid var(--app-border-default)',
                  marginBottom: 14,
                }}
              >
                <IconListDetails size={14} color="var(--app-primary-strong)" />
                Properties
              </Box>

              {/* Props grid */}
              <Box
                style={{
                  display: 'grid',
                  gridTemplateColumns: '92px 1fr',
                  gap: '10px 12px',
                  padding: '4px 0 14px',
                  alignItems: 'center',
                }}
              >
                <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                  Column
                </Text>
                <Select
                  data={columns.map((c) => ({ value: String(c.id), label: c.name }))}
                  required
                  size="xs"
                  variant="unstyled"
                  styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                  {...form.getInputProps('boardColumnId')}
                />

                <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                  Type
                </Text>
                <Select
                  data={[
                    { value: 'not_specified', label: 'Not specified' },
                    { value: 'epic', label: 'Epic' },
                    { value: 'story', label: 'Story' },
                    { value: 'bug', label: 'Bug' },
                  ]}
                  aria-label="Type"
                  size="xs"
                  variant="unstyled"
                  styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                  {...form.getInputProps('taskType')}
                  onChange={(v) => {
                    form.setFieldValue('taskType', v ?? 'not_specified');
                    // Nesting is one level deep, so an epic can never have a parent epic.
                    if (v === 'epic') form.setFieldValue('parentTaskId', null);
                  }}
                />

                <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                  Priority
                </Text>
                <Select
                  data={[
                    { value: '', label: 'None' },
                    { value: 'critical', label: 'Critical' },
                    { value: 'high', label: 'High' },
                    { value: 'medium', label: 'Medium' },
                    { value: 'low', label: 'Low' },
                  ]}
                  clearable
                  size="xs"
                  variant="unstyled"
                  styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                  {...form.getInputProps('priority')}
                />

                <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                  Assignee
                </Text>
                <Select
                  data={members.map((m) => ({ value: String(m.id), label: m.name }))}
                  clearable
                  searchable
                  size="xs"
                  variant="unstyled"
                  styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                  {...form.getInputProps('assigneeId')}
                />

                {/* Parent epic — a new task can be attached to an epic on creation. Hidden when
                    the new task is itself an epic (one level of nesting only). */}
                {form.values.taskType !== 'epic' && epicOptions.length > 0 && (
                  <>
                    <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                      Parent Epic
                    </Text>
                    <Select
                      data={epicOptions}
                      aria-label="Parent Epic"
                      placeholder="No epic"
                      clearable
                      searchable
                      size="xs"
                      variant="unstyled"
                      styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                      {...form.getInputProps('parentTaskId')}
                    />
                  </>
                )}
              </Box>

              {/* Automation note (AC-17) */}
              {(() => {
                const selColId = form.values.boardColumnId;
                const selCol = selColId ? columns.find((c) => String(c.id) === selColId) : null;
                if (!selCol?.workflowBinding) return null;
                return (
                  <Box
                    style={{
                      display: 'flex',
                      alignItems: 'flex-start',
                      gap: 8,
                      marginTop: 4,
                      padding: '10px 12px',
                      borderLeft: '2px solid var(--app-primary)',
                      background: 'var(--mantine-color-brand-light)',
                      borderRadius: '0 5px 5px 0',
                      fontSize: 12,
                      color: 'var(--mantine-color-dimmed)',
                    }}
                  >
                    <IconBolt size={14} color="var(--app-primary-strong)" style={{ marginTop: 1, flexShrink: 0 }} />
                    <Text size="xs">
                      Placing this in <strong style={{ color: 'var(--mantine-color-text)' }}>{selCol.name}</strong> will
                      run the{' '}
                      <strong style={{ color: 'var(--mantine-color-text)' }}>
                        {selCol.workflowBinding.workflowName ?? 'workflow'}
                      </strong>{' '}
                      workflow on entry.
                    </Text>
                  </Box>
                );
              })()}
            </Box>
          </Box>

          {/* Footer */}
          <Group
            justify="flex-end"
            gap={8}
            style={{
              padding: '12px 20px',
              borderTop: '1px solid var(--app-border-default)',
              background: 'var(--app-bg-elevated)',
              flexShrink: 0,
            }}
          >
            <Button
              variant="default"
              size="sm"
              onClick={() => {
                setCreateOpen(false);
                form.reset();
              }}
            >
              Cancel
            </Button>
            <Button type="submit" size="sm" loading={loading}>
              Create task
            </Button>
          </Group>
        </form>
      </Drawer>
    </>
  );
};

setPageLayout(BoardPage, persistentProjectLayout);

export default BoardPage;
