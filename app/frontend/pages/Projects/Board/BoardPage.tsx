import {
  DndContext,
  DragOverlay,
  PointerSensor,
  closestCorners,
  pointerWithin,
  useSensor,
  useSensors,
  useDroppable,
  type CollisionDetection,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy, useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Avatar,
  Badge,
  Box,
  Button,
  Card,
  Checkbox,
  Drawer,
  Group,
  Loader,
  Menu,
  Modal,
  MultiSelect,
  Paper,
  ScrollArea,
  Select,
  SimpleGrid,
  Skeleton,
  Stack,
  Tabs,
  TagsInput,
  Text,
  TextInput,
  Textarea,
  ThemeIcon,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import {
  IconArrowsMaximize,
  IconArrowsMinimize,
  IconBookmark,
  IconBug,
  IconChevronLeft,
  IconChevronRight,
  IconCircleCheck,
  IconClock,
  IconCloudUpload,
  IconCoin,
  IconColumns,
  IconDownload,
  IconFilter,
  IconGripVertical,
  IconHourglass,
  IconLayoutKanban,
  IconLink,
  IconMessage,
  IconPlus,
  IconSearch,
  IconSend,
  IconSettings,
  IconTrash,
  IconChartBar,
  IconExternalLink,
  IconPlayerPlay,
  IconUser,
  IconX,
} from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Markdown from 'react-markdown';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
  XAxis,
  YAxis,
} from 'recharts';
import remarkGfm from 'remark-gfm';
import { z } from 'zod';

import { apiFetch } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';
import { formatElapsedTime } from 'shared/lib/formatElapsedTime';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useLocalStorageSet } from 'shared/lib/hooks/useLocalStorage';
import {
  apiV1ProjectTasksPath,
  apiV1ProjectTaskPath,
  apiV1ProjectTaskCommentsPath,
  apiV1ProjectTaskAssetsPath,
  apiV1ProjectTaskAssetPath,
  apiV1ProjectTaskGatePath,
  moveApiV1ProjectTaskPath,
  triggerWorkflowApiV1ProjectTaskPath,
  apiV1ProjectColumnsPath,
  apiV1ProjectColumnPath,
  reorderApiV1ProjectColumnsPath,
  apiV1ProjectActivitiesPath,
  apiV1ProjectBoardPath,
  apiV1ProjectViewPresetsPath,
  apiV1ProjectViewPresetPath,
} from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import styles from './BoardPage.module.css';

const COMMENT_TAG_SUGGESTIONS = ['feedback', 'tech_design', 'code_review', 'qa_report', 'implementation_notes'];
const AUTHOR_TYPES = [
  { value: '', label: 'All' },
  { value: 'human', label: 'Human' },
  { value: 'agent', label: 'Agent' },
  { value: 'system', label: 'System' },
];

interface Project {
  id: number;
  name: string;
}
interface Board {
  id: number;
  name: string;
  presetOrigin: string | null;
}
interface WorkflowBinding {
  id: number;
  workflowId: number;
  workflowName: string | null;
  triggerMode: string;
}
interface Column {
  id: number;
  name: string;
  position: number;
  purpose: string | null;
  workflowBinding: WorkflowBinding | null;
}
interface Workflow {
  id: number;
  name: string;
}
interface Gate {
  id: number;
  gateType: string;
  metadata: Record<string, unknown> & { repoFullName?: string; prNumber?: number; runId?: number };
  createdAt: string;
}

interface Task {
  id: number;
  title: string;
  description?: string | null;
  taskType: string;
  priority: string | null;
  assigneeId: number | null;
  assigneeName: string | null;
  boardColumnId: number;
  position: number;
  parentTaskId: number | null;
  tags: string[];
  commentsCount: number;
  childrenCount: number;
  assetsCount?: number;
  recentWorkflowRuns: Array<{ id: number; state: string; createdAt: string }>;
  pendingGates: Gate[];
  createdAt: string;
  updatedAt: string;
}
interface Member {
  id: number;
  name: string;
}

interface BoardPreset {
  key: string;
  displayName: string;
  columns: string[];
}

interface ViewPreset {
  id: number;
  name: string;
  filters: Record<string, unknown>;
  shared: boolean;
  userId: number;
  createdAt: string;
}

interface Props {
  project: Project;
  board: Board | null;
  boardPresets?: BoardPreset[];
  columns: Column[];
  tasks: Task[];
  members: Member[];
  workflows: Workflow[];
  viewPresets?: ViewPreset[];
  currentUserId?: number;
  cableStream?: string;
  taskCableStream?: string | null;
  recentActivities?: ActivityItem[];
  selectedTask?: Task | null;
  taskComments?: Comment[];
  taskAssets?: TaskAsset[];
  taskActivities?: ActivityItem[];
  taskWorkflowRuns?: TaskWorkflowRun[];
  taskStatistics?: TaskStatistics | null;
}

const TASK_TYPE_COLORS: Record<string, string> = {
  epic: '#9c27b0',
  story: '#2196f3',
  bug: '#f44336',
  not_specified: '#9e9e9e',
};

const PRIORITY_COLORS: Record<string, string> = {
  critical: '#f44336',
  high: '#ff9800',
  medium: '#ffc107',
  low: '#4caf50',
};

const WORKFLOW_ACTIVE_STATES = new Set(['pending', 'running', 'paused']);

const CHART_COLORS = [
  '#2196f3',
  '#9c27b0',
  '#4caf50',
  '#ff9800',
  '#e91e63',
  '#00bcd4',
  '#ff5722',
  '#3f51b5',
  '#8bc34a',
  '#ffc107',
];
const CHART_TOOLTIP_STYLE: React.CSSProperties = {
  backgroundColor: '#1a1a2e',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: '#fff',
};

function workflowStatusColor(state: string): string {
  if (WORKFLOW_ACTIVE_STATES.has(state)) return '#1976d2';
  if (state === 'failed') return '#d32f2f';
  if (state === 'cancelled') return '#9e9e9e';
  return '#2e7d32';
}

function formatCostCents(cents: number): string {
  return cents >= 100 ? `$${(cents / 100).toFixed(2)}` : `${cents}¢`;
}

