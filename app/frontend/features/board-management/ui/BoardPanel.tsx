import {
  DndContext,
  DragOverlay,
  MouseSensor,
  TouchSensor,
  closestCorners,
  pointerWithin,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
  type CollisionDetection,
} from '@dnd-kit/core';
import DashboardCustomizeIcon from '@mui/icons-material/DashboardCustomize';
import SettingsIcon from '@mui/icons-material/Settings';
import UnfoldLessIcon from '@mui/icons-material/UnfoldLess';
import UnfoldMoreIcon from '@mui/icons-material/UnfoldMore';
import {
  Alert,
  Box,
  Card,
  CardActionArea,
  CardContent,
  Chip,
  IconButton,
  Skeleton,
  Stack,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate, useSearch } from '@tanstack/react-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BoardTask } from 'entities/board-task';
import { TaskCard } from 'entities/board-task';
import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';

import {
  useGetBoardQuery,
  useCreateTaskMutation,
  useMoveTaskMutation,
  useGetBoardPresetsQuery,
  useCreateBoardMutation,
  useGetProjectMembersQuery,
} from '../api/boardApi';
import { useBoardChannel } from '../lib/useBoardChannel';
import { useBoardSidebarStore } from '../model/useBoardSidebarStore';

import { ActivityFeedPanel } from './ActivityFeedPanel';
import { BoardColumnComponent } from './BoardColumn';
import { BoardFilterBar, type BoardFilters } from './BoardFilterBar';
import { BoardSettingsDialog } from './BoardSettingsDialog';
import { CreateTaskDialog } from './CreateTaskDialog';
import { TaskSidebar } from './TaskSidebar';

interface BoardPanelProps {
  projectId: number;
}

const MOVE_DEBOUNCE_MS = 500;

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    height: 'calc(100vh - 220px)',
  },
  board: {
    display: 'flex',
    gap: 1.5,
    overflowX: 'auto',
    flex: 1,
    pb: 2,
    px: 2,
    pt: 2,
    alignItems: 'stretch',
    backgroundColor: 'background.default',
    borderRadius: '12px',
  },
  loading: {
    display: 'flex',
    gap: 1.5,
  },
  skeletonCol: {
    width: 300,
    minWidth: 300,
    height: 400,
    borderRadius: '10px',
  },
  empty: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    py: 8,
    gap: 2,
  },
} satisfies Record<string, SxProps<Theme>>;