function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}K`;
  return `${tokens}`;
}

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return `${h}h ${m}m`;
}

interface BoardFilters {
  assigneeId: string | null;
  taskType: string | null;
  priority: string | null;
  tags: string[];
  search: string;
}

const EMPTY_FILTERS: BoardFilters = { assigneeId: null, taskType: null, priority: null, tags: [], search: '' };

const taskSchema = z.object({
  title: z.string().min(1, 'Title is required'),
  description: z.string().optional(),
  taskType: z.string().optional(),
  priority: z.string().optional(),
  assigneeId: z.string().nullable().optional(),
  boardColumnId: z.string().min(1, 'Column is required'),
});

type TaskFormValues = z.infer<typeof taskSchema>;

function avatarInitials(name: string): string {
  return name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

// --- TaskCard (no grip handle, legacy style) ---

function SortableTaskCard({ task, onClick }: { task: Task; onClick?: (t: Task) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: `task-${task.id}`,
    data: { type: 'task', task },
    transition: {
      duration: 200,
      easing: 'cubic-bezier(0.25, 1, 0.5, 1)',
    },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
    scale: isDragging ? '1.02' : '1',
  };

  return (
    <Box ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <TaskCardUI task={task} onClick={onClick} />
    </Box>
  );
}

function TaskCardUI({
  task,
  onClick,
  isDragOverlay,
}: {
  task: Task;
  onClick?: (t: Task) => void;
  isDragOverlay?: boolean;
}) {
  const visibleTags = (task.tags ?? []).slice(0, 3);
  const overflowCount = (task.tags ?? []).length - 3;

  return (
    <Paper
      shadow={isDragOverlay ? 'lg' : 'xs'}
      radius="sm"
      p="xs"
      mb={8}
      withBorder
      bg="var(--mantine-color-dark-5)"
      onClick={() => onClick?.(task)}
      style={{
        cursor: 'pointer',
        transition: 'box-shadow 0.15s, border-color 0.15s',
        borderColor: 'var(--app-border-strong)',
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLElement).style.boxShadow = 'var(--mantine-shadow-md)';
        (e.currentTarget as HTMLElement).style.borderColor = 'var(--mantine-color-accentBlue-4)';
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLElement).style.boxShadow = isDragOverlay
          ? 'var(--mantine-shadow-lg)'
          : 'var(--mantine-shadow-xs)';
        (e.currentTarget as HTMLElement).style.borderColor = 'var(--app-border-strong)';
      }}
    >
      {/* Title row with priority dot */}
      <Group gap={4} align="flex-start" wrap="nowrap">
        {task.priority && (
          <Tooltip label={task.priority}>
            <Box
              w={8}
              h={8}
              mt={4}
              style={{
                borderRadius: '50%',
                backgroundColor: PRIORITY_COLORS[task.priority] ?? '#9e9e9e',
                flexShrink: 0,
              }}
            />
          </Tooltip>
        )}
        <Text size="sm" fw={500} lh={1.3} style={{ flex: 1, wordBreak: 'break-word' }}>
          {task.title}
        </Text>
      </Group>

      {/* Type chip + tags */}
      <Group gap={4} mt={6} wrap="wrap">
        {task.taskType && task.taskType !== 'not_specified' && (
          <Badge
            size="xs"
            variant="filled"
            style={{
              backgroundColor: TASK_TYPE_COLORS[task.taskType] ?? '#9e9e9e',
              color: '#fff',
              fontWeight: 600,
              fontSize: 10,
            }}
          >
            {task.taskType}
          </Badge>
        )}
        {visibleTags.map((tag) => (
          <Badge key={tag} size="xs" variant="outline" color="gray" style={{ fontSize: 10 }}>
            {tag}
          </Badge>
        ))}
        {overflowCount > 0 && (
          <Badge size="xs" variant="outline" color="gray" style={{ fontSize: 10 }}>
            +{overflowCount}
          </Badge>
        )}
      </Group>

      {/* Footer: assignee + workflow dots + comments */}
      <Group justify="space-between" mt={6}>
        <Group gap={6}>
          {task.assigneeName && (
            <Tooltip label={task.assigneeName}>
              <Avatar size={20} radius="xl" color="blue" style={{ fontSize: 10 }}>
                {avatarInitials(task.assigneeName)}
              </Avatar>
            </Tooltip>
          )}
          {(task.recentWorkflowRuns ?? []).length > 0 && (
            <Tooltip label={(task.recentWorkflowRuns ?? []).map((r) => r.state).join(', ')}>
              <Group gap={3} align="center" style={{ lineHeight: 1 }}>
                {[...(task.recentWorkflowRuns ?? [])].reverse().map((run) => (
                  <Box
                    key={run.id}
                    w={7}
                    h={7}
                    className={WORKFLOW_ACTIVE_STATES.has(run.state) ? styles.workflowDotActive : undefined}
                    style={{
                      borderRadius: '50%',
                      backgroundColor: workflowStatusColor(run.state),
                    }}
                  />
                ))}
              </Group>
            </Tooltip>
          )}
        </Group>
        <Group gap={6}>
          {task.childrenCount > 0 && (
            <Group gap={2}>
              <Text size="xs" c="dimmed">
                □{task.childrenCount}
              </Text>
            </Group>
          )}
          {task.commentsCount > 0 && (
            <Group gap={2}>
              <IconMessage size={12} color="var(--mantine-color-dimmed)" />
              <Text size="xs" c="dimmed">
                {task.commentsCount}
              </Text>
            </Group>
          )}
        </Group>
      </Group>
    </Paper>
  );
}

// --- Column ---

function BoardColumn({
  column,
  tasks,
  onAddTask,
  onTaskClick,
  collapsed,
  onToggleCollapse,
  isFiltered,
  isDropTarget,
}: {
  column: Column;
  tasks: Task[];
  onAddTask: (columnId: number) => void;
  onTaskClick: (task: Task) => void;
  collapsed: boolean;
  onToggleCollapse: (id: number) => void;
  isFiltered: boolean;
  isDropTarget: boolean;
}) {
  const { setNodeRef } = useDroppable({ id: `column-${column.id}`, data: { columnId: column.id } });
  const taskIds = useMemo(() => tasks.map((t) => `task-${t.id}`), [tasks]);

  const overStyle = {
    outline: isDropTarget ? '2px solid var(--mantine-color-blue-6)' : '2px solid transparent',
    outlineOffset: -2,
    transition: 'outline-color 0.15s ease',
  };

  if (collapsed) {
    const priorityIndicators = tasks.slice(0, 5).map((t) => {
      const latestRun = t.recentWorkflowRuns?.[0];
      const hasPendingGates = (t.pendingGates?.length ?? 0) > 0;
      let color = '#9e9e9e';
      let hasActiveRun = false;
      if (latestRun) {
        color = workflowStatusColor(latestRun.state);
        hasActiveRun = WORKFLOW_ACTIVE_STATES.has(latestRun.state);
      }
      if (hasPendingGates) {
        color = '#eab308';
        hasActiveRun = false;
      }
      const tooltipParts: string[] = [t.title];
      if (latestRun) {
        if (latestRun.state === 'running' && latestRun.createdAt) {
          tooltipParts.push(`Running — ${formatElapsedTime(latestRun.createdAt)}`);
        } else {
          tooltipParts.push(`Status: ${latestRun.state}`);
        }
      }
      if (hasPendingGates) {
        const oldestGate = t.pendingGates.reduce((a, b) => (a.createdAt < b.createdAt ? a : b));
        tooltipParts.push(`Waiting — ${formatElapsedTime(oldestGate.createdAt)}`);
      }
      return { id: t.id, task: t, color, hasActiveRun, tooltipLabel: tooltipParts.join(' · ') };
    });

    return (
      <Box
        ref={setNodeRef}
        onClick={() => onToggleCollapse(column.id)}
        style={{
          flex: '0 0 44px',
          minWidth: 44,
          maxWidth: 44,
          backgroundColor: 'var(--mantine-color-dark-6)',
          border: '1px solid var(--app-border-default)',
          borderRadius: 10,
          maxHeight: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          cursor: 'pointer',
          padding: '12px 0',
          gap: 8,
          ...overStyle,
        }}
      >
        <Box style={{ position: 'relative' }}>
          <IconChevronRight size={16} color="var(--mantine-color-dimmed)" />
          <Badge
            size="xs"
            variant="filled"
            color="gray"
            style={{ position: 'absolute', top: -8, right: -12, fontSize: 9, padding: '0 4px', minWidth: 16 }}
          >
            {tasks.length}
          </Badge>
        </Box>
        {priorityIndicators.length > 0 && (
          <Box style={{ display: 'flex', flexDirection: 'column', gap: 3, alignItems: 'center' }}>
            {priorityIndicators.map((ind) => (
              <Tooltip key={ind.id} label={ind.tooltipLabel} position="right" withArrow color="dark">
                <Box
                  onClick={(e) => {
                    e.stopPropagation();
                    onTaskClick(ind.task);
                  }}
                  style={{
                    width: 4,
                    height: 20,
                    borderRadius: 2,
                    backgroundColor: ind.color,
                    cursor: 'pointer',
                    animation: ind.hasActiveRun ? 'priorityBarPulse 2s ease-in-out infinite' : undefined,
                  }}
                />
              </Tooltip>
            ))}
          </Box>
        )}
        <Tooltip label={column.name} position="right">
          <Text
            size="xs"
            fw={600}
            c="dimmed"
            tt="uppercase"
            style={{ writingMode: 'vertical-rl', textOrientation: 'mixed', letterSpacing: 0.5, whiteSpace: 'nowrap' }}
          >
            {column.name}
          </Text>
        </Tooltip>
      </Box>
    );
  }

  return (
    <Box
      ref={setNodeRef}
      style={{
        flex: '0 0 280px',
        minWidth: 280,
        display: 'flex',
        flexDirection: 'column',
        backgroundColor: 'var(--mantine-color-dark-6)',
        border: '1px solid var(--app-border-default)',
        borderRadius: 10,
        overflow: 'hidden',
        ...overStyle,
      }}
    >
      {/* Header */}
      <Box style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 12px 8px' }}>
        <Group gap={6} style={{ overflow: 'hidden', cursor: 'pointer', flex: 1 }}>
          <ActionIcon size="xs" variant="subtle" onClick={() => onToggleCollapse(column.id)} style={{ padding: 2 }}>
            <IconChevronLeft size={14} color="var(--mantine-color-dimmed)" />
          </ActionIcon>
          {column.purpose ? (
            <Tooltip label={column.purpose} multiline w={200}>
              <Text
                size="xs"
                fw={600}
                c="dimmed"
                tt="uppercase"
                style={{ letterSpacing: 0.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
              >
                {column.name}
              </Text>
            </Tooltip>
          ) : (
            <Text
              size="xs"
              fw={600}
              c="dimmed"
              tt="uppercase"
              style={{ letterSpacing: 0.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
            >
              {column.name}
            </Text>
          )}
          <Text
            size="xs"
            fw={600}
            c="dimmed"
            style={{
              backgroundColor: 'var(--mantine-color-dark-5)',
              borderRadius: 10,
              padding: '1px 6px',
              flexShrink: 0,
            }}
          >
            {tasks.length}
          </Text>
        </Group>
        <ActionIcon size="sm" variant="subtle" onClick={() => onAddTask(column.id)}>
          <IconPlus size={16} />
        </ActionIcon>
      </Box>

      {/* Task list */}
      <SortableContext items={taskIds} strategy={verticalListSortingStrategy}>
        <Box style={{ flex: 1, overflowY: 'auto', padding: '0 12px 12px', minHeight: 60 }}>
          {tasks.length === 0 ? (
            <Text size="xs" c="dimmed" ta="center" py="xl">
              {isFiltered ? 'No matching tasks' : 'No tasks yet'}
            </Text>
          ) : (
            tasks.map((task) => <SortableTaskCard key={task.id} task={task} onClick={onTaskClick} />)
          )}
        </Box>
      </SortableContext>
    </Box>
  );
}

// --- API helpers ---

const jsonHeaders = { 'Content-Type': 'application/json' };

interface Comment {
  id: number;
  body: string;
  authorName?: string;
  authorType?: string;
  tags?: string[];
  createdAt: string;
}
interface ActivityItem {
  id: number;
  eventType: string;
  actorName: string;
  description: string;
  createdAt: string;
}

async function addTaskComment(projectId: number, taskId: number, body: string, tags: string[] = []) {
  await apiFetch(apiV1ProjectTaskCommentsPath(projectId, taskId), {
    method: 'POST',
    headers: jsonHeaders,
    body: JSON.stringify({ taskComment: { body, tags } }),
  });
  router.reload({ only: ['task_comments', 'task_activities'] });
}

interface TaskAsset {
  id: number;
  name: string;
  fileUrl: string | null;
  fileSize: number | null;
  contentType: string | null;
  authorType: string | null;
  tags: string[];
}

async function uploadTaskAsset(projectId: number, taskId: number, file: File) {
  const formData = new FormData();
  formData.append('task_asset[name]', file.name);
  formData.append('task_asset[file]', file);
  try {
    await apiFetch(apiV1ProjectTaskAssetsPath(projectId, taskId), {
      method: 'POST',
      body: formData,
    });
    router.reload({ only: ['task_assets', 'task_activities'] });
  } catch {
    /* ignore */
  }
}

async function deleteTaskAsset(projectId: number, taskId: number, assetId: number) {
  try {
    await apiFetch(apiV1ProjectTaskAssetPath(projectId, taskId, assetId), {
      method: 'DELETE',
    });
    router.reload({ only: ['task_assets', 'task_activities'] });
  } catch {
    /* ignore */
  }
}

async function deleteTaskGate(projectId: number, taskId: number, gateId: number): Promise<boolean> {
  try {
    const res = await apiFetch(apiV1ProjectTaskGatePath(projectId, taskId, gateId), {
      method: 'DELETE',
    });
    return res.ok;
  } catch {
    return false;
  }
}

interface TaskWorkflowRun {
  id: number;
  workflowName: string;
  state: string;
  mode: string;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
}

function useBoardActivitiesLoadMore(projectId: number, initialActivities: ActivityItem[]) {
  const [extraActivities, setExtraActivities] = useState<ActivityItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(initialActivities.length >= 20);

  useEffect(() => {
    setExtraActivities([]);
    setPage(1);
    setHasMore(initialActivities.length >= 20);
  }, [initialActivities]);

  const loadMore = useCallback(async () => {
    const nextPage = page + 1;
    setLoading(true);
    try {
      const res = await apiFetch(apiV1ProjectActivitiesPath(projectId) + `?page=${nextPage}&per_page=20`);
      if (res.ok) {
        const data = await res.json();
        const items: ActivityItem[] = data.items ?? data ?? [];
        setExtraActivities((prev) => [...prev, ...items]);
        setHasMore(data.meta ? data.meta.page < data.meta.totalPages : items.length >= 20);
        setPage(nextPage);
      }
    } catch {
      /* ignore */
    }
    setLoading(false);
  }, [projectId, page]);

  const activities = useMemo(() => [...initialActivities, ...extraActivities], [initialActivities, extraActivities]);

  return { activities, loading, loadMore, hasMore };
}

interface TaskStatistics {
  costTotals: { totalCostCents: number };
  tokenTotals: { totalTokens: number };
  timeTotals: { totalDurationSeconds: number };
  gateStats: Array<{
    id: number;
    gateType: string;
    status: string;
    createdAt: string;
    resolvedAt: string | null;
    durationSeconds: number | null;
  }>;
  workflowBreakdowns: Array<{
    workflowId: number;
    workflowName: string;
    costCents: number;
    totalTokens: number;
    durationSeconds: number;
  }>;
}

// --- Task Detail Sidebar ---

function TaskDetailSidebar({
  task,
  allTasks,
  onClose,
  onDelete,
  onOpenTask,
  projectId,
  columns,
  members,
  comments,
  activities,
  taskAssets,
  workflowRuns,
  stats,
}: {
  task: Task | null;
  allTasks: Task[];
  onClose: () => void;
  onDelete: (taskId: number) => void;
  onOpenTask: (task: Task) => void;
  projectId: number;
  columns: Column[];
  members: Member[];
  comments: Comment[];
  activities: ActivityItem[];
  taskAssets: TaskAsset[];
  workflowRuns: TaskWorkflowRun[];
  stats: TaskStatistics | null;
}) {
  const [tab, setTab] = useState<string | null>('details');
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleValue, setTitleValue] = useState('');
  const [pendingTitle, setPendingTitle] = useState<string | null>(null);
  const [editingDesc, setEditingDesc] = useState(false);
  const [descValue, setDescValue] = useState('');
  const [pendingDesc, setPendingDesc] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const [wide, setWide] = useState(false);
  const [commentBody, setCommentBody] = useState('');
  const [commentTags, setCommentTags] = useState<string[]>([]);
  const [submittingComment, setSubmittingComment] = useState(false);
  const [collapsedComments, setCollapsedComments] = useState<Set<number>>(new Set());
  const [authorFilter, setAuthorFilter] = useState('');
  const [tagFilter, setTagFilter] = useState('');
  const [triggeringWorkflow, setTriggeringWorkflow] = useState(false);
  const [deletingGateId, setDeletingGateId] = useState<number | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

  // Clear optimistic overrides when cable brings fresh task data
  useEffect(() => {
    setPendingTitle(null);
    setPendingDesc(null);
  }, [task?.updatedAt]);

  const filteredComments = useMemo(() => {
    return comments.filter((c) => {
      if (authorFilter && c.authorType !== authorFilter) return false;
      if (tagFilter && !(c.tags ?? []).some((t) => t.toLowerCase().includes(tagFilter.toLowerCase()))) return false;
      return true;
    });
  }, [comments, authorFilter, tagFilter]);

  const allCommentsCollapsed = useMemo(
    () => filteredComments.length > 0 && filteredComments.every((c) => collapsedComments.has(c.id)),
    [filteredComments, collapsedComments],
  );

  const toggleComment = useCallback((id: number) => {
    setCollapsedComments((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleAllComments = useCallback(() => {
    if (allCommentsCollapsed) setCollapsedComments(new Set());
    else setCollapsedComments(new Set(filteredComments.map((c) => c.id)));
  }, [allCommentsCollapsed, filteredComments]);

  const epicTasks = useMemo(
    () => allTasks.filter((t) => t.taskType === 'epic' && t.id !== task?.id),
    [allTasks, task?.id],
  );

  const childTasks = useMemo(() => allTasks.filter((t) => t.parentTaskId === task?.id), [allTasks, task?.id]);

  const parentTask = useMemo(
    () => (task?.parentTaskId ? allTasks.find((t) => t.id === task.parentTaskId) : null) ?? null,
    [allTasks, task?.parentTaskId],
  );

  useEffect(() => {
    if (task) {
      setTitleValue(task.title);
      setDescValue(task.description ?? '');
      setTab('details');
      setEditingTitle(false);
      setEditingDesc(false);
      setDeleteConfirm(false);
      setCommentBody('');
      setCommentTags([]);
      setCollapsedComments(new Set());
      setAuthorFilter('');
      setTagFilter('');
    }
  }, [task?.id]);

  const saveTitle = async () => {
    if (!task || titleValue.trim() === task.title) {
      setEditingTitle(false);
      return;
    }
    const saved = titleValue.trim();
    setPendingTitle(saved);
    setEditingTitle(false);
    await apiFetch(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { title: saved } }),
    });
    // cable will refresh selectedTask and clear pendingTitle via useEffect below
  };

  const saveDescription = async () => {
    setEditingDesc(false);
    if (!task || descValue === (task.description ?? '')) return;
    const saved = descValue;
    setPendingDesc(saved);
    await apiFetch(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { description: saved } }),
    });
  };

  const saveField = async (field: string, value: string | string[] | null) => {
    if (!task) return;
    await apiFetch(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { [field]: value } }),
    });
    router.reload({ only: ['selected_task'] });
  };

  const moveToColumn = async (columnId: string) => {
    if (!task) return;
    await apiFetch(moveApiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ columnId: Number(columnId) }),
    });
    router.reload({ only: ['tasks', 'selected_task'] });
  };

  const handleSubmitComment = async () => {
    if (!commentBody.trim() || !task) return;
    setSubmittingComment(true);
    await addTaskComment(projectId, task.id, commentBody.trim(), commentTags);
    setCommentBody('');
    setCommentTags([]);
    setSubmittingComment(false);
  };

  const handleTriggerWorkflow = useCallback(async () => {
    if (!task) return;
    setTriggeringWorkflow(true);
    try {
      await apiFetch(triggerWorkflowApiV1ProjectTaskPath(projectId, task.id), {
        method: 'POST',
        headers: jsonHeaders,
      });
      router.reload({ only: ['selected_task', 'task_workflow_runs', 'task_activities'] });
    } catch {
      /* ignore */
    }
    setTriggeringWorkflow(false);
  }, [projectId, task]);

  const handleDeleteGate = useCallback(
    async (gateId: number) => {
      if (!task) return;
      setDeletingGateId(gateId);
      await deleteTaskGate(projectId, task.id, gateId);
      router.reload({ only: ['selected_task'] });
      setDeletingGateId(null);
    },
    [projectId, task],
  );

  const handleUploadAsset = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file || !task) return;
      await uploadTaskAsset(projectId, task.id, file);
      if (fileInputRef.current) fileInputRef.current.value = '';
    },
    [projectId, task],
  );

  const handleDeleteAsset = useCallback(
    async (assetId: number) => {
      if (!task) return;
      await deleteTaskAsset(projectId, task.id, assetId);
    },
    [projectId, task],
  );

  if (!task) return null;

  const taskColumn = columns.find((c) => c.id === task.boardColumnId);
  const columnWorkflowBinding = taskColumn?.workflowBinding ?? null;
  const hasActiveRun = (task.recentWorkflowRuns ?? []).some((r) => WORKFLOW_ACTIVE_STATES.has(r.state));
  const canTriggerWorkflow = columnWorkflowBinding && !hasActiveRun;
  const assetsCount = (taskAssets ?? []).length || task.assetsCount || 0;

  return (
    <Drawer
      opened={!!task}
      onClose={onClose}
      position="right"
      size={wide ? '50vw' : 480}
      withCloseButton={false}
      padding={0}
      styles={{
        content: { display: 'flex', flexDirection: 'column', overflow: 'hidden' },
        body: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
      }}
    >
      {/* Header */}
      <Box p="md" style={{ borderBottom: '1px solid var(--mantine-color-dark-4)', flexShrink: 0 }}>
        <Group justify="space-between" mb="xs">
          <Group gap="xs">
            <ActionIcon variant="subtle" size="sm" onClick={() => setWide(!wide)}>
              {wide ? <IconArrowsMinimize size={16} /> : <IconArrowsMaximize size={16} />}
            </ActionIcon>
            {task.taskType && task.taskType !== 'not_specified' && (
              <Badge
                size="sm"
                variant="filled"
                style={{ backgroundColor: TASK_TYPE_COLORS[task.taskType] ?? '#9e9e9e', color: '#fff' }}
              >
                {task.taskType}
              </Badge>
            )}
            {task.priority && (
              <Badge
                size="sm"
                variant="outline"
                style={{
                  borderColor: PRIORITY_COLORS[task.priority] ?? '#9e9e9e',
                  color: PRIORITY_COLORS[task.priority] ?? '#9e9e9e',
                }}
              >
                {task.priority}
              </Badge>
            )}
          </Group>
          <Group gap="xs">
            {canTriggerWorkflow && (
              <Button
                variant="light"
                size="compact-sm"
                leftSection={<IconPlayerPlay size={14} />}
                onClick={handleTriggerWorkflow}
                loading={triggeringWorkflow}
              >
                Run workflow
              </Button>
            )}
            <ActionIcon variant="subtle" color="red" size="sm" onClick={() => setDeleteConfirm(true)}>
              <IconTrash size={16} />
            </ActionIcon>
            <ActionIcon variant="subtle" size="sm" onClick={onClose}>
              <IconX size={16} />
            </ActionIcon>
          </Group>
        </Group>
        {editingTitle ? (
          <TextInput
            value={titleValue}
            onChange={(e) => setTitleValue(e.currentTarget.value)}
            onBlur={saveTitle}
            onKeyDown={(e) => {
              if (e.key === 'Enter') saveTitle();
              if (e.key === 'Escape') {
                setTitleValue(task.title);
                setEditingTitle(false);
              }
            }}
            autoFocus
            size="md"
            styles={{ input: { fontWeight: 700, fontSize: 18, padding: 0, border: 'none', background: 'transparent' } }}
          />
        ) : (
          <Text size="lg" fw={700} onClick={() => setEditingTitle(true)} style={{ cursor: 'pointer' }}>
            {pendingTitle ?? task.title}
          </Text>
        )}
      </Box>

      <Tabs
        value={tab}
        onChange={setTab}
        style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}
      >
        <Tabs.List px="md" style={{ flexShrink: 0 }}>
          <Tabs.Tab value="details">Details</Tabs.Tab>
          <Tabs.Tab value="comments">
            Comments{' '}
            {(comments ?? []).length > 0
              ? `(${(comments ?? []).length})`
              : task.commentsCount > 0
                ? `(${task.commentsCount})`
                : ''}
          </Tabs.Tab>
          <Tabs.Tab value="assets">Assets{assetsCount > 0 ? ` (${assetsCount})` : ''}</Tabs.Tab>
          <Tabs.Tab value="activity">Activity</Tabs.Tab>
          <Tabs.Tab value="statistics">
            <IconChartBar size={16} />
          </Tabs.Tab>
        </Tabs.List>

        {/* Details — fully editable fields */}
        <Tabs.Panel value="details" p="md" style={{ flex: 1, overflow: 'auto' }}>
          <Stack gap="md">
            {/* Description — click to edit */}
            <Box>
              <Text size="xs" c="dimmed" fw={600} tt="uppercase" mb={4}>
                Description
              </Text>
              {editingDesc ? (
                <Textarea
                  value={descValue}
                  onChange={(e) => setDescValue(e.currentTarget.value)}
                  onBlur={saveDescription}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') {
                      setDescValue(task.description ?? '');
                      setEditingDesc(false);
                    }
                  }}
                  autoFocus
                  autosize
                  minRows={3}
                  size="sm"
                />
              ) : (
                <Box
                  onClick={() => {
                    setDescValue(task.description ?? '');
                    setEditingDesc(true);
                  }}
                  style={{ cursor: 'pointer', minHeight: 40 }}
                >
                  {(pendingDesc ?? task.description) ? (
                    <Box className={styles.commentMd}>
                      <Markdown remarkPlugins={[remarkGfm]}>{pendingDesc ?? task.description ?? ''}</Markdown>
                    </Box>
                  ) : (
                    <Text size="sm" c="dimmed">
                      Click to add description...
                    </Text>
                  )}
                </Box>
              )}
            </Box>

            <Select
              label="Column"
              data={columns.map((c) => ({ value: String(c.id), label: c.name }))}
              value={String(task.boardColumnId)}
              onChange={(v) => {
                if (v && v !== String(task.boardColumnId)) moveToColumn(v);
              }}
              size="sm"
            />
            <Select
              label="Type"
              data={[
                { value: 'not_specified', label: 'Not specified' },
                { value: 'epic', label: 'Epic' },
                { value: 'story', label: 'Story' },
                { value: 'bug', label: 'Bug' },
              ]}
              value={task.taskType}
              onChange={(v) => saveField('taskType', v)}
              size="sm"
            />
            <Select
              label="Priority"
              data={[
                { value: '', label: 'None' },
                { value: 'critical', label: 'Critical' },
                { value: 'high', label: 'High' },
                { value: 'medium', label: 'Medium' },
                { value: 'low', label: 'Low' },
              ]}
              value={task.priority ?? ''}
              onChange={(v) => saveField('priority', v || null)}
              clearable
              size="sm"
            />
            <Select
              label="Assignee"
              data={members.map((m) => ({ value: String(m.id), label: m.name }))}
              value={task.assigneeId ? String(task.assigneeId) : null}
              onChange={(v) => saveField('assigneeId', v)}
              clearable
              searchable
              size="sm"
            />

            {/* Parent epic — for non-epic tasks */}
            {task.taskType !== 'epic' && epicTasks.length > 0 && (
              <Select
                label="Parent Epic"
                data={epicTasks.map((e) => ({ value: String(e.id), label: e.title }))}
                value={task.parentTaskId ? String(task.parentTaskId) : null}
                onChange={(v) => saveField('parentTaskId', v)}
                clearable
                searchable
                size="sm"
              />
            )}

            {/* Tags — editable free-text input */}
            <TagsInput
              label="Tags"
              value={task.tags ?? []}
              onChange={(tags) => saveField('tags', tags)}
              placeholder="Add tag and press Enter"
              size="sm"
              clearable
            />

            <Box>
              <Text size="xs" c="dimmed" mb={4}>
                Created
              </Text>
              <Text size="sm">{formatDateTime(task.createdAt)}</Text>
            </Box>

            {/* Workflow Runs */}
            {(workflowRuns ?? []).length > 0 && (
              <Box>
                <Text size="xs" c="dimmed" fw={600} tt="uppercase" mb={4}>
                  Workflow Runs ({(workflowRuns ?? []).length})
                </Text>
                <Stack gap={4}>
                  {(workflowRuns ?? []).map((run) => (
                    <Group key={run.id} gap="xs" align="center" style={{ fontSize: 13 }}>
                      <Badge
                        size="xs"
                        variant="filled"
                        color={
                          run.state === 'completed'
                            ? 'green'
                            : run.state === 'failed'
                              ? 'red'
                              : run.state === 'running'
                                ? 'blue'
                                : 'gray'
                        }
                        style={{ fontSize: 10, fontWeight: 600 }}
                      >
                        {run.state}
                      </Badge>
                      <Text
                        component="a"
                        href={`/company/projects/${projectId}/workflow_runs/${run.id}`}
                        target="_blank"
                        rel="noopener"
                        size="sm"
                        c="blue"
                        style={{ display: 'flex', alignItems: 'center', gap: 4, flex: 1, textDecoration: 'none' }}
                        onMouseEnter={(e: React.MouseEvent<HTMLAnchorElement>) => {
                          e.currentTarget.style.textDecoration = 'underline';
                        }}
                        onMouseLeave={(e: React.MouseEvent<HTMLAnchorElement>) => {
                          e.currentTarget.style.textDecoration = 'none';
                        }}
                      >
                        {run.workflowName}
                        <IconExternalLink size={12} />
                      </Text>
                      <Text size="xs" c="dimmed">
                        {formatDateTime(run.createdAt)}
                      </Text>
                    </Group>
                  ))}
                </Stack>
              </Box>
            )}

            {/* Child tasks — for epics */}
            {task.taskType === 'epic' && (
              <Box>
                <Group justify="space-between" mb={4}>
                  <Text size="xs" c="dimmed" fw={600} tt="uppercase">
                    Child Tasks ({childTasks.length})
                  </Text>
                </Group>
                {childTasks.length === 0 ? (
                  <Text size="xs" c="dimmed">
                    No child tasks yet
                  </Text>
                ) : (
                  <Stack gap={2}>
                    {childTasks.map((child) => (
                      <UnstyledButton
                        key={child.id}
                        onClick={() => onOpenTask(child)}
                        px={6}
                        py={4}
                        style={{
                          borderRadius: 4,
                          display: 'flex',
                          alignItems: 'center',
                          gap: 8,
                          transition: 'background 0.1s',
                        }}
                        className={styles.childTaskRow}
                      >
                        <Badge
                          size="xs"
                          variant="filled"
                          style={{
                            backgroundColor: TASK_TYPE_COLORS[child.taskType] ?? '#9e9e9e',
                            color: '#fff',
                            fontSize: 10,
                            fontWeight: 600,
                            flexShrink: 0,
                          }}
                        >
                          {child.taskType.replace('_', ' ')}
                        </Badge>
                        <Text size="xs" c="blue" style={{ flex: 1 }} lineClamp={1}>
                          {child.title}
                        </Text>
                      </UnstyledButton>
                    ))}
                  </Stack>
                )}
              </Box>
            )}

            {/* Parent epic link — for non-epic tasks with parent */}
            {task.taskType !== 'epic' && parentTask && (
              <Box>
                <Text size="xs" c="dimmed" fw={600} tt="uppercase" mb={4}>
                  Parent Epic
                </Text>
                <UnstyledButton onClick={() => onOpenTask(parentTask)}>
                  <Text
                    size="sm"
                    c="blue"
                    style={{ textDecoration: 'none' }}
                    onMouseEnter={(e: React.MouseEvent<HTMLElement>) => {
                      e.currentTarget.style.textDecoration = 'underline';
                    }}
                    onMouseLeave={(e: React.MouseEvent<HTMLElement>) => {
                      e.currentTarget.style.textDecoration = 'none';
                    }}
                  >
                    {parentTask.title}
                  </Text>
                </UnstyledButton>
              </Box>
            )}

            {/* Pending waits */}
            {(task.pendingGates ?? []).length > 0 && (
              <Box>
                <Group gap={6} mb={4}>
                  <ThemeIcon size={18} variant="light" color="yellow" radius="xl">
                    <IconHourglass size={12} />
                  </ThemeIcon>
                  <Text size="xs" c="dimmed" fw={600} tt="uppercase">
                    Pending Waits ({(task.pendingGates ?? []).length})
                  </Text>
                </Group>
                <Stack gap={4}>
                  {(task.pendingGates ?? []).map((wait) => (
                    <Group key={wait.id} gap="xs" align="flex-start" wrap="nowrap">
                      <Badge
                        size="xs"
                        color="yellow"
                        variant="filled"
                        style={{ fontSize: 10, fontWeight: 600, flexShrink: 0 }}
                      >
                        {wait.gateType.replace(/_/g, ' ')}
                      </Badge>
                      <Box style={{ flex: 1, minWidth: 0 }}>
                        {wait.gateType === 'github_checks_completed' &&
                          wait.metadata.repoFullName &&
                          wait.metadata.prNumber && (
                            <Text
                              component="a"
                              href={`https://github.com/${wait.metadata.repoFullName}/pull/${wait.metadata.prNumber}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              size="xs"
                              c="blue"
                              style={{ display: 'flex', alignItems: 'center', gap: 4 }}
                            >
                              <IconLink size={10} />
                              {String(wait.metadata.repoFullName)} #{String(wait.metadata.prNumber)}
                            </Text>
                          )}
                        {wait.gateType === 'github_workflow_completed' &&
                          wait.metadata.repoFullName &&
                          wait.metadata.runId && (
                            <Text
                              component="a"
                              href={`https://github.com/${wait.metadata.repoFullName}/actions/runs/${wait.metadata.runId}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              size="xs"
                              c="blue"
                              style={{ display: 'flex', alignItems: 'center', gap: 4 }}
                            >
                              <IconLink size={10} />
                              {String(wait.metadata.repoFullName)} #{String(wait.metadata.runId)}
                            </Text>
                          )}
                      </Box>
                      <ActionIcon
                        size="xs"
                        variant="subtle"
                        color="gray"
                        onClick={() => handleDeleteGate(wait.id)}
                        loading={deletingGateId === wait.id}
                      >
                        <IconX size={12} />
                      </ActionIcon>
                    </Group>
                  ))}
                </Stack>
              </Box>
            )}
          </Stack>
        </Tabs.Panel>

        {/* Comments — collapsible + markdown */}
        <Tabs.Panel value="comments" style={{ flex: 1, overflow: 'auto' }}>
          <Group gap="sm" p="md" pb={0}>
            <Select
              size="xs"
              placeholder="Author"
              data={AUTHOR_TYPES}
              value={authorFilter}
              onChange={(v) => setAuthorFilter(v ?? '')}
              clearable
              w={100}
            />
            <TextInput
              size="xs"
              placeholder="Filter by tag"
              value={tagFilter}
              onChange={(e) => setTagFilter(e.currentTarget.value)}
              style={{ flex: 1 }}
            />
          </Group>

          <Box p="md" style={{ borderBottom: '1px solid var(--mantine-color-dark-4)' }}>
            <Textarea
              placeholder="Write a comment... (⌘+Enter to send)"
              value={commentBody}
              onChange={(e) => setCommentBody(e.currentTarget.value)}
              autosize
              minRows={2}
              maxRows={6}
              size="sm"
              mb="xs"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && e.metaKey) {
                  e.preventDefault();
                  handleSubmitComment();
                }
              }}
            />
            <Group gap="xs" mb="xs" wrap="wrap">
              {COMMENT_TAG_SUGGESTIONS.map((tag) => (
                <Badge
                  key={tag}
                  size="xs"
                  variant={commentTags.includes(tag) ? 'filled' : 'outline'}
                  style={{ cursor: 'pointer' }}
                  onClick={() =>
                    setCommentTags((prev) => (prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag]))
                  }
                >
                  {tag}
                </Badge>
              ))}
            </Group>
            <Button
              size="xs"
              rightSection={<IconSend size={14} />}
              onClick={handleSubmitComment}
              loading={submittingComment}
              disabled={!commentBody.trim()}
            >
              Send
            </Button>
          </Box>

          {filteredComments.length > 1 && (
            <Group justify="flex-end" px="md" pt="xs">
              <Button
                variant="subtle"
                size="xs"
                leftSection={allCommentsCollapsed ? <IconArrowsMaximize size={14} /> : <IconArrowsMinimize size={14} />}
                onClick={toggleAllComments}
                styles={{ root: { textTransform: 'none' } }}
              >
                {allCommentsCollapsed ? 'Expand all' : 'Collapse all'}
              </Button>
            </Group>
          )}

          <ScrollArea p="md">
            {filteredComments.length === 0 ? (
              <Text size="sm" c="dimmed" ta="center" py="xl">
                No comments yet.
              </Text>
            ) : (
              filteredComments.map((c) => {
                const isCollapsed = collapsedComments.has(c.id);
                return (
                  <Paper
                    key={c.id}
                    p="sm"
                    radius="sm"
                    mb="sm"
                    style={{ backgroundColor: 'var(--mantine-color-dark-6)' }}
                  >
                    <Group
                      gap="xs"
                      style={{ cursor: 'pointer', userSelect: 'none' }}
                      onClick={() => toggleComment(c.id)}
                      mb={isCollapsed ? 0 : 4}
                    >
                      <Avatar size={22} radius="xl" color="blue" style={{ fontSize: 10 }}>
                        {(c.authorName ?? 'U')[0]}
                      </Avatar>
                      <Text size="xs" fw={600}>
                        {c.authorName ?? 'System'}
                      </Text>
                      {c.authorType && (
                        <Badge size="xs" variant="light">
                          {c.authorType}
                        </Badge>
                      )}
                      <Text size="xs" c="dimmed" style={{ marginLeft: 'auto' }}>
                        {formatDateTime(c.createdAt)}
                      </Text>
                    </Group>
                    {isCollapsed ? (
                      <Text size="xs" c="dimmed" lineClamp={1} mt={4}>
                        {c.body.split('\n')[0]}
                      </Text>
                    ) : (
                      <Box className={styles.commentMd} style={{ fontSize: 13, lineHeight: 1.5 }}>
                        <Markdown remarkPlugins={[remarkGfm]}>{c.body}</Markdown>
                      </Box>
                    )}
                    {c.tags && c.tags.length > 0 && (
                      <Group gap={4} mt={6}>
                        {c.tags.map((t) => (
                          <Badge key={t} size="xs" variant="outline">
                            {t}
                          </Badge>
                        ))}
                      </Group>
                    )}
                  </Paper>
                );
              })
            )}
          </ScrollArea>
        </Tabs.Panel>

        {/* Assets — with upload and delete */}
        <Tabs.Panel value="assets" style={{ flex: 1, overflow: 'auto' }}>
          <Group justify="flex-end" p="md" pb={0}>
            <input ref={fileInputRef} type="file" hidden onChange={handleUploadAsset} />
            <Button
              variant="outline"
              size="xs"
              leftSection={<IconCloudUpload size={14} />}
              onClick={() => fileInputRef.current?.click()}
            >
              Upload File
            </Button>
          </Group>
          <ScrollArea p="md">
            {(taskAssets ?? []).length === 0 ? (
              <Text size="sm" c="dimmed" ta="center" py="xl">
                No assets attached.
              </Text>
            ) : (
              <Stack gap="sm">
                {(taskAssets ?? []).map((a) => (
                  <Paper key={a.id} p="xs" radius="sm" withBorder>
                    <Group justify="space-between" wrap="nowrap">
                      <Box style={{ flex: 1, minWidth: 0 }}>
                        <Text size="sm" fw={500} lineClamp={1}>
                          {a.name}
                        </Text>
                        <Text size="xs" c="dimmed">
                          {a.contentType ?? ''}
                          {a.fileSize
                            ? ` · ${a.fileSize < 1024 ? `${a.fileSize} B` : a.fileSize < 1024 * 1024 ? `${(a.fileSize / 1024).toFixed(1)} KB` : `${(a.fileSize / (1024 * 1024)).toFixed(1)} MB`}`
                            : ''}
                        </Text>
                      </Box>
                      <Group gap={4}>
                        {a.authorType && (
                          <Badge size="xs" variant="light">
                            {a.authorType}
                          </Badge>
                        )}
                        {a.fileUrl && (
                          <ActionIcon component="a" href={a.fileUrl} target="_blank" variant="subtle" size="sm">
                            <IconDownload size={14} />
                          </ActionIcon>
                        )}
                        <ActionIcon variant="subtle" color="red" size="sm" onClick={() => handleDeleteAsset(a.id)}>
                          <IconTrash size={14} />
                        </ActionIcon>
                      </Group>
                    </Group>
                    {a.tags && a.tags.length > 0 && (
                      <Group gap={4} mt={4}>
                        {a.tags.map((t) => (
                          <Badge key={t} size="xs" variant="outline">
                            {t}
                          </Badge>
                        ))}
                      </Group>
                    )}
                  </Paper>
                ))}
              </Stack>
            )}
          </ScrollArea>
        </Tabs.Panel>

        {/* Activity */}
        <Tabs.Panel value="activity" p="md" style={{ flex: 1, overflow: 'auto' }}>
          {(activities ?? []).length === 0 ? (
            <Text size="sm" c="dimmed" ta="center" py="xl">
              No activity yet.
            </Text>
          ) : (
            (activities ?? []).map((a) => (
              <Group key={a.id} gap="sm" py="xs" style={{ borderBottom: '1px solid var(--mantine-color-dark-5)' }}>
                <Box style={{ flex: 1, minWidth: 0 }}>
                  <Text size="sm" lineClamp={2}>
                    {a.description}
                  </Text>
                  <Text size="xs" c="dimmed">
                    {a.actorName} · {formatDateTime(a.createdAt)}
                  </Text>
                </Box>
              </Group>
            ))
          )}
        </Tabs.Panel>

        {/* Statistics */}
        <Tabs.Panel value="statistics" p="md" style={{ flex: 1, overflow: 'auto' }}>
          {stats === undefined ? (
            <Stack gap="sm" pt={4}>
              <SimpleGrid cols={3} spacing="sm">
                {[0, 1, 2].map((i) => (
                  <Paper key={i} p="md" radius="md" withBorder>
                    <Skeleton height={12} width={80} mb={8} />
                    <Skeleton height={24} width={60} />
                  </Paper>
                ))}
              </SimpleGrid>
              <Skeleton height={180} radius="md" mt="md" />
            </Stack>
          ) : !stats?.costTotals ? (
            <Text size="sm" c="dimmed" ta="center" py="xl">
              No statistics available.
            </Text>
          ) : (
            <Stack gap={0}>
              {/* Summary stat cards with icons */}
              <SimpleGrid cols={3} spacing="sm">
                <Paper p="md" radius="md" withBorder>
                  <Group gap={4} mb={6}>
                    <IconCoin size={12} color="var(--mantine-color-dimmed)" />
                    <Text size="11px" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
                      Total Cost
                    </Text>
                  </Group>
                  <Text size="22px" fw={700} lh={1.1}>
                    {formatCostCents(stats.costTotals.totalCostCents)}
                  </Text>
                </Paper>
                <Paper p="md" radius="md" withBorder>
                  <Group gap={4} mb={6}>
                    <IconChartBar size={12} color="var(--mantine-color-dimmed)" />
                    <Text size="11px" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
                      Total Tokens
                    </Text>
                  </Group>
                  <Text size="22px" fw={700} lh={1.1}>
                    {formatTokens(stats.tokenTotals.totalTokens)}
                  </Text>
                </Paper>
                <Paper p="md" radius="md" withBorder>
                  <Group gap={4} mb={6}>
                    <IconClock size={12} color="var(--mantine-color-dimmed)" />
                    <Text size="11px" c="dimmed" tt="uppercase" style={{ letterSpacing: 0.4 }}>
                      Total Run Time
                    </Text>
                  </Group>
                  <Text size="22px" fw={700} lh={1.1}>
                    {formatDuration(stats.timeTotals.totalDurationSeconds)}
                  </Text>
                </Paper>
              </SimpleGrid>

              {/* Workflow breakdown with chart + table */}
              {stats.workflowBreakdowns.length > 0 && (
                <>
                  <Text size="13px" fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }} mt="xl" mb="sm">
                    Breakdown by Workflow
                  </Text>
                  <Paper p="md" radius="md" withBorder>
                    <Text size="13px" fw={600} mb="md">
                      Cost per Workflow
                    </Text>
                    <Box style={{ width: '100%', height: Math.max(stats.workflowBreakdowns.length * 36, 80) }}>
                      <ResponsiveContainer width="100%" height="100%">
                        <BarChart
                          data={stats.workflowBreakdowns.map((b, i) => ({
                            name: b.workflowName.length > 20 ? b.workflowName.slice(0, 18) + '\u2026' : b.workflowName,
                            costCents: b.costCents,
                            color: CHART_COLORS[i % CHART_COLORS.length],
                          }))}
                          layout="vertical"
                          margin={{ top: 4, right: 16, bottom: 0, left: 0 }}
                        >
                          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" horizontal={false} />
                          <XAxis
                            type="number"
                            tick={{ fontSize: 11 }}
                            tickFormatter={(v) => formatCostCents(Number(v))}
                          />
                          <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={110} />
                          <RechartsTooltip
                            contentStyle={CHART_TOOLTIP_STYLE}
                            formatter={(v) => [formatCostCents(Number(v)), 'Cost']}
                          />
                          <Bar dataKey="costCents" radius={[0, 4, 4, 0]}>
                            {stats.workflowBreakdowns.map((_, i) => (
                              <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                            ))}
                          </Bar>
                        </BarChart>
                      </ResponsiveContainer>
                    </Box>

                    {/* Breakdown table */}
                    <Box mt="md" style={{ overflowX: 'auto' }}>
                      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                          <tr>
                            <th
                              style={{
                                textAlign: 'left',
                                fontSize: 11,
                                color: 'var(--mantine-color-dimmed)',
                                fontWeight: 600,
                                padding: '6px 8px',
                                borderBottom: '1px solid var(--mantine-color-dark-4)',
                              }}
                            >
                              Workflow
                            </th>
                            <th
                              style={{
                                textAlign: 'right',
                                fontSize: 11,
                                color: 'var(--mantine-color-dimmed)',
                                fontWeight: 600,
                                padding: '6px 8px',
                                borderBottom: '1px solid var(--mantine-color-dark-4)',
                              }}
                            >
                              Cost
                            </th>
                            <th
                              style={{
                                textAlign: 'right',
                                fontSize: 11,
                                color: 'var(--mantine-color-dimmed)',
                                fontWeight: 600,
                                padding: '6px 8px',
                                borderBottom: '1px solid var(--mantine-color-dark-4)',
                              }}
                            >
                              Tokens
                            </th>
                            <th
                              style={{
                                textAlign: 'right',
                                fontSize: 11,
                                color: 'var(--mantine-color-dimmed)',
                                fontWeight: 600,
                                padding: '6px 8px',
                                borderBottom: '1px solid var(--mantine-color-dark-4)',
                              }}
                            >
                              Run Time
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          {stats.workflowBreakdowns.map((b, i) => (
                            <tr key={b.workflowId}>
                              <td
                                style={{
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--mantine-color-dark-5)',
                                }}
                              >
                                <Group gap={8} wrap="nowrap">
                                  <Box
                                    w={8}
                                    h={8}
                                    style={{
                                      borderRadius: '50%',
                                      backgroundColor: CHART_COLORS[i % CHART_COLORS.length],
                                      flexShrink: 0,
                                    }}
                                  />
                                  <Text size="xs" lineClamp={1}>
                                    {b.workflowName}
                                  </Text>
                                </Group>
                              </td>
                              <td
                                style={{
                                  textAlign: 'right',
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--mantine-color-dark-5)',
                                }}
                              >
                                {formatCostCents(b.costCents)}
                              </td>
                              <td
                                style={{
                                  textAlign: 'right',
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--mantine-color-dark-5)',
                                }}
                              >
                                {formatTokens(b.totalTokens)}
                              </td>
                              <td
                                style={{
                                  textAlign: 'right',
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--mantine-color-dark-5)',
                                }}
                              >
                                {formatDuration(b.durationSeconds)}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </Box>
                  </Paper>
                </>
              )}

              {/* Waits with icons and duration sub-text */}
              {stats.gateStats.length > 0 && (
                <>
                  <Group gap={6} mt="xl" mb="sm">
                    <Text size="13px" fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                      Waits
                    </Text>
                    <Text size="11px" c="dimmed">
                      {stats.gateStats.filter((w) => w.status === 'pending').length} pending &middot;{' '}
                      {stats.gateStats.filter((w) => w.status === 'resolved').length} resolved
                    </Text>
                  </Group>
                  <Paper p="md" radius="md" withBorder>
                    <Stack gap={0}>
                      {stats.gateStats.map((w, idx) => (
                        <Group
                          key={w.id}
                          gap={10}
                          align="center"
                          py={8}
                          style={
                            idx < stats.gateStats.length - 1
                              ? { borderBottom: '1px solid var(--mantine-color-dark-5)' }
                              : undefined
                          }
                        >
                          {w.status === 'resolved' ? (
                            <IconCircleCheck size={14} color="var(--mantine-color-green-6)" style={{ flexShrink: 0 }} />
                          ) : (
                            <IconHourglass size={14} color="var(--mantine-color-yellow-6)" style={{ flexShrink: 0 }} />
                          )}
                          <Box style={{ flex: 1, minWidth: 0 }}>
                            <Text size="xs" fw={500}>
                              {w.gateType.replace(/_/g, ' ')}
                            </Text>
                            {w.durationSeconds != null && (
                              <Text size="11px" c="dimmed">
                                Resolved in {formatDuration(w.durationSeconds)}
                              </Text>
                            )}
                          </Box>
                          <Badge
                            size="xs"
                            variant="filled"
                            color={w.status === 'resolved' ? 'green' : 'yellow'}
                            style={{ fontSize: 10, fontWeight: 600 }}
                          >
                            {w.status}
                          </Badge>
                        </Group>
                      ))}
                    </Stack>
                  </Paper>
                </>
              )}

              <Box h={16} />
            </Stack>
          )}
        </Tabs.Panel>
      </Tabs>

      <Modal opened={deleteConfirm} onClose={() => setDeleteConfirm(false)} title="Delete Task" centered size="sm">
        <Text size="sm" mb="md">
          Are you sure you want to delete &quot;{task.title}&quot;? This action cannot be undone.
        </Text>
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setDeleteConfirm(false)}>
            Cancel
          </Button>
          <Button
            color="red"
            onClick={() => {
              onDelete(task.id);
              setDeleteConfirm(false);
            }}
          >
            Delete
          </Button>
        </Group>
      </Modal>
    </Drawer>
  );
}

// --- Board Settings Dialog (with drag-to-reorder columns) ---

interface ColState {
  id: number | null;
  name: string;
  purpose: string;
  workflowId: string | null;
  triggerMode: string;
  bindingId: number | null;
  bindingChanged: boolean;
}

function SortableColumnRow({
  col,
  idx,
  updateCol,
  removeColumn,
}: {
  col: ColState;
  idx: number;
  updateCol: (idx: number, field: keyof ColState, value: string | number | null) => void;
  removeColumn: (idx: number) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: col.id ? `col-${col.id}` : `col-new-${idx}`,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <Paper ref={setNodeRef} style={style} p="sm" radius="sm" withBorder>
      <Group gap="sm" mb="xs">
        <Box {...attributes} {...listeners} style={{ cursor: 'grab', touchAction: 'none' }}>
          <IconGripVertical size={14} color="var(--mantine-color-dimmed)" />
        </Box>
        <TextInput
          placeholder="Column name"
          value={col.name}
          onChange={(e) => updateCol(idx, 'name', e.currentTarget.value)}
          style={{ flex: 1 }}
          size="sm"
        />
        <ActionIcon variant="subtle" color="red" size="sm" onClick={() => removeColumn(idx)}>
          <IconTrash size={14} />
        </ActionIcon>
      </Group>
      <TextInput
        placeholder="Purpose (optional)"
        value={col.purpose}
        onChange={(e) => updateCol(idx, 'purpose', e.currentTarget.value)}
        size="xs"
        mb="xs"
      />
      <Text size="xs" c="dimmed">
        Triggers (incl. “task enters this column”) are configured per workflow — open a workflow and use the{' '}
        <b>Triggers</b> button.
      </Text>
    </Paper>
  );
}

function BoardSettingsDialog({
  opened,
  onClose,
  projectId,
  columns: initialColumns,
}: {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  columns: Column[];
}) {
  const [cols, setCols] = useState<ColState[]>([]);
  const [saving, setSaving] = useState(false);
  const [deletedIds, setDeletedIds] = useState<number[]>([]);

  useEffect(() => {
    if (opened) {
      setCols(
        initialColumns.map((c) => ({
          id: c.id,
          name: c.name,
          purpose: c.purpose ?? '',
          workflowId: c.workflowBinding?.workflowId ? String(c.workflowBinding.workflowId) : null,
          triggerMode: c.workflowBinding?.triggerMode ?? 'auto',
          bindingId: c.workflowBinding?.id ?? null,
          bindingChanged: false,
        })),
      );
      setDeletedIds([]);
    }
  }, [opened, initialColumns]);

  const addColumn = () =>
    setCols((prev) => [
      ...prev,
      {
        id: null,
        name: '',
        purpose: '',
        workflowId: null,
        triggerMode: 'auto',
        bindingId: null,
        bindingChanged: false,
      },
    ]);

  const removeColumn = (idx: number) => {
    const col = cols[idx];
    if (col.id) setDeletedIds((prev) => [...prev, col.id!]);
    setCols((prev) => prev.filter((_, i) => i !== idx));
  };

  const updateCol = (idx: number, field: keyof ColState, value: string | number | null) => {
    setCols((prev) =>
      prev.map((c, i) => {
        if (i !== idx) return c;
        const updated = { ...c, [field]: value };
        if (['workflowId', 'triggerMode'].includes(field)) updated.bindingChanged = true;
        return updated;
      }),
    );
  };

  const settingsSensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  const sortableIds = useMemo(() => cols.map((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`)), [cols]);

  const handleColumnDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    setCols((prev) => {
      const oldIndex = prev.findIndex((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`) === active.id);
      const newIndex = prev.findIndex((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`) === over.id);
      if (oldIndex === -1 || newIndex === -1) return prev;

      const next = [...prev];
      const [moved] = next.splice(oldIndex, 1);
      next.splice(newIndex, 0, moved);
      return next;
    });
  }, []);

  const handleSave = async () => {
    setSaving(true);

    for (const id of deletedIds) {
      await apiFetch(apiV1ProjectColumnPath(projectId, id), { method: 'DELETE' });
    }

    const createdIdMap = new Map<number, number>();

    for (let i = 0; i < cols.length; i++) {
      const col = cols[i];
      if (col.id) {
        const orig = initialColumns.find((c) => c.id === col.id);
        if (orig && (orig.name !== col.name || (orig.purpose ?? '') !== col.purpose)) {
          await apiFetch(apiV1ProjectColumnPath(projectId, col.id), {
            method: 'PATCH',
            headers: jsonHeaders,
            body: JSON.stringify({ boardColumn: { name: col.name, purpose: col.purpose || null } }),
          });
        }
      } else if (col.name.trim()) {
        const res = await apiFetch(apiV1ProjectColumnsPath(projectId), {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({ boardColumn: { name: col.name, purpose: col.purpose || null } }),
        });
        if (res.ok) {
          const data = await res.json();
          createdIdMap.set(i, data.id);
        }
      }
    }

    const allIds = cols.map((c, i) => c.id ?? createdIdMap.get(i)).filter((id): id is number => id != null);
    if (allIds.length > 0) {
      await apiFetch(reorderApiV1ProjectColumnsPath(projectId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({ columnIds: allIds }),
      });
    }

    setSaving(false);
    onClose();
    router.reload({ only: ['columns', 'tasks', 'workflows'] });
  };

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title="Board Settings"
      centered
      size="xl"
      styles={{
        content: { display: 'flex', flexDirection: 'column', maxHeight: '80vh' },
        body: { flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' },
      }}
    >
      <Text size="sm" c="dimmed" mb="md">
        Drag to reorder, rename, or remove columns. Assign workflows to auto-trigger when tasks enter a column.
      </Text>
      <DndContext sensors={settingsSensors} collisionDetection={closestCorners} onDragEnd={handleColumnDragEnd}>
        <SortableContext items={sortableIds} strategy={verticalListSortingStrategy}>
          <Box style={{ flex: 1, minHeight: 0, overflowY: 'auto', paddingRight: 4 }}>
            <Stack gap="md">
              {cols.map((col, idx) => (
                <SortableColumnRow
                  key={col.id ? `col-${col.id}` : `col-new-${idx}`}
                  col={col}
                  idx={idx}
                  updateCol={updateCol}
                  removeColumn={removeColumn}
                />
              ))}
            </Stack>
          </Box>
        </SortableContext>
      </DndContext>
      <Group mt="md" justify="space-between" style={{ flexShrink: 0 }}>
        <Button variant="outline" size="sm" leftSection={<IconPlus size={14} />} onClick={addColumn}>
          Add Column
        </Button>
        <Group gap="sm">
          <Button variant="outline" size="sm" onClick={onClose}>
            Cancel
          </Button>
          <Button size="sm" loading={saving} onClick={handleSave}>
            Save
          </Button>
        </Group>
      </Group>
    </Modal>
  );
}

// --- Activity Feed (collapsible, real data) ---

function ActivityFeedPanel({ projectId, initialActivities }: { projectId: number; initialActivities: ActivityItem[] }) {
  const [open, setOpen] = useState(false);
  const { activities, loading, loadMore, hasMore } = useBoardActivitiesLoadMore(projectId, initialActivities);

  return (
    <Box mt="sm">
      <Group
        gap="sm"
        onClick={() => setOpen(!open)}
        style={{ cursor: 'pointer', userSelect: 'none' }}
        justify="space-between"
        p="xs"
      >
        <Text size="xs" fw={700} tt="uppercase" style={{ letterSpacing: 0.5 }}>
          Activity Feed
        </Text>
        <Box style={{ transform: open ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.2s' }}>
          <IconChevronRight size={14} style={{ transform: 'rotate(90deg)' }} />
        </Box>
      </Group>
      {open && (
        <Paper withBorder p="sm" radius="sm" mah={260} style={{ overflow: 'auto' }}>
          {loading && activities.length === 0 ? (
            <Box ta="center" py="md">
              <Loader size="sm" />
            </Box>
          ) : activities.length === 0 ? (
            <Text size="xs" c="dimmed" ta="center" py="md">
              No activity yet.
            </Text>
          ) : (
            <>
              {activities.map((a) => (
                <Group key={a.id} gap="sm" py={4} style={{ borderBottom: '1px solid var(--mantine-color-dark-5)' }}>
                  <Box style={{ flex: 1, minWidth: 0 }}>
                    <Text size="xs" lineClamp={1}>
                      {a.description}
                    </Text>
                    <Text size="10px" c="dimmed">
                      {a.actorName} · {formatDateTime(a.createdAt)}
                    </Text>
                  </Box>
                </Group>
              ))}
              {hasMore && (
                <Button variant="subtle" size="xs" fullWidth mt="xs" onClick={loadMore} loading={loading}>
                  Load more
                </Button>
              )}
            </>
          )}
        </Paper>
      )}
    </Box>
  );
}

// --- Board Preset Picker (empty board state) ---

const PRESET_ICONS: Record<string, React.ReactNode> = {
  simple_kanban: <IconLayoutKanban size={32} />,
  dev_team: <IconColumns size={32} />,
  full_sdlc: <IconSettings size={32} />,
};

function BoardPresetPicker({ projectId, presets }: { projectId: number; presets: BoardPreset[] }) {
  const [creating, setCreating] = useState<string | null>(null);

  const handleCreate = async (presetKey: string) => {
    setCreating(presetKey);
    try {
      await apiFetch(apiV1ProjectBoardPath(projectId), {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ board: { preset: presetKey, name: 'Project Board' } }),
      });
      router.reload();
    } catch {
      setCreating(null);
    }
  };

  return (
    <Box py={60} maw={700} mx="auto">
      <Stack align="center" mb="xl">
        <ThemeIcon size={64} radius="xl" variant="light" color="blue">
          <IconLayoutKanban size={32} />
        </ThemeIcon>
        <Text size="xl" fw={700}>
          Create your task board
        </Text>
        <Text c="dimmed" size="sm" ta="center" maw={400}>
          Pick a template that fits your workflow. You can customize columns later.
        </Text>
      </Stack>

      <SimpleGrid cols={{ base: 1, sm: presets.length >= 3 ? 3 : presets.length }} spacing="md">
        {presets.map((preset) => (
          <Card
            key={preset.key}
            withBorder
            padding="lg"
            radius="md"
            style={{ cursor: creating ? 'not-allowed' : 'pointer', transition: 'transform 0.15s, box-shadow 0.15s' }}
            onMouseEnter={(e) => {
              if (!creating) {
                (e.currentTarget as HTMLElement).style.transform = 'translateY(-2px)';
                (e.currentTarget as HTMLElement).style.boxShadow = 'var(--mantine-shadow-md)';
              }
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.transform = '';
              (e.currentTarget as HTMLElement).style.boxShadow = '';
            }}
            onClick={() => !creating && handleCreate(preset.key)}
          >
            <Stack align="center" gap="sm">
              <ThemeIcon size={48} radius="md" variant="light" color="blue">
                {PRESET_ICONS[preset.key] ?? <IconLayoutKanban size={28} />}
              </ThemeIcon>
              <Text fw={600} ta="center">
                {preset.displayName}
              </Text>
              <Group gap={4} wrap="wrap" justify="center">
                {preset.columns.map((col) => (
                  <Badge key={col} size="xs" variant="outline" color="gray">
                    {col}
                  </Badge>
                ))}
              </Group>
              <Button
                fullWidth
                variant="light"
                loading={creating === preset.key}
                disabled={!!creating && creating !== preset.key}
              >
                Use this template
              </Button>
            </Stack>
          </Card>
        ))}
      </SimpleGrid>
    </Box>
  );
}