export const BoardPanel = ({ projectId }: BoardPanelProps) => {
  const { data, isLoading, error } = useGetBoardQuery(projectId);
  const [createTask] = useCreateTaskMutation();
  const [moveTask] = useMoveTaskMutation();
  const { data: collaborators } = useGetProjectMembersQuery(projectId);
  const { data: currentUser } = useGetCurrentUserQuery();

  const urlSearch = useSearch({ strict: false }) as {
    assigneeId?: string;
    taskType?: string;
    priority?: string;
    tags?: string;
    search?: string;
    task?: number;
  };
  const navigate = useNavigate({
    from: Routes.frontend.companyProjectTabPath('$projectId', '$tab') as '/company/projects/$projectId/$tab',
  });

  const [activeTask, setActiveTask] = useState<BoardTask | null>(null);
  const [creatingInColumn, setCreatingInColumn] = useState<number | null>(null);
  const [filters, setFilters] = useState<BoardFilters>(() => ({
    assigneeId: urlSearch.assigneeId,
    taskType: urlSearch.taskType,
    priority: urlSearch.priority,
    tags: urlSearch.tags ? urlSearch.tags.split(',').filter(Boolean) : undefined,
    search: urlSearch.search,
  }));
  const boardId = data?.board.id;
  const [collapsedColumns, setCollapsedColumns] = useState<Set<number>>(new Set());
  const [collapsedRestored, setCollapsedRestored] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const lastMoveRef = useRef<Record<number, number>>({});

  const openTask = useBoardSidebarStore((s) => s.openTask);
  const activeTaskId = useBoardSidebarStore((s) => s.activeTaskId);
  const isOpen = useBoardSidebarStore((s) => s.isOpen);

  const isInitialMount = useRef(true);

  useEffect(() => {
    if (urlSearch.task != null) {
      openTask(urlSearch.task);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }
    void navigate({
      search: (prev) => ({
        ...prev,
        task: isOpen && activeTaskId != null ? activeTaskId : undefined,
      }),
      replace: true,
    });
  }, [isOpen, activeTaskId, navigate]);

  useEffect(() => {
    if (!boardId || collapsedRestored) return;
    try {
      const stored = localStorage.getItem(`board-${boardId}-collapsed`);
      if (stored) setCollapsedColumns(new Set(JSON.parse(stored) as number[]));
    } catch {
      /* ignore corrupt data */
    }
    setCollapsedRestored(true);
  }, [boardId, collapsedRestored]);

  useEffect(() => {
    if (!boardId || !collapsedRestored) return;
    localStorage.setItem(`board-${boardId}-collapsed`, JSON.stringify([...collapsedColumns]));
  }, [boardId, collapsedColumns, collapsedRestored]);

  const mouseSensor = useSensor(MouseSensor, { activationConstraint: { distance: 8 } });
  const touchSensor = useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 5 } });
  const sensors = useSensors(mouseSensor, touchSensor);

  const collisionDetection = useCallback<CollisionDetection>((args) => {
    const pointerCollisions = pointerWithin(args);
    if (pointerCollisions.length > 0) return pointerCollisions;
    return closestCorners(args);
  }, []);

  useBoardChannel({ boardId: data?.board.id ?? null, projectId });

  const tasksByColumn = useMemo(() => {
    if (!data) return {};
    const map: Record<number, BoardTask[]> = {};
    for (const col of data.board.boardColumns) {
      map[col.id] = [];
    }

    const filtered = data.tasks.filter((task) => {
      if (filters.assigneeId && String(task.assigneeId) !== filters.assigneeId) return false;
      if (filters.taskType && task.taskType !== filters.taskType) return false;
      if (filters.priority && task.priority !== filters.priority) return false;
      if (filters.search && !task.title.toLowerCase().includes(filters.search.toLowerCase())) return false;
      if (filters.tags?.length && !filters.tags.some((tag) => task.tags.includes(tag))) return false;
      return true;
    });

    for (const task of filtered) {
      if (map[task.boardColumnId]) {
        map[task.boardColumnId].push(task);
      }
    }
    return map;
  }, [data, filters]);

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const taskData = event.active.data.current?.task as BoardTask | undefined;
    setActiveTask(taskData ?? null);
  }, []);

  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      setActiveTask(null);
      const { active, over } = event;
      if (!over || !data) return;

      const task = active.data.current?.task as BoardTask | undefined;
      if (!task) return;

      let targetColumnId: number;
      let targetPosition: number | undefined;

      if (over.data.current?.task) {
        const overTask = over.data.current.task as BoardTask;
        targetColumnId = overTask.boardColumnId;
        targetPosition = overTask.position;
      } else if (over.data.current?.columnId) {
        targetColumnId = over.data.current.columnId as number;
      } else {
        return;
      }

      const sameColumn = targetColumnId === task.boardColumnId;
      if (sameColumn && targetPosition === undefined) return;
      if (sameColumn && targetPosition === task.position) return;

      const now = Date.now();
      const lastMove = lastMoveRef.current[task.id];
      if (lastMove && now - lastMove < MOVE_DEBOUNCE_MS) return;
      lastMoveRef.current[task.id] = now;

      const position =
        targetPosition ?? (tasksByColumn[targetColumnId] || []).reduce((max, t) => Math.max(max, t.position), 0) + 1;

      moveTask({ projectId, taskId: task.id, columnId: targetColumnId, position });
    },
    [data, moveTask, projectId, tasksByColumn],
  );

  const handleToggleCollapse = useCallback((columnId: number) => {
    setCollapsedColumns((prev) => {
      const next = new Set(prev);
      if (next.has(columnId)) {
        next.delete(columnId);
      } else {
        next.add(columnId);
      }
      return next;
    });
  }, []);

  const handleToggleAll = useCallback(() => {
    if (!data) return;
    const allIds = data.board.boardColumns.map((c) => c.id);
    setCollapsedColumns((prev) => (prev.size === allIds.length ? new Set() : new Set(allIds)));
  }, [data]);

  const handleFilterChange = useCallback(
    (newFilters: BoardFilters) => {
      setFilters(newFilters);
      void navigate({
        search: (prev) => ({
          ...prev,
          assigneeId: newFilters.assigneeId,
          taskType: newFilters.taskType,
          priority: newFilters.priority,
          tags: newFilters.tags?.length ? newFilters.tags.join(',') : undefined,
          search: newFilters.search,
        }),
        replace: true,
      });
    },
    [navigate],
  );

  const handleCreateTask = useCallback(
    async (taskData: Partial<BoardTask>) => {
      await createTask({ projectId, boardTask: taskData });
      setCreatingInColumn(null);
    },
    [createTask, projectId],
  );

  if (isLoading) {
    return (
      <Box sx={styles.loading}>
        {[1, 2, 3].map((i) => (
          <Skeleton key={i} variant="rounded" sx={styles.skeletonCol} />
        ))}
      </Box>
    );
  }

  if (error) {
    return <CreateBoardView projectId={projectId} />;
  }

  if (!data) return null;

  return (
    <Box sx={styles.root}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
        <Box sx={{ flex: 1 }}>
          <BoardFilterBar
            filters={filters}
            onChange={handleFilterChange}
            projectId={projectId}
            members={(collaborators?.items || []).map((m) => ({ id: m.id, name: m.name || m.email }))}
            currentUserId={currentUser?.id}
          />
        </Box>
        <Tooltip
          title={
            collapsedColumns.size === data.board.boardColumns.length ? 'Expand all columns' : 'Collapse all columns'
          }
        >
          <IconButton size="small" onClick={handleToggleAll}>
            {collapsedColumns.size === data.board.boardColumns.length ? (
              <UnfoldMoreIcon fontSize="small" />
            ) : (
              <UnfoldLessIcon fontSize="small" />
            )}
          </IconButton>
        </Tooltip>
        <Tooltip title="Board settings">
          <IconButton size="small" onClick={() => setSettingsOpen(true)}>
            <SettingsIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      </Box>
      <DndContext
        sensors={sensors}
        collisionDetection={collisionDetection}
        onDragStart={handleDragStart}
        onDragEnd={handleDragEnd}
      >
        <Box sx={styles.board}>
          {data.board.boardColumns.map((col) => (
            <BoardColumnComponent
              key={col.id}
              column={col}
              tasks={tasksByColumn[col.id] || []}
              onTaskClick={openTask}
              onAddTask={(colId) => setCreatingInColumn(colId)}
              isFiltered={Boolean(
                filters.assigneeId || filters.taskType || filters.priority || filters.tags?.length || filters.search,
              )}
              collapsed={collapsedColumns.has(col.id)}
              onToggleCollapse={handleToggleCollapse}
            />
          ))}
        </Box>

        {creatingInColumn !== null && (
          <CreateTaskDialog
            open
            onClose={() => setCreatingInColumn(null)}
            onSubmit={handleCreateTask}
            columnId={creatingInColumn}
            columns={data.board.boardColumns}
            projectId={projectId}
          />
        )}
        <DragOverlay>{activeTask ? <TaskCard task={activeTask} isDragging /> : null}</DragOverlay>
      </DndContext>

      <ActivityFeedPanel projectId={projectId} />
      <TaskSidebar projectId={projectId} />

      <BoardSettingsDialog
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        projectId={projectId}
        columns={data.board.boardColumns}
      />
    </Box>
  );
};

const CreateBoardView = ({ projectId }: { projectId: number }) => {
  const { data: presets, isLoading } = useGetBoardPresetsQuery(projectId);
  const [createBoard, { isLoading: isCreating }] = useCreateBoardMutation();

  const handleCreate = async (presetKey: string) => {
    try {
      await createBoard({ projectId, preset: presetKey }).unwrap();
    } catch {
      /* error handled by RTK */
    }
  };

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', py: 8, gap: 3 }}>
      <DashboardCustomizeIcon sx={{ fontSize: 64, color: 'text.secondary', opacity: 0.5 }} />
      <Typography variant="h5" color="text.secondary">
        No task board yet
      </Typography>

      {isLoading ? (
        <Stack direction="row" spacing={2}>
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} variant="rounded" width={240} height={160} />
          ))}
        </Stack>
      ) : (
        <Stack spacing={1.5} alignItems="center">
          <Typography variant="body2" color="text.secondary">
            Choose a template to get started. You can customize columns later.
          </Typography>
          <Stack direction="row" spacing={2} flexWrap="wrap" justifyContent="center">
            {presets?.map((preset) => (
              <Card key={preset.key} sx={{ width: 260 }} variant="outlined">
                <CardActionArea onClick={() => handleCreate(preset.key)} disabled={isCreating}>
                  <CardContent>
                    <Typography variant="subtitle1" gutterBottom fontWeight={600}>
                      {preset.displayName}
                    </Typography>
                    <Stack direction="row" gap={0.5} flexWrap="wrap">
                      {preset.columns.map((col) => (
                        <Chip key={col} label={col} size="small" variant="outlined" />
                      ))}
                    </Stack>
                  </CardContent>
                </CardActionArea>
              </Card>
            ))}
          </Stack>
        </Stack>
      )}

      {isCreating && (
        <Alert severity="info" sx={{ mt: 2 }}>
          Creating board...
        </Alert>
      )}
    </Box>
  );
};