// --- View Preset Menu ---

function ViewPresetMenu({
  projectId,
  viewPresets,
  currentUserId,
  filters,
  onApplyFilters,
}: {
  projectId: number;
  viewPresets: ViewPreset[];
  currentUserId: number;
  filters: BoardFilters;
  onApplyFilters: (filters: BoardFilters) => void;
}) {
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const [saveShared, setSaveShared] = useState(false);
  const [saving, setSaving] = useState(false);

  const hasActiveFilters = !!(
    filters.assigneeId ||
    filters.taskType ||
    filters.priority ||
    filters.tags.length > 0 ||
    filters.search
  );

  const builtInPresets = useMemo(
    () => [
      {
        id: 'my-work',
        name: 'My Work',
        icon: <IconUser size={14} />,
        apply: () =>
          onApplyFilters({
            assigneeId: String(currentUserId),
            taskType: null,
            priority: null,
            tags: [],
            search: '',
          }),
      },
      {
        id: 'all-bugs',
        name: 'All Bugs',
        icon: <IconBug size={14} />,
        apply: () =>
          onApplyFilters({
            assigneeId: null,
            taskType: 'bug',
            priority: null,
            tags: [],
            search: '',
          }),
      },
    ],
    [currentUserId, onApplyFilters],
  );

  const filtersToJson = (): Record<string, unknown> => {
    const result: Record<string, unknown> = {};
    if (filters.assigneeId) result.assignee_id = filters.assigneeId;
    if (filters.taskType) result.task_type = filters.taskType;
    if (filters.priority) result.priority = filters.priority;
    if (filters.tags.length > 0) result.tags = filters.tags;
    if (filters.search) result.search = filters.search;
    return result;
  };

  const applyViewPreset = (preset: ViewPreset) => {
    const f = preset.filters as Record<string, unknown>;
    onApplyFilters({
      assigneeId: f.assignee_id ? String(f.assignee_id) : null,
      taskType: (f.task_type as string) ?? null,
      priority: (f.priority as string) ?? null,
      tags: (f.tags as string[]) ?? [],
      search: (f.search as string) ?? '',
    });
  };

  const handleSave = async () => {
    if (!saveName.trim()) return;
    setSaving(true);
    try {
      await apiFetch(apiV1ProjectViewPresetsPath(projectId), {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({
          boardViewPreset: { name: saveName.trim(), shared: saveShared, filters: filtersToJson() },
        }),
      });
      router.reload({ only: ['view_presets'] });
      setSaveOpen(false);
      setSaveName('');
      setSaveShared(false);
    } catch {
      /* ignore */
    }
    setSaving(false);
  };

  const handleDelete = async (presetId: number) => {
    try {
      await apiFetch(apiV1ProjectViewPresetPath(projectId, presetId), { method: 'DELETE' });
      router.reload({ only: ['view_presets'] });
    } catch {
      /* ignore */
    }
  };

  return (
    <>
      <Menu shadow="md" width={220} position="bottom-start">
        <Menu.Target>
          <Button variant="subtle" size="sm" leftSection={<IconFilter size={14} />} px="xs">
            Presets
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Label>Built-in</Menu.Label>
          {builtInPresets.map((bp) => (
            <Menu.Item key={bp.id} leftSection={bp.icon} onClick={bp.apply}>
              {bp.name}
            </Menu.Item>
          ))}

          {viewPresets.length > 0 && (
            <>
              <Menu.Divider />
              <Menu.Label>Saved</Menu.Label>
              {viewPresets.map((vp) => (
                <Menu.Item
                  key={vp.id}
                  onClick={() => applyViewPreset(vp)}
                  rightSection={
                    vp.userId === currentUserId ? (
                      <ActionIcon
                        size="xs"
                        variant="subtle"
                        color="red"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDelete(vp.id);
                        }}
                      >
                        <IconX size={12} />
                      </ActionIcon>
                    ) : null
                  }
                  leftSection={<IconBookmark size={14} />}
                >
                  <Group gap={4}>
                    <Text size="sm">{vp.name}</Text>
                    {vp.shared && (
                      <Badge size="xs" variant="light" color="gray">
                        shared
                      </Badge>
                    )}
                  </Group>
                </Menu.Item>
              ))}
            </>
          )}

          {hasActiveFilters && (
            <>
              <Menu.Divider />
              <Menu.Item leftSection={<IconPlus size={14} />} onClick={() => setSaveOpen(true)}>
                Save current filters
              </Menu.Item>
            </>
          )}
        </Menu.Dropdown>
      </Menu>

      <Modal opened={saveOpen} onClose={() => setSaveOpen(false)} title="Save Filter Preset" centered size="sm">
        <Stack gap="md">
          <TextInput
            label="Preset name"
            placeholder="e.g. Sprint 5 tasks"
            value={saveName}
            onChange={(e) => setSaveName(e.currentTarget.value)}
            autoFocus
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSave();
            }}
          />
          <Checkbox
            label="Share with team members"
            checked={saveShared}
            onChange={(e) => setSaveShared(e.currentTarget.checked)}
          />
          <Group justify="flex-end">
            <Button variant="outline" onClick={() => setSaveOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleSave} loading={saving} disabled={!saveName.trim()}>
              Save
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}

// --- Main Page ---

function normalizeTask(t: Task): Task {
  return {
    ...t,
    title: t.title ?? '',
    tags: t.tags ?? [],
    pendingGates: t.pendingGates ?? [],
    recentWorkflowRuns: t.recentWorkflowRuns ?? [],
    assetsCount: t.assetsCount ?? 0,
    childrenCount: t.childrenCount ?? 0,
    commentsCount: t.commentsCount ?? 0,
  };
}

const BoardPage = () => {
  const {
    project,
    board,
    boardPresets,
    columns,
    tasks: serverTasks,
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
  } = usePage<{ props: Props }>().props as unknown as Props;

  const [localTasks, setLocalTasks] = useState<Task[]>(() => (serverTasks ?? []).map(normalizeTask));
  useEffect(() => {
    setLocalTasks((serverTasks ?? []).map(normalizeTask));
  }, [serverTasks]);

  const selectedTask = selectedTaskProp ? normalizeTask(selectedTaskProp) : null;

  // Sync the updated selectedTask into localTasks after partial reloads that only refresh
  // the selected task (e.g. editing fields, triggering a workflow, removing a wait).
  // Without this, task cards in the board columns would show stale data until the next
  // full-tasks reload.
  useEffect(() => {
    if (!selectedTaskProp) return;

    const nextTask = normalizeTask(selectedTaskProp);

    setLocalTasks((prev) => prev.map((t) => (t.id === nextTask.id ? nextTask : t)));
  }, [selectedTaskProp]);

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
  const [activeTask, setActiveTask] = useState<Task | null>(null);
  const [hoverColumnId, setHoverColumnId] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [filters, setFilters] = useState<BoardFilters>(EMPTY_FILTERS);
  const collapsedColumnsStorageKey = board ? `board:${board.id}:collapsedColumns` : null;
  const [collapsedColumns, setCollapsedColumns] = useLocalStorageSet<number>(collapsedColumnsStorageKey, new Set());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  const openTask = useCallback(
    (task: Task | null) => {
      router.get(boardUrl, { task: task?.id }, { preserveState: true, preserveScroll: true });
    },
    [boardUrl],
  );

  const closeTask = useCallback(() => {
    router.get(boardUrl, {}, { preserveState: true, preserveScroll: true });
  }, [boardUrl]);

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

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

  const allTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const t of localTasks) for (const tag of t.tags ?? []) tagSet.add(tag);
    return [...tagSet].sort();
  }, [localTasks]);

  const filteredTasks = useMemo(() => {
    return localTasks.filter((t) => {
      if (filters.search && !(t.title ?? '').toLowerCase().includes(filters.search.toLowerCase())) return false;
      if (filters.assigneeId && String(t.assigneeId) !== filters.assigneeId) return false;
      if (filters.taskType && t.taskType !== filters.taskType) return false;
      if (filters.priority && t.priority !== filters.priority) return false;
      if (filters.tags.length > 0 && !filters.tags.every((ft) => (t.tags ?? []).includes(ft))) return false;
      return true;
    });
  }, [localTasks, filters]);

  const tasksByColumn = useMemo(() => {
    const map: Record<number, Task[]> = {};
    for (const col of columns) map[col.id] = [];
    for (const task of filteredTasks) {
      if (map[task.boardColumnId]) map[task.boardColumnId].push(task);
    }
    for (const col of columns) map[col.id].sort((a, b) => a.position - b.position);
    return map;
  }, [columns, filteredTasks]);

  const form = useForm<TaskFormValues>({
    validate: zodResolver(taskSchema),
    initialValues: {
      title: '',
      description: '',
      taskType: 'not_specified',
      priority: '',
      assigneeId: null,
      boardColumnId: '',
    },
  });

  const handleCreateTask = useCallback(
    async (values: TaskFormValues) => {
      if (!board) return;
      setLoading(true);
      try {
        const res = await apiFetch(apiV1ProjectTasksPath(project.id), {
          method: 'POST',
          headers: jsonHeaders,
          body: JSON.stringify({
            boardTask: {
              title: values.title,
              description: values.description,
              taskType: values.taskType || 'not_specified',
              priority: values.priority || null,
              assigneeId: values.assigneeId ? Number(values.assigneeId) : null,
              boardColumnId: Number(values.boardColumnId),
            },
          }),
        });
        if (res.ok) {
          const created = await res.json();
          setCreateOpen(false);
          form.reset();
          setLocalTasks((prev) => [...prev, normalizeTask(created)]);
          // cable will confirm with authoritative server state
        }
      } catch {
        /* ignore */
      }
      setLoading(false);
    },
    [board, project.id, form],
  );

  const handleDeleteTask = useCallback(
    async (taskId: number) => {
      try {
        await apiFetch(apiV1ProjectTaskPath(project.id, taskId), { method: 'DELETE' });
        closeTask();
      } catch {
        /* ignore */
      }
    },
    [project.id, closeTask],
  );

  const preDragSnapshotRef = useRef<Task[]>([]);
  const draggedIdRef = useRef<number | null>(null);

  const handleDragStart = useCallback(
    (event: DragStartEvent) => {
      const taskData = event.active.data.current?.task as Task | undefined;
      setActiveTask(taskData ?? null);
      setHoverColumnId(null);
      draggedIdRef.current = taskData?.id ?? null;
      preDragSnapshotRef.current = localTasks.map((t) => ({ ...t }));
    },
    [localTasks],
  );

  const handleDragOver = useCallback((event: DragOverEvent) => {
    const { over } = event;
    if (!over) {
      setHoverColumnId(null);
      return;
    }

    let targetColumnId: number | null = null;
    if (over.data.current?.columnId) {
      targetColumnId = over.data.current.columnId as number;
    } else if (over.data.current?.task) {
      const overTask = over.data.current.task as Task;
      targetColumnId = overTask.boardColumnId;
    }

    setHoverColumnId(targetColumnId);

    if (targetColumnId == null) return;
    const activeId = draggedIdRef.current;
    if (activeId == null) return;

    setLocalTasks((prev) => {
      const activeItem = prev.find((t) => t.id === activeId);
      if (!activeItem || activeItem.boardColumnId === targetColumnId) return prev;

      const targetTasks = prev.filter((t) => t.boardColumnId === targetColumnId);
      const maxPos = targetTasks.reduce((max, t) => Math.max(max, t.position), -1);

      return prev.map((t) => (t.id === activeId ? { ...t, boardColumnId: targetColumnId!, position: maxPos + 1 } : t));
    });
  }, []);

  const handleDragEnd = useCallback(
    async (event: DragEndEvent) => {
      setActiveTask(null);
      setHoverColumnId(null);
      const { over } = event;
      if (!over || !board) {
        draggedIdRef.current = null;
        return;
      }

      const origTask = preDragSnapshotRef.current.find((t) => t.id === draggedIdRef.current);
      draggedIdRef.current = null;
      if (!origTask) return;

      let targetColumnId: number;
      let targetPosition: number | undefined;

      if (over.data.current?.task) {
        const overTask = over.data.current.task as Task;
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

      setLocalTasks((prev) => {
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
        await apiFetch(moveApiV1ProjectTaskPath(project.id, origTask.id), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ columnId: targetColumnId, position }),
        });
        // cable confirms via board.touch → broadcast_refresh_to(board) → only: ['tasks', 'columns', 'recent_activities']
      } catch {
        setLocalTasks(preDragSnapshotRef.current);
      }
    },
    [board, project.id],
  );

  const openCreateForColumn = (columnId: number) => {
    form.setFieldValue('boardColumnId', String(columnId));
    setCreateOpen(true);
  };

  const handleToggleCollapse = useCallback((colId: number) => {
    setCollapsedColumns((prev) => {
      const next = new Set(prev);
      if (next.has(colId)) next.delete(colId);
      else next.add(colId);
      return next;
    });
  }, []);

  const handleToggleAll = useCallback(() => {
    const allIds = columns.map((c) => c.id);
    setCollapsedColumns((prev) => (prev.size === allIds.length ? new Set() : new Set(allIds)));
  }, [columns]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (e.target as HTMLElement)?.isContentEditable)
        return;

      if (e.key === 'n' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        setCreateOpen(true);
      } else if (e.key === '/' && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        searchInputRef.current?.focus();
      } else if (e.key === 'Escape') {
        closeTask();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [closeTask]);

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
        {/* Filter bar */}
        <Group gap="sm" mb="sm" wrap="wrap" align="center">
          <ViewPresetMenu
            projectId={project.id}
            viewPresets={viewPresets ?? []}
            currentUserId={currentUserId ?? 0}
            filters={filters}
            onApplyFilters={setFilters}
          />
          <Select
            placeholder="Assignee"
            data={[{ value: '', label: 'All' }, ...members.map((m) => ({ value: String(m.id), label: m.name }))]}
            value={filters.assigneeId ?? ''}
            onChange={(v) => setFilters((f) => ({ ...f, assigneeId: v || null }))}
            clearable
            size="sm"
            w={140}
          />
          <Select
            placeholder="Type"
            data={[
              { value: '', label: 'All types' },
              { value: 'epic', label: 'Epic' },
              { value: 'story', label: 'Story' },
              { value: 'bug', label: 'Bug' },
            ]}
            value={filters.taskType ?? ''}
            onChange={(v) => setFilters((f) => ({ ...f, taskType: v || null }))}
            clearable
            size="sm"
            w={120}
          />
          <Select
            placeholder="Priority"
            data={[
              { value: '', label: 'All priorities' },
              { value: 'critical', label: 'Critical' },
              { value: 'high', label: 'High' },
              { value: 'medium', label: 'Medium' },
              { value: 'low', label: 'Low' },
            ]}
            value={filters.priority ?? ''}
            onChange={(v) => setFilters((f) => ({ ...f, priority: v || null }))}
            clearable
            size="sm"
            w={130}
          />
          {allTags.length > 0 && (
            <MultiSelect
              placeholder="Tags"
              data={allTags}
              value={filters.tags}
              onChange={(v) => setFilters((f) => ({ ...f, tags: v }))}
              clearable
              searchable
              size="sm"
              w={160}
              maxDropdownHeight={200}
            />
          )}
          <TextInput
            ref={searchInputRef}
            placeholder="Search title..."
            leftSection={<IconSearch size={14} />}
            value={filters.search}
            onChange={(e) => {
              const v = e.currentTarget.value;
              setFilters((f) => ({ ...f, search: v }));
            }}
            size="sm"
            w={180}
          />
          {hasActiveFilters && (
            <Button
              variant="subtle"
              size="sm"
              leftSection={<IconX size={12} />}
              onClick={() => setFilters(EMPTY_FILTERS)}
            >
              Clear
            </Button>
          )}
          <Box style={{ flex: 1 }} />
          <Tooltip label={collapsedColumns.size === columns.length ? 'Expand all' : 'Collapse all'}>
            <ActionIcon variant="subtle" size="sm" onClick={handleToggleAll}>
              {collapsedColumns.size === columns.length ? (
                <IconArrowsMaximize size={16} />
              ) : (
                <IconArrowsMinimize size={16} />
              )}
            </ActionIcon>
          </Tooltip>
          <Tooltip label="Board settings">
            <ActionIcon variant="subtle" size="sm" onClick={() => setSettingsOpen(true)}>
              <IconSettings size={16} />
            </ActionIcon>
          </Tooltip>
        </Group>

        {/* Board area */}
        <DndContext
          sensors={sensors}
          collisionDetection={collisionDetection}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
        >
          <Box className={styles.boardArea}>
            {columns.map((col) => (
              <BoardColumn
                key={col.id}
                column={col}
                tasks={tasksByColumn[col.id] ?? []}
                onAddTask={openCreateForColumn}
                onTaskClick={openTask}
                collapsed={collapsedColumns.has(col.id)}
                onToggleCollapse={handleToggleCollapse}
                isFiltered={hasActiveFilters}
                isDropTarget={hoverColumnId === col.id}
              />
            ))}
          </Box>
          <DragOverlay dropAnimation={{ duration: 200, easing: 'cubic-bezier(0.25, 1, 0.5, 1)' }}>
            {activeTask ? (
              <Box w={280} style={{ transform: 'rotate(2deg)', filter: 'drop-shadow(0 8px 16px rgba(0,0,0,0.3))' }}>
                <TaskCardUI task={activeTask} isDragOverlay />
              </Box>
            ) : null}
          </DragOverlay>
        </DndContext>

        <ActivityFeedPanel projectId={project.id} initialActivities={recentActivities ?? []} />
      </Box>

      <TaskDetailSidebar
        task={selectedTask}
        allTasks={localTasks}
        onClose={closeTask}
        onDelete={handleDeleteTask}
        onOpenTask={openTask}
        projectId={project.id}
        columns={columns}
        members={members}
        comments={taskComments ?? []}
        activities={taskActivities ?? []}
        taskAssets={taskAssetsProp ?? []}
        workflowRuns={taskWorkflowRuns ?? []}
        stats={taskStatistics ?? null}
      />
      <BoardSettingsDialog
        opened={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        projectId={project.id}
        columns={columns}
      />

      {/* Create Task Modal */}
      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="New Task" centered>
        <form onSubmit={form.onSubmit(handleCreateTask)}>
          <Stack gap="md">
            <TextInput label="Title" required {...form.getInputProps('title')} />
            <Textarea label="Description" autosize minRows={2} {...form.getInputProps('description')} />
            <Select
              label="Type"
              data={[
                { value: 'not_specified', label: 'Not specified' },
                { value: 'epic', label: 'Epic' },
                { value: 'story', label: 'Story' },
                { value: 'bug', label: 'Bug' },
              ]}
              {...form.getInputProps('taskType')}
            />
            <Select
              label="Priority"
              data={[
                { value: '', label: 'None' },
                { value: 'critical', label: 'Critical' },
                { value: 'high', label: 'High' },
                { value: 'medium', label: 'Medium' },
                { value: 'low', label: 'Low' },
              ]}
              clearable
              {...form.getInputProps('priority')}
            />
            <Select
              label="Assignee"
              data={members.map((m) => ({ value: String(m.id), label: m.name }))}
              clearable
              searchable
              {...form.getInputProps('assigneeId')}
            />
            <Select
              label="Column"
              data={columns.map((c) => ({ value: String(c.id), label: c.name }))}
              required
              {...form.getInputProps('boardColumnId')}
            />
            <Group justify="flex-end">
              <Button variant="outline" onClick={() => setCreateOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" loading={loading}>
                Create
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </>
  );
};

setPageLayout(BoardPage, persistentProjectLayout);

export default BoardPage;
