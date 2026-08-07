import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
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
import {
  SortableContext,
  verticalListSortingStrategy,
  horizontalListSortingStrategy,
  sortableKeyboardCoordinates,
  useSortable,
  arrayMove,
} from '@dnd-kit/sortable';
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
  Paper,
  Select,
  SimpleGrid,
  Skeleton,
  Stack,
  Tabs,
  Text,
  TextInput,
  Textarea,
  ThemeIcon,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import {
  IconActivity,
  IconAdjustmentsHorizontal,
  IconArchive,
  IconArchiveOff,
  IconArrowLeft,
  IconArrowRight,
  IconArrowsMaximize,
  IconArrowsMinimize,
  IconAlertCircle,
  IconBolt,
  IconBookmark,
  IconBug,
  IconCheck,
  IconChevronDown,
  IconChevronsRight,
  IconCircleCheck,
  IconClock,
  IconCloudUpload,
  IconCoin,
  IconColumns,
  IconDots,
  IconDownload,
  IconFlag,
  IconFold,
  IconGripVertical,
  IconHourglass,
  IconLayoutGrid,
  IconLayoutKanban,
  IconListDetails,
  IconLink,
  IconMessage,
  IconPencil,
  IconPlus,
  IconRefresh,
  IconRobot,
  IconSearch,
  IconSend,
  IconSettings,
  IconTag,
  IconTrash,
  IconChartBar,
  IconExternalLink,
  IconFileTypePdf,
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
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useLocalStorageSet } from 'shared/lib/hooks/useLocalStorage';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import {
  apiV1ProjectTasksPath,
  apiV1ProjectTaskPath,
  apiV1ProjectTaskCommentsPath,
  apiV1ProjectTaskAssetsPath,
  apiV1ProjectTaskAssetPath,
  apiV1ProjectTaskGatePath,
  moveApiV1ProjectTaskPath,
  archiveApiV1ProjectTaskPath,
  unarchiveApiV1ProjectTaskPath,
  triggerWorkflowApiV1ProjectTaskPath,
  apiV1ProjectColumnsPath,
  apiV1ProjectColumnPath,
  reorderApiV1ProjectColumnsPath,
  apiV1ProjectActivitiesPath,
  apiV1ProjectBoardPath,
  apiV1ProjectViewPresetsPath,
  apiV1ProjectViewPresetPath,
} from 'shared/routes';
import { CHART_SERIES } from 'shared/theme/chartPalette';
import { PageHeader } from 'shared/ui/PageHeader';

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
  // Serialized only on the task detail payload (TaskDetailResource), so the drawer can name the
  // parent epic even when the epic is archived and therefore absent from the board's task list.
  parentTaskTitle?: string | null;
  tags: string[];
  archived: boolean;
  commentsCount: number;
  childrenCount: number;
  assetsCount?: number;
  recentWorkflowRuns: Array<{
    id: number;
    state: string;
    createdAt: string;
    durationSeconds?: number | null;
    totalCostCents?: number | null;
    errorMessage?: string | null;
  }>;
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

// Categorical, so these read from the chart ramp rather than Material hexes;
// priority is a severity scale, so it reads from the status tokens.
const TASK_TYPE_COLORS: Record<string, string> = {
  epic: 'var(--app-chart-5)',
  story: 'var(--app-chart-2)',
  bug: 'var(--app-danger-fg)',
  not_specified: 'var(--app-text-tertiary)',
};

const PRIORITY_COLORS: Record<string, string> = {
  critical: 'var(--app-danger-fg)',
  high: 'var(--app-warning-fg)',
  medium: 'var(--app-chart-4)',
  low: 'var(--app-success-fg)',
};

const WORKFLOW_ACTIVE_STATES = new Set(['pending', 'running', 'paused']);

// Helper to get workflow status indicator color
const workflowStatusColor = (state: string): string => {
  if (WORKFLOW_ACTIVE_STATES.has(state)) return 'var(--app-warning-fg)';
  if (state === 'failed') return 'var(--app-danger-fg)';
  if (state === 'completed' || state === 'succeeded') return 'var(--app-success-fg)';
  return 'var(--app-text-tertiary)';
};

const CHART_COLORS = CHART_SERIES;
const CHART_TOOLTIP_STYLE: React.CSSProperties = {
  backgroundColor: 'var(--app-bg-default)',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--app-text-primary)',
};

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
  showArchived: boolean;
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

function avatarInitials(name: string): string {
  return name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

// --- TaskCard (no grip handle, legacy style) ---

function SortableTaskCard({
  task,
  href,
  onClick,
  onRetry,
}: {
  task: Task;
  href?: string;
  onClick?: (t: Task) => void;
  onRetry?: (task: Task) => void;
}) {
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
      <TaskCardUI task={task} href={href} onClick={onClick} onRetry={onRetry} />
    </Box>
  );
}

// A compact, draggable stand-in for a task shown inside a collapsed column strip.
// It keeps the ticket present in the DOM as a sortable item so a drag can still be
// initiated from a collapsed source column (board requirement 3). It renders no task
// title text — only a small grab bar — so a collapsed column stays lightweight and does
// not reveal card content while folded.
function CollapsedTaskChip({ task }: { task: Task }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: `task-${task.id}`,
    data: { type: 'task', task },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <Box
      ref={setNodeRef}
      aria-label={`Drag ${task.title}`}
      title={task.title}
      style={{
        ...style,
        width: 30,
        height: 12,
        borderRadius: 3,
        backgroundColor: 'var(--app-border-default)',
        cursor: 'grab',
        touchAction: 'none',
        flexShrink: 0,
      }}
      {...attributes}
      {...listeners}
    />
  );
}

function TaskCardUI({
  task,
  href,
  onClick,
  isDragOverlay,
  onRetry,
}: {
  task: Task;
  href?: string;
  onClick?: (t: Task) => void;
  isDragOverlay?: boolean;
  onRetry?: (task: Task) => void;
}) {
  const visibleTags = (task.tags ?? []).slice(0, 3);
  const overflowCount = (task.tags ?? []).length - 3;

  const latestRun = (task.recentWorkflowRuns ?? [])[0] ?? null;
  const isRunning = latestRun && WORKFLOW_ACTIVE_STATES.has(latestRun.state);
  const isFailed = latestRun?.state === 'failed';
  const isSuccess = latestRun && (latestRun.state === 'completed' || latestRun.state === 'succeeded');

  let dotColor: string | undefined;
  let runLabel: string | undefined;
  if (isRunning && latestRun) {
    dotColor = 'var(--app-warning-fg)';
    runLabel = latestRun.state;
  } else if (isFailed) {
    dotColor = 'var(--app-danger-fg)';
    runLabel = 'failed';
  } else if (isSuccess && latestRun) {
    dotColor = 'var(--app-success-fg)';
    runLabel = latestRun.state;
  }

  const isLink = !isDragOverlay && !!href;
  const handleClick = (e: React.MouseEvent<HTMLElement>) => {
    if (!isLink) {
      onClick?.(task);
      return;
    }
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    onClick?.(task);
  };

  return (
    <Paper
      component={isLink ? 'a' : 'div'}
      href={isLink ? href : undefined}
      draggable={isLink ? false : undefined}
      radius="sm"
      p="xs"
      mb={8}
      withBorder
      bg="var(--app-bg-elevated)"
      onClick={handleClick}
      style={{
        cursor: 'pointer',
        transition: 'border-color 0.15s, background-color 0.15s',
        borderColor: 'var(--app-border-strong)',
        opacity: task.archived ? 0.6 : 1,
        display: 'block',
        color: 'inherit',
        textDecoration: 'none',
        borderRadius: 8,
        padding: '12px 13px',
      }}
      onMouseEnter={(e: React.MouseEvent<HTMLElement>) => {
        (e.currentTarget as HTMLElement).style.borderColor = 'var(--mantine-color-brand-4)';
        (e.currentTarget as HTMLElement).style.backgroundColor = 'var(--app-bg-paper)';
      }}
      onMouseLeave={(e: React.MouseEvent<HTMLElement>) => {
        (e.currentTarget as HTMLElement).style.borderColor = 'var(--app-border-strong)';
        (e.currentTarget as HTMLElement).style.backgroundColor = 'var(--app-bg-elevated)';
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
                backgroundColor: PRIORITY_COLORS[task.priority] ?? 'var(--app-text-tertiary)',
                flexShrink: 0,
              }}
            />
          </Tooltip>
        )}
        <Text size="sm" fw={500} lh={1.3} style={{ flex: 1, wordBreak: 'break-word', fontSize: 13 }}>
          {task.title}
        </Text>
      </Group>

      {/* Workflow status chip — filled colored badge (AC-11) */}
      {latestRun && dotColor && runLabel && (
        <Group gap={4} mt={6} align="center">
          <ActionIcon size="xs" variant="subtle" color="orange" style={{ cursor: 'default', flexShrink: 0 }}>
            <IconBolt size={11} />
          </ActionIcon>
          <Badge
            size="xs"
            variant="filled"
            color={isFailed ? 'red' : isRunning ? 'orange' : 'green'}
            leftSection={
              <Box
                w={5}
                h={5}
                className={isRunning ? styles.workflowDotActive : undefined}
                style={{ borderRadius: '50%', backgroundColor: 'rgba(255,255,255,0.7)', flexShrink: 0 }}
              />
            }
            style={{ fontSize: 10, cursor: 'default', textTransform: 'uppercase', letterSpacing: 0.3 }}
          >
            {isFailed ? 'Failed' : isRunning ? 'Running' : 'Succeeded'}
          </Badge>
        </Group>
      )}

      {/* Type chip + tags */}
      <Group gap={4} mt={6} wrap="wrap">
        {task.archived && (
          <Badge size="xs" variant="light" color="gray" leftSection={<IconArchive size={9} />} style={{ fontSize: 10 }}>
            Archived
          </Badge>
        )}
        {task.taskType && task.taskType !== 'not_specified' && (
          <Badge
            size="xs"
            variant="filled"
            style={{
              backgroundColor: TASK_TYPE_COLORS[task.taskType] ?? 'var(--app-text-tertiary)',
              color: 'var(--app-on-primary)',
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

      {/* Error message on failed cards */}
      {isFailed && latestRun?.errorMessage && (
        <Text size="xs" c="red.4" mt={4} style={{ fontSize: 11, lineHeight: 1.4 }} lineClamp={2}>
          {latestRun.errorMessage}
        </Text>
      )}

      {/* Retry button on failed cards (AC-12) */}
      {isFailed && onRetry && (
        <Box mt={6}>
          <Button
            size="compact-xs"
            variant="subtle"
            color="red"
            leftSection={<IconRefresh size={11} />}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              onRetry?.(task);
            }}
            style={{ fontSize: 11, paddingLeft: 0 }}
          >
            Retry run
          </Button>
        </Box>
      )}

      {/* Duration + cost on succeeded cards */}
      {isSuccess && latestRun && (latestRun.durationSeconds != null || latestRun.totalCostCents != null) && (
        <Group gap={8} mt={4}>
          {latestRun.durationSeconds != null && (
            <Text size="xs" c="dimmed" style={{ fontSize: 11 }}>
              ⏱ {formatDuration(latestRun.durationSeconds)}
            </Text>
          )}
          {latestRun.totalCostCents != null && (
            <Text size="xs" c="dimmed" style={{ fontSize: 11 }}>
              {formatCostCents(latestRun.totalCostCents)}
            </Text>
          )}
        </Group>
      )}

      {/* Footer: assignee + comments */}
      <Group justify="space-between" mt={6}>
        <Group gap={6}>
          {task.assigneeName && (
            <Tooltip label={task.assigneeName}>
              <Avatar
                size={20}
                radius="xl"
                color="brand"
                variant="filled"
                /* styles, not style: Mantine's placeholder span sets its own color. */
                styles={{ placeholder: { fontSize: 10, color: 'var(--app-on-primary)' } }}
              >
                {avatarInitials(task.assigneeName)}
              </Avatar>
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
  taskHref,
  onAddTask,
  onTaskClick,
  onRetryTask,
  collapsed,
  onToggleCollapse,
  onMoveLeft,
  onMoveRight,
  onDeleteColumn,
  onRenameColumn,
  isFiltered,
  isDropTarget,
  canExecute,
}: {
  column: Column;
  tasks: Task[];
  taskHref: (task: Task) => string;
  onAddTask: (columnId: number) => void;
  onTaskClick: (task: Task) => void;
  onRetryTask: (task: Task) => void;
  collapsed: boolean;
  onToggleCollapse: (id: number) => void;
  onMoveLeft?: () => void;
  onMoveRight?: () => void;
  onDeleteColumn?: () => void;
  onRenameColumn?: (columnId: number, name: string) => void;
  isFiltered: boolean;
  isDropTarget: boolean;
  canExecute: boolean;
}) {
  const {
    setNodeRef,
    listeners: colListeners,
    transform: colTransform,
    transition: colTransition,
    isDragging: colIsDragging,
  } = useSortable({
    id: `col-${column.id}`,
    data: { type: 'column', columnId: column.id },
  });
  // Keep the droppable registration for task drop targets
  const { setNodeRef: setDropRef } = useDroppable({ id: `column-${column.id}`, data: { columnId: column.id } });

  const setRefs = (el: HTMLElement | null) => {
    setNodeRef(el);
    setDropRef(el);
  };

  const colStyle = {
    transform: colTransform ? `translate3d(${colTransform.x}px, ${colTransform.y}px, 0)` : undefined,
    transition: colTransition,
    opacity: colIsDragging ? 0.4 : 1,
    zIndex: colIsDragging ? 10 : undefined,
  };

  const taskIds = useMemo(() => tasks.map((t) => `task-${t.id}`), [tasks]);
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState('');
  const renameInputRef = useRef<HTMLInputElement>(null);

  // Focus the input after Mantine's Menu close has finished restoring focus to the trigger.
  // Without the timeout, Menu focus-restoration fires after React's commit and immediately
  // blurs the freshly-mounted input, triggering onBlur → commitRename → input disappears.
  useEffect(() => {
    if (!renaming) return;
    const t = setTimeout(() => renameInputRef.current?.focus(), 0);
    return () => clearTimeout(t);
  }, [renaming]);

  const overStyle = {
    outline: isDropTarget ? '2px solid var(--mantine-color-brand-6)' : '2px solid transparent',
    outlineOffset: -2,
    transition: 'outline-color 0.15s ease',
  };

  const startRename = () => {
    setRenameValue(column.name);
    setRenaming(true);
  };

  const commitRename = () => {
    setRenaming(false);
    const val = renameValue.trim();
    if (!val || val === column.name) return;
    onRenameColumn?.(column.id, val);
  };

  if (collapsed) {
    return (
      <Box
        ref={setRefs}
        onClick={() => onToggleCollapse(column.id)}
        style={{
          flex: '0 0 46px',
          minWidth: 46,
          maxWidth: 46,
          backgroundColor: 'var(--app-bg-elevated)',
          border: '1px solid var(--app-border-default)',
          borderRadius: 10,
          maxHeight: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'flex-start',
          cursor: 'pointer',
          padding: '12px 0',
          gap: 12,
          ...overStyle,
        }}
      >
        {/* Expand chevrons button */}
        <Box
          style={{
            width: 22,
            height: 22,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: 4,
            color: 'var(--mantine-color-dimmed)',
            flexShrink: 0,
          }}
        >
          <IconChevronsRight size={14} />
        </Box>

        {/* Column name — vertical-rl, no rotation, reads naturally */}
        <Tooltip label={column.name} position="right">
          <div
            style={{
              writingMode: 'vertical-rl',
              color: 'var(--mantine-color-text)',
              fontWeight: 600,
              fontSize: 13,
              letterSpacing: '-0.01em',
              userSelect: 'none',
              cursor: 'pointer',
              overflow: 'hidden',
            }}
          >
            {column.name}
          </div>
        </Tooltip>

        {/* Task count — bordered pill matching reference */}
        <div
          style={{
            fontSize: 10,
            color: 'var(--mantine-color-dimmed)',
            background: 'var(--app-bg-default)',
            border: '1px solid var(--app-border-default)',
            borderRadius: 3,
            padding: '1px 6px',
            lineHeight: 1.6,
            flexShrink: 0,
          }}
        >
          {tasks.length}
        </div>

        {/* Workflow status indicator for automated columns */}
        {column.workflowBinding && tasks.length > 0 && (
          <div
            style={{
              width: 8,
              height: 8,
              borderRadius: '50%',
              backgroundColor: workflowStatusColor(
                tasks.flatMap((t) => t.recentWorkflowRuns ?? [])[0]?.state || 'idle',
              ),
              flexShrink: 0,
            }}
          />
        )}

        {/* Draggable ticket chips — keep the tickets reachable so they can be dragged out of a
            collapsed source column (board requirement 3). No title text is rendered here. */}
        {tasks.length > 0 && (
          <SortableContext items={taskIds} strategy={verticalListSortingStrategy}>
            <Box
              onClick={(e) => e.stopPropagation()}
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 6,
                width: '100%',
                overflowY: 'auto',
                paddingTop: 2,
              }}
            >
              {tasks.map((task) => (
                <CollapsedTaskChip key={task.id} task={task} />
              ))}
            </Box>
          </SortableContext>
        )}
      </Box>
    );
  }

  return (
    <Box
      ref={setRefs}
      style={{
        flex: '0 0 300px',
        minWidth: 300,
        display: 'flex',
        flexDirection: 'column',
        backgroundColor: 'var(--app-bg-elevated)',
        border: '1px solid var(--app-border-default)',
        borderRadius: 10,
        overflow: 'hidden',
        ...overStyle,
        ...colStyle,
      }}
    >
      {/* Header — collapse toggle icon; the column title carries the drag-to-reorder handle */}
      <Box
        style={{
          height: 44,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '0 10px 0 4px',
          borderBottom: '1px solid var(--app-border-default)',
          flexShrink: 0,
          userSelect: 'none',
        }}
        onDoubleClick={canExecute ? startRename : undefined}
      >
        {/* Collapse toggle — replaces the old drag grip; chevron folds the column into a strip */}
        <ActionIcon
          size="sm"
          variant="subtle"
          color="gray"
          aria-label="Collapse column"
          onClick={(e) => {
            e.stopPropagation();
            onToggleCollapse(column.id);
          }}
          onMouseDown={(e) => e.stopPropagation()}
          style={{ flexShrink: 0, marginRight: 2 }}
        >
          <IconChevronDown size={15} />
        </ActionIcon>
        {/* Left: name (drag handle) + count + bolt chip */}
        <Group gap={6} style={{ overflow: 'hidden', flex: 1, minWidth: 0 }}>
          {renaming ? (
            <TextInput
              ref={renameInputRef}
              value={renameValue}
              onChange={(e) => setRenameValue(e.currentTarget.value)}
              onBlur={() => {
                // Only commit on blur if still in rename mode (Escape key sets renaming=false)
                if (renaming) commitRename();
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  commitRename();
                  e.preventDefault();
                }
                if (e.key === 'Escape') {
                  setRenaming(false);
                  e.preventDefault();
                }
              }}
              size="xs"
              variant="unstyled"
              onClick={(e) => e.stopPropagation()}
              onMouseDown={(e) => e.stopPropagation()}
              style={{ flex: 1 }}
              styles={{ input: { fontSize: 13, fontWeight: 600, padding: '0 0 0 4px' } }}
            />
          ) : (
            <Text
              {...colListeners}
              fw={600}
              title="Drag to reorder column"
              style={{
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                fontSize: 13,
                color: 'var(--mantine-color-text)',
                cursor: 'grab',
                touchAction: 'none',
              }}
            >
              {column.name}
            </Text>
          )}
          <Text fw={500} c="dimmed" style={{ flexShrink: 0, fontSize: 12 }}>
            {tasks.length}
          </Text>
          {column.workflowBinding && (
            <Tooltip label={column.workflowBinding.workflowName ?? 'Automation'} withArrow>
              <ActionIcon
                size="xs"
                variant="subtle"
                color="orange"
                style={{ flexShrink: 0, cursor: 'default' }}
                onClick={(e) => e.stopPropagation()}
                onMouseDown={(e) => e.stopPropagation()}
              >
                <IconBolt size={12} />
              </ActionIcon>
            </Tooltip>
          )}
        </Group>

        {/* Right: ⋯ menu + add button */}
        <Group gap={2} style={{ flexShrink: 0 }}>
          {canExecute && (
            <Menu shadow="md" width={190} position="bottom-end" withinPortal>
              <Menu.Target>
                <ActionIcon
                  size="sm"
                  variant="subtle"
                  aria-label={`Column actions for ${column.name}`}
                  onClick={(e) => e.stopPropagation()}
                  onMouseDown={(e) => e.stopPropagation()}
                >
                  <IconDots size={14} />
                </ActionIcon>
              </Menu.Target>
              <Menu.Dropdown onClick={(e) => e.stopPropagation()}>
                {/* Automation info block — shown for automated columns */}
                {column.workflowBinding && (
                  <>
                    <Box
                      style={{
                        display: 'flex',
                        alignItems: 'flex-start',
                        gap: 8,
                        padding: '7px 10px 8px',
                        fontSize: 12,
                        color: 'var(--mantine-color-dimmed)',
                        lineHeight: 1.45,
                      }}
                    >
                      <IconBolt size={13} color="var(--app-primary-strong)" style={{ marginTop: 1, flexShrink: 0 }} />
                      <span>
                        Runs{' '}
                        <strong style={{ color: 'var(--mantine-color-text)' }}>
                          {column.workflowBinding.workflowName ?? 'workflow'}
                        </strong>{' '}
                        when a task enters this column.
                      </span>
                    </Box>
                    <Menu.Divider />
                  </>
                )}

                <Menu.Item
                  leftSection={<IconPencil size={13} color="var(--mantine-color-dimmed)" />}
                  onClick={startRename}
                >
                  Rename
                </Menu.Item>
                <Menu.Item
                  leftSection={<IconFold size={13} color="var(--mantine-color-dimmed)" />}
                  onClick={() => onToggleCollapse(column.id)}
                >
                  Collapse
                </Menu.Item>

                <Menu.Divider />

                <Menu.Item
                  leftSection={
                    <IconArrowLeft
                      size={13}
                      color={onMoveLeft ? 'var(--mantine-color-dimmed)' : 'var(--mantine-color-placeholder)'}
                    />
                  }
                  onClick={onMoveLeft}
                  disabled={!onMoveLeft}
                >
                  Move left
                </Menu.Item>
                <Menu.Item
                  leftSection={
                    <IconArrowRight
                      size={13}
                      color={onMoveRight ? 'var(--mantine-color-dimmed)' : 'var(--mantine-color-placeholder)'}
                    />
                  }
                  onClick={onMoveRight}
                  disabled={!onMoveRight}
                >
                  Move right
                </Menu.Item>

                <Menu.Divider />
                <Menu.Item color="red" leftSection={<IconTrash size={13} />} onClick={() => onDeleteColumn?.()}>
                  Delete column
                </Menu.Item>
              </Menu.Dropdown>
            </Menu>
          )}
          {canExecute && (
            <ActionIcon
              size="sm"
              variant="subtle"
              aria-label={`Add task to ${column.name}`}
              onClick={(e) => {
                e.stopPropagation();
                onAddTask(column.id);
              }}
              onMouseDown={(e) => e.stopPropagation()}
            >
              <IconPlus size={16} />
            </ActionIcon>
          )}
        </Group>
      </Box>

      {/* Task list */}
      <SortableContext items={taskIds} strategy={verticalListSortingStrategy}>
        <Box style={{ flex: 1, overflowY: 'auto', padding: '0 12px 12px', minHeight: 60 }}>
          {tasks.length === 0 ? (
            <Text size="xs" c="dimmed" ta="center" py="xl">
              {isFiltered ? 'No matching tasks' : 'No tasks yet'}
            </Text>
          ) : (
            tasks.map((task) => (
              <SortableTaskCard
                key={task.id}
                task={task}
                href={taskHref(task)}
                onClick={onTaskClick}
                onRetry={onRetryTask}
              />
            ))
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
  actorType: string;
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
  totalCostCents?: number;
  totalTokens?: number;
  durationSeconds?: number;
  steps?: Array<{
    name: string;
    state: string;
    startedAt: string | null;
    finishedAt: string | null;
    durationSeconds: number | null;
  }>;
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

// --- Neutral Status Chip (AC-13, AC-28) ---

function NeutralStatusChip({ state, size = 'xs' }: { state: string; size?: string }) {
  const isRunning = WORKFLOW_ACTIVE_STATES.has(state);
  const isSuccess = state === 'completed' || state === 'succeeded';
  const isFailed = state === 'failed';
  let dotColor = 'var(--mantine-color-gray-5)';
  if (isRunning) dotColor = 'var(--app-warning-fg)';
  else if (isSuccess) dotColor = 'var(--app-success-fg)';
  else if (isFailed) dotColor = 'var(--app-danger-fg)';

  return (
    <Badge
      size={size as 'xs' | 'sm'}
      variant="outline"
      color="gray"
      leftSection={
        <Box
          w={6}
          h={6}
          className={isRunning ? styles.workflowDotActive : undefined}
          style={{ borderRadius: '50%', backgroundColor: dotColor, flexShrink: 0 }}
        />
      }
      style={{ fontSize: 10, cursor: 'default' }}
    >
      {state}
    </Badge>
  );
}

// --- Inline tags editor (matches reference .tag / .add-tag / .tag-input pattern) ---

function InlineTagsEditor({
  tags,
  onChange,
  disabled,
}: {
  tags: string[];
  onChange: (tags: string[]) => void;
  disabled?: boolean;
}) {
  const [inputVisible, setInputVisible] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const showInput = () => {
    setInputVisible(true);
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const commitTag = () => {
    const trimmed = inputValue.trim();
    if (trimmed && !tags.includes(trimmed)) {
      onChange([...tags, trimmed]);
    }
    setInputValue('');
    setInputVisible(false);
  };

  const removeTag = (tag: string) => onChange(tags.filter((t) => t !== tag));

  return (
    <Box style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', marginLeft: -9 }}>
      {tags.map((tag) => (
        <Box
          key={tag}
          style={{
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: '0.02em',
            padding: '4px 5px 4px 9px',
            borderRadius: 5,
            border: '1px solid rgba(209,207,205,0.14)',
            background: 'rgba(209,207,205,0.05)',
            color: 'var(--mantine-color-dimmed)',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 2,
            whiteSpace: 'nowrap',
            lineHeight: 1,
          }}
        >
          {tag}
          {!disabled && (
            <Box
              component="button"
              onClick={() => removeTag(tag)}
              style={{
                cursor: 'pointer',
                fontSize: 12,
                opacity: 0.5,
                width: 16,
                height: 16,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                borderRadius: 3,
                background: 'none',
                border: 'none',
                color: 'inherit',
                padding: 0,
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLButtonElement).style.opacity = '1';
                (e.currentTarget as HTMLButtonElement).style.color = 'var(--app-danger-fg)';
                (e.currentTarget as HTMLButtonElement).style.background = 'rgba(200,90,90,0.12)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLButtonElement).style.opacity = '0.5';
                (e.currentTarget as HTMLButtonElement).style.color = 'inherit';
                (e.currentTarget as HTMLButtonElement).style.background = 'none';
              }}
            >
              ×
            </Box>
          )}
        </Box>
      ))}
      {!disabled && !inputVisible && (
        <Box
          component="button"
          onClick={showInput}
          style={{
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: '0.02em',
            padding: '4px 10px',
            borderRadius: 5,
            border: '1px dashed var(--app-border-strong)',
            background: 'transparent',
            color: 'var(--mantine-color-placeholder)',
            cursor: 'pointer',
            lineHeight: 1,
            transition: 'color 0.12s, border-color 0.12s',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--mantine-color-dimmed)';
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--mantine-color-dimmed)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--mantine-color-placeholder)';
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--app-border-strong)';
          }}
        >
          + Add
        </Box>
      )}
      {!disabled && inputVisible && (
        <input
          ref={inputRef}
          value={inputValue}
          onChange={(e) => setInputValue(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commitTag();
            }
            if (e.key === 'Escape') {
              e.preventDefault();
              setInputValue('');
              setInputVisible(false);
            }
          }}
          onBlur={() => {
            // Only commit on blur if still in input mode (Escape key sets inputVisible=false)
            if (inputVisible) commitTag();
          }}
          placeholder="Tag name"
          style={{
            width: 120,
            background: 'var(--app-bg-paper)',
            border: '1px solid var(--app-primary)',
            borderRadius: 5,
            fontFamily: 'inherit',
            fontSize: 12,
            padding: '4px 10px',
            lineHeight: 1,
            color: 'var(--mantine-color-text)',
            outline: 'none',
          }}
        />
      )}
    </Box>
  );
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
  canExecute,
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
  canExecute: boolean;
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
  const [authorFilter, setAuthorFilter] = useState('');
  const [tagFilter, setTagFilter] = useState('');
  const [triggeringWorkflow, setTriggeringWorkflow] = useState(false);
  const [archiving, setArchiving] = useState(false);
  const [deletingGateId, setDeletingGateId] = useState<number | null>(null);
  const [showAllSteps, setShowAllSteps] = useState(false);

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

  const epicTasks = useMemo(
    () => allTasks.filter((t) => t.taskType === 'epic' && t.id !== task?.id),
    [allTasks, task?.id],
  );

  const childTasks = useMemo(() => allTasks.filter((t) => t.parentTaskId === task?.id), [allTasks, task?.id]);

  const parentTask = useMemo(
    () => (task?.parentTaskId ? allTasks.find((t) => t.id === task.parentTaskId) : null) ?? null,
    [allTasks, task?.parentTaskId],
  );

  // The board only loads active tasks, so an archived parent epic is absent from `allTasks`.
  // The serialized parentTaskTitle keeps the link visible (and the select's current value
  // selectable) even when the epic itself was never loaded onto the board.
  const parentTaskTitle = parentTask?.title ?? task?.parentTaskTitle ?? null;

  // Options for the Parent Epic select: every epic on the board, plus the current parent when
  // it is not among them — without it Mantine has no option matching `value` and renders blank.
  const parentEpicOptions = useMemo(() => {
    const options = epicTasks.map((e) => ({ value: String(e.id), label: e.title }));
    if (task?.parentTaskId && !options.some((o) => o.value === String(task.parentTaskId))) {
      options.unshift({ value: String(task.parentTaskId), label: parentTaskTitle ?? `#${task.parentTaskId}` });
    }
    return options;
  }, [epicTasks, task?.parentTaskId, parentTaskTitle]);

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

  const handleToggleArchive = useCallback(async () => {
    if (!task) return;
    setArchiving(true);
    const path = task.archived
      ? unarchiveApiV1ProjectTaskPath(projectId, task.id)
      : archiveApiV1ProjectTaskPath(projectId, task.id);
    try {
      await apiFetch(path, { method: 'PATCH', headers: jsonHeaders });
      router.reload({ only: ['tasks', 'selected_task'] });
    } catch {
      /* ignore */
    }
    setArchiving(false);
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
      size={wide ? '50vw' : 620}
      withCloseButton={false}
      padding={0}
      styles={{
        content: { display: 'flex', flexDirection: 'column', overflow: 'hidden' },
        body: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
      }}
    >
      {/* Panel bar — icon actions only, no title here */}
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 4,
          padding: '12px 16px',
          borderBottom: '1px solid var(--app-border-default)',
          flexShrink: 0,
        }}
      >
        <ActionIcon variant="subtle" size="sm" title={wide ? 'Collapse' : 'Expand'} onClick={() => setWide(!wide)}>
          {wide ? <IconArrowsMinimize size={16} /> : <IconArrowsMaximize size={16} />}
        </ActionIcon>
        <Box style={{ flex: 1 }} />
        {canExecute && canTriggerWorkflow && (
          <Button
            size="compact-sm"
            leftSection={<IconPlayerPlay size={13} />}
            onClick={handleTriggerWorkflow}
            loading={triggeringWorkflow}
            styles={{
              root: {
                background: 'var(--app-primary)',
                color: 'var(--app-on-primary)',
                border: 'none',
                fontWeight: 600,
                fontSize: 13,
                height: 28,
                paddingLeft: 10,
                paddingRight: 10,
              },
            }}
          >
            Run workflow
          </Button>
        )}
        {canExecute && (
          <Tooltip label={task.archived ? 'Unarchive' : 'Archive'}>
            <ActionIcon
              variant="subtle"
              color={task.archived ? 'brand' : 'gray'}
              size="sm"
              onClick={handleToggleArchive}
              loading={archiving}
            >
              {task.archived ? <IconArchiveOff size={16} /> : <IconArchive size={16} />}
            </ActionIcon>
          </Tooltip>
        )}
        {canExecute && (
          <ActionIcon
            variant="subtle"
            size="sm"
            title="Delete"
            onClick={() => setDeleteConfirm(true)}
            style={{ color: 'var(--mantine-color-dimmed)' }}
            className={styles.dangerHover}
          >
            <IconTrash size={16} />
          </ActionIcon>
        )}
        <ActionIcon variant="subtle" size="sm" title="Close" onClick={onClose}>
          <IconX size={16} />
        </ActionIcon>
      </Box>

      <Tabs
        value={tab}
        onChange={setTab}
        style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}
        classNames={{
          tab: styles.detailTab,
          list: styles.detailTabsList,
        }}
      >
        <Tabs.List>
          <Tabs.Tab value="details">Details</Tabs.Tab>
          {columnWorkflowBinding && <Tabs.Tab value="runs">Runs ({(workflowRuns ?? []).length})</Tabs.Tab>}
          <Tabs.Tab value="comments">
            Comments ({(comments ?? []).length > 0 ? (comments ?? []).length : task.commentsCount})
          </Tabs.Tab>
          <Tabs.Tab value="assets">Assets ({assetsCount})</Tabs.Tab>
          <Tabs.Tab value="activity">Activity</Tabs.Tab>
          <Tabs.Tab value="statistics">Analytics</Tabs.Tab>
        </Tabs.List>

        {/* Details — fully editable fields */}
        <Tabs.Panel value="details" style={{ flex: 1, overflow: 'auto', padding: 20 }}>
          {/* Panel header: title, chips, description */}
          <Box style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 18 }}>
            {/* Editable title */}
            {editingTitle ? (
              <textarea
                className={styles.ptTitle}
                value={titleValue}
                rows={1}
                onChange={(e) => {
                  setTitleValue(e.currentTarget.value);
                  e.currentTarget.style.height = 'auto';
                  e.currentTarget.style.height = e.currentTarget.scrollHeight + 'px';
                }}
                onBlur={saveTitle}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    saveTitle();
                  }
                  if (e.key === 'Escape') {
                    setTitleValue(task.title);
                    setEditingTitle(false);
                  }
                }}
                autoFocus
              />
            ) : (
              <div
                className={styles.ptTitle}
                onClick={() => canExecute && setEditingTitle(true)}
                style={{ cursor: canExecute ? 'text' : 'default', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}
              >
                {pendingTitle ?? task.title}
              </div>
            )}

            {/* Status chips: type, priority, workflow */}
            <Box style={{ display: 'flex', flexWrap: 'wrap', gap: 7, alignItems: 'center' }}>
              {task.taskType && task.taskType !== 'not_specified' && (
                <Box
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: '0.05em',
                    textTransform: 'uppercase',
                    padding: '2px 8px',
                    borderRadius: 4,
                    border: '1px solid rgba(209,207,205,0.12)',
                    background: 'rgba(209,207,205,0.05)',
                    color: 'var(--mantine-color-dimmed)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 5,
                  }}
                >
                  {task.taskType.replace('_', ' ')}
                </Box>
              )}
              {task.priority && (
                <Box
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: '0.05em',
                    textTransform: 'uppercase',
                    padding: '2px 8px',
                    borderRadius: 4,
                    border: '1px solid rgba(209,207,205,0.12)',
                    background: 'rgba(209,207,205,0.05)',
                    color: 'var(--mantine-color-dimmed)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 5,
                  }}
                >
                  {task.priority}
                </Box>
              )}
              {columnWorkflowBinding && (
                <Box
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    padding: '2px 8px',
                    borderRadius: 4,
                    border: '1px solid var(--mantine-color-brand-light-hover)',
                    background: 'var(--mantine-color-brand-light)',
                    color: 'var(--app-primary-strong)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 5,
                  }}
                >
                  <IconBolt size={11} />
                  {columnWorkflowBinding.workflowName}
                </Box>
              )}
            </Box>

            {/* Editable description */}
            {editingDesc ? (
              <textarea
                className={styles.ptDesc}
                value={descValue}
                rows={3}
                autoFocus
                onChange={(e) => setDescValue(e.currentTarget.value)}
                onBlur={saveDescription}
                onKeyDown={(e) => {
                  if (e.key === 'Escape') {
                    setDescValue(task.description ?? '');
                    setEditingDesc(false);
                  }
                }}
              />
            ) : (
              <div
                className={styles.ptDesc}
                onClick={() => {
                  if (!canExecute) return;
                  setDescValue(task.description ?? '');
                  setEditingDesc(true);
                }}
                style={{
                  cursor: canExecute ? 'text' : 'default',
                  color:
                    (pendingDesc ?? task.description)
                      ? 'var(--mantine-color-dimmed)'
                      : 'var(--mantine-color-placeholder)',
                }}
              >
                {(pendingDesc ?? task.description) ? (
                  <Box className={styles.commentMd}>
                    <Markdown remarkPlugins={[remarkGfm]}>{pendingDesc ?? task.description ?? ''}</Markdown>
                  </Box>
                ) : (
                  <span style={{ color: 'var(--mantine-color-placeholder)', fontStyle: 'italic' }}>
                    Click to add description…
                  </span>
                )}
              </div>
            )}
          </Box>

          {/* Latest run summary (AC-19) — only for automated columns */}
          {columnWorkflowBinding &&
            (workflowRuns ?? []).length > 0 &&
            (() => {
              const latestRun = (workflowRuns ?? [])[0];
              const dur = latestRun.durationSeconds;
              return (
                <Box style={{ marginBottom: 20 }}>
                  {/* sec-label */}
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
                    <IconBolt size={14} color="var(--app-primary-strong)" />
                    Latest run
                  </Box>
                  {/* run-summary card */}
                  <Box
                    style={{
                      display: 'flex',
                      gap: 16,
                      alignItems: 'center',
                      padding: '12px 14px',
                      border: '1px solid var(--app-border-default)',
                      borderRadius: 8,
                      background: 'var(--app-bg-paper)',
                    }}
                  >
                    <Box style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                      <Text
                        style={{
                          fontSize: 10,
                          letterSpacing: '0.06em',
                          textTransform: 'uppercase',
                          color: 'var(--mantine-color-placeholder)',
                        }}
                      >
                        Status
                      </Text>
                      <NeutralStatusChip state={latestRun.state} />
                    </Box>
                    {dur != null && (
                      <Box style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <Text
                          style={{
                            fontSize: 10,
                            letterSpacing: '0.06em',
                            textTransform: 'uppercase',
                            color: 'var(--mantine-color-placeholder)',
                          }}
                        >
                          Duration
                        </Text>
                        <Text style={{ fontFamily: 'monospace', fontSize: 14, color: 'var(--mantine-color-text)' }}>
                          {formatDuration(dur)}
                        </Text>
                      </Box>
                    )}
                    {latestRun.totalCostCents != null && (
                      <Box style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <Text
                          style={{
                            fontSize: 10,
                            letterSpacing: '0.06em',
                            textTransform: 'uppercase',
                            color: 'var(--mantine-color-placeholder)',
                          }}
                        >
                          Cost
                        </Text>
                        <Text style={{ fontFamily: 'monospace', fontSize: 14, color: 'var(--mantine-color-text)' }}>
                          {formatCostCents(latestRun.totalCostCents)}
                        </Text>
                      </Box>
                    )}
                    <Box
                      component="button"
                      onClick={() => setTab('runs')}
                      style={{
                        marginLeft: 'auto',
                        background: 'none',
                        border: 'none',
                        color: 'var(--app-primary-strong)',
                        fontSize: 12,
                        fontWeight: 600,
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 4,
                        padding: '4px 0',
                      }}
                    >
                      View runs <IconArrowRight size={12} />
                    </Box>
                  </Box>
                </Box>
              );
            })()}

          {/* Properties */}
          <Box style={{ marginBottom: 20 }}>
            {/* sec-label */}
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

            {/* props grid */}
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
                value={String(task.boardColumnId)}
                onChange={(v) => {
                  if (v && v !== String(task.boardColumnId)) moveToColumn(v);
                }}
                aria-label="Column"
                size="xs"
                variant="unstyled"
                styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                disabled={!canExecute}
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
                value={task.taskType}
                onChange={(v) => saveField('taskType', v)}
                size="xs"
                variant="unstyled"
                styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                disabled={!canExecute}
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
                value={task.priority ?? ''}
                onChange={(v) => saveField('priority', v || null)}
                clearable
                size="xs"
                variant="unstyled"
                styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                disabled={!canExecute}
              />

              <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                Assignee
              </Text>
              <Select
                data={members.map((m) => ({ value: String(m.id), label: m.name }))}
                value={task.assigneeId ? String(task.assigneeId) : null}
                onChange={(v) => saveField('assigneeId', v)}
                clearable
                searchable
                size="xs"
                variant="unstyled"
                styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                disabled={!canExecute}
              />

              {/* Parent epic — for non-epic tasks */}
              {task.taskType !== 'epic' && parentEpicOptions.length > 0 && (
                <>
                  <Text size="xs" c="dimmed" style={{ lineHeight: '24px' }}>
                    Parent Epic
                  </Text>
                  <Select
                    data={parentEpicOptions}
                    value={task.parentTaskId ? String(task.parentTaskId) : null}
                    onChange={(v) => saveField('parentTaskId', v)}
                    aria-label="Parent Epic"
                    clearable
                    searchable
                    size="xs"
                    variant="unstyled"
                    styles={{ input: { fontSize: 13, padding: '6px 9px', marginLeft: -9 } }}
                    disabled={!canExecute}
                  />
                </>
              )}

              <Text size="xs" c="dimmed" style={{ alignSelf: 'flex-start', paddingTop: 5 }}>
                Tags
              </Text>
              <InlineTagsEditor
                tags={task.tags ?? []}
                onChange={(tags) => saveField('tags', tags)}
                disabled={!canExecute}
              />

              <Text size="xs" c="dimmed">
                Created
              </Text>
              <Text size="xs" c="dimmed">
                {formatDateTime(task.createdAt)}
              </Text>
            </Box>
          </Box>

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
                          backgroundColor: TASK_TYPE_COLORS[child.taskType] ?? 'var(--app-text-tertiary)',
                          color: 'var(--app-on-primary)',
                          fontSize: 10,
                          fontWeight: 600,
                          flexShrink: 0,
                        }}
                      >
                        {child.taskType.replace('_', ' ')}
                      </Badge>
                      <Text size="xs" c="brand" style={{ flex: 1 }} lineClamp={1}>
                        {child.title}
                      </Text>
                    </UnstyledButton>
                  ))}
                </Stack>
              )}
            </Box>
          )}

          {/* Parent epic link — for non-epic tasks with parent */}
          {task.taskType !== 'epic' && task.parentTaskId && (
            <Box>
              <Text size="xs" c="dimmed" fw={600} tt="uppercase" mb={4}>
                Parent Epic
              </Text>
              {parentTask ? (
                <UnstyledButton onClick={() => onOpenTask(parentTask)}>
                  <Text
                    size="sm"
                    c="brand"
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
              ) : (
                // Archived (or otherwise not-loaded) epic: still name it, but there is no
                // board card to open, so it is plain text rather than a dead link.
                <Text size="sm">{parentTaskTitle ?? `#${task.parentTaskId}`}</Text>
              )}
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
                            c="brand"
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
                            c="brand"
                            style={{ display: 'flex', alignItems: 'center', gap: 4 }}
                          >
                            <IconLink size={10} />
                            {String(wait.metadata.repoFullName)} #{String(wait.metadata.runId)}
                          </Text>
                        )}
                    </Box>
                    {canExecute && (
                      <ActionIcon
                        size="xs"
                        variant="subtle"
                        color="gray"
                        onClick={() => handleDeleteGate(wait.id)}
                        loading={deletingGateId === wait.id}
                      >
                        <IconX size={12} />
                      </ActionIcon>
                    )}
                  </Group>
                ))}
              </Stack>
            </Box>
          )}
        </Tabs.Panel>

        {/* Runs tab — hidden for manual tasks (AC-22) */}
        {columnWorkflowBinding && (
          <Tabs.Panel value="runs" p="md" style={{ flex: 1, overflow: 'auto' }}>
            <Stack gap="md">
              {(workflowRuns ?? []).length === 0 ? (
                <Text size="sm" c="dimmed" ta="center" py="xl">
                  No runs yet.
                </Text>
              ) : (
                <>
                  {/* Totals row */}
                  <Group gap="lg" wrap="wrap">
                    <Box>
                      <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                        Runs
                      </Text>
                      <Text size="sm" fw={600}>
                        {(workflowRuns ?? []).length}
                      </Text>
                    </Box>
                    <Box>
                      <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                        Success rate
                      </Text>
                      <Text size="sm" fw={600}>
                        {Math.round(
                          ((workflowRuns ?? []).filter((r) => r.state === 'completed' || r.state === 'succeeded')
                            .length /
                            (workflowRuns ?? []).length) *
                            100,
                        )}
                        %
                      </Text>
                    </Box>
                    {(workflowRuns ?? []).some((r) => r.totalCostCents != null) && (
                      <Box>
                        <Text size="xs" c="dimmed" tt="uppercase" fw={600} mb={2}>
                          Total cost
                        </Text>
                        <Text size="sm" ff="monospace" fw={600}>
                          {formatCostCents((workflowRuns ?? []).reduce((s, r) => s + (r.totalCostCents ?? 0), 0))}
                        </Text>
                      </Box>
                    )}
                  </Group>

                  {/* Run history */}
                  <Stack gap={4}>
                    {(workflowRuns ?? []).map((run) => (
                      <Box
                        key={run.id}
                        p="xs"
                        style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}
                      >
                        <Group justify="space-between" wrap="nowrap" gap="xs">
                          <NeutralStatusChip state={run.state} />
                          <Text
                            component="a"
                            href={`/company/projects/${projectId}/workflow_runs/${run.id}`}
                            target="_blank"
                            rel="noopener"
                            size="xs"
                            c="brand"
                            style={{
                              display: 'flex',
                              alignItems: 'center',
                              gap: 4,
                              flex: 1,
                              minWidth: 0,
                              textDecoration: 'none',
                            }}
                          >
                            <Box
                              component="span"
                              style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                            >
                              {run.workflowName ?? 'Workflow run'}
                            </Box>
                            <IconExternalLink size={11} style={{ flexShrink: 0 }} />
                          </Text>
                          <Text size="xs" c="dimmed" style={{ flexShrink: 0 }}>
                            {formatDateTime(run.createdAt)}
                          </Text>
                        </Group>

                        {/* Step timeline for first (latest) run */}
                        {run.id === (workflowRuns ?? [])[0]?.id && (run.steps ?? []).length > 0 && (
                          <Box mt="xs">
                            {(run.steps ?? []).map((step, i) => {
                              const isHidden = !showAllSteps && i > 2;
                              return (
                                <Box
                                  key={i}
                                  style={{
                                    display: isHidden ? 'none' : 'flex',
                                    gap: 10,
                                    paddingTop: 8,
                                    paddingBottom: 8,
                                    borderBottom: '1px solid var(--app-border-default)',
                                  }}
                                >
                                  <Box
                                    w={8}
                                    h={8}
                                    mt={4}
                                    style={{
                                      borderRadius: '50%',
                                      flexShrink: 0,
                                      backgroundColor:
                                        step.state === 'done'
                                          ? 'var(--app-success-fg)'
                                          : step.state === 'running'
                                            ? 'var(--app-warning-fg)'
                                            : step.state === 'failed'
                                              ? 'var(--app-danger-fg)'
                                              : 'var(--mantine-color-gray-5)',
                                    }}
                                  />
                                  <Box style={{ flex: 1 }}>
                                    <Text size="sm" c={step.state === 'waiting' ? 'dimmed' : undefined}>
                                      {step.name}
                                    </Text>
                                    <Text size="xs" c="dimmed" ff="monospace">
                                      {step.durationSeconds != null ? formatDuration(step.durationSeconds) : '—'}
                                    </Text>
                                  </Box>
                                </Box>
                              );
                            })}
                            {(run.steps ?? []).length > 3 && (
                              <Button variant="subtle" size="xs" mt={8} onClick={() => setShowAllSteps((s) => !s)}>
                                {showAllSteps ? 'Show fewer steps' : `Show all ${(run.steps ?? []).length} steps`}
                              </Button>
                            )}
                          </Box>
                        )}

                        {/* Retry in Runs tab for failed run (AC-56) */}
                        {run.state === 'failed' && canExecute && (
                          <Box mt="xs">
                            <Button
                              size="compact-xs"
                              variant="outline"
                              color="red"
                              leftSection={<IconRefresh size={11} />}
                              loading={triggeringWorkflow}
                              onClick={handleTriggerWorkflow}
                            >
                              Retry run
                            </Button>
                          </Box>
                        )}
                      </Box>
                    ))}
                  </Stack>
                </>
              )}
            </Stack>
          </Tabs.Panel>
        )}

        {/* Comments — composer on top, filter row below (AC-24) */}
        <Tabs.Panel value="comments" style={{ flex: 1, overflow: 'auto', padding: 20 }}>
          {/* Composer */}
          {canExecute && (
            <Box style={{ paddingBottom: 20, marginBottom: 4, borderBottom: '1px solid var(--app-border-default)' }}>
              <Textarea
                placeholder="Write a comment… (⌘+Enter to send)"
                value={commentBody}
                onChange={(e) => setCommentBody(e.currentTarget.value)}
                autosize
                minRows={3}
                maxRows={6}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && e.metaKey) {
                    e.preventDefault();
                    handleSubmitComment();
                  }
                }}
                styles={{
                  input: {
                    background: 'var(--app-bg-paper)',
                    border: '1px solid var(--app-border-default)',
                    borderRadius: 5,
                    fontSize: 13,
                    lineHeight: 1.6,
                    padding: '8px 11px',
                    color: 'var(--mantine-color-text)',
                    transition: 'border-color .12s',
                  },
                }}
                variant="unstyled"
              />
              {/* Tag toggles */}
              <Box style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
                {COMMENT_TAG_SUGGESTIONS.map((tag) => {
                  const active = commentTags.includes(tag);
                  return (
                    <Box
                      key={tag}
                      component="button"
                      onClick={() =>
                        setCommentTags((prev) => (prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag]))
                      }
                      style={{
                        fontSize: 11,
                        fontWeight: 500,
                        letterSpacing: '0.02em',
                        padding: '4px 10px',
                        borderRadius: 5,
                        border: `1px solid ${active ? 'var(--mantine-color-brand-light-hover)' : 'rgba(209,207,205,0.14)'}`,
                        background: active ? 'var(--mantine-color-brand-light)' : 'rgba(209,207,205,0.05)',
                        color: active ? 'var(--app-primary)' : 'var(--mantine-color-dimmed)',
                        cursor: 'pointer',
                        lineHeight: 1,
                        transition: 'all .12s',
                        fontFamily: 'inherit',
                      }}
                    >
                      {tag
                        .split('_')
                        .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
                        .join('_')}
                    </Box>
                  );
                })}
              </Box>
              {/* Send row */}
              <Box style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 12 }}>
                <Text style={{ fontSize: 11, color: 'var(--mantine-color-placeholder)' }}>⌘ + Enter to send</Text>
                <Button
                  size="compact-sm"
                  rightSection={<IconSend size={13} />}
                  onClick={handleSubmitComment}
                  loading={submittingComment}
                  disabled={!commentBody.trim()}
                  styles={{
                    root: {
                      background: commentBody.trim() ? 'var(--app-primary)' : undefined,
                      color: commentBody.trim() ? 'var(--app-on-primary)' : undefined,
                      border: 'none',
                      fontWeight: 600,
                    },
                  }}
                >
                  Send
                </Button>
              </Box>
            </Box>
          )}

          {/* List header + filters */}
          <Box style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '16px 0 4px' }}>
            <Text
              style={{
                fontSize: 11,
                letterSpacing: '0.06em',
                textTransform: 'uppercase',
                color: 'var(--mantine-color-placeholder)',
                fontWeight: 600,
                whiteSpace: 'nowrap',
              }}
            >
              Comments <span style={{ color: 'var(--mantine-color-dimmed)' }}>({filteredComments.length})</span>
            </Text>
            <Box style={{ display: 'flex', alignItems: 'center', gap: 6, marginLeft: 'auto' }}>
              <Select
                size="xs"
                data={AUTHOR_TYPES}
                value={authorFilter}
                onChange={(v) => setAuthorFilter(v ?? '')}
                clearable
                w={90}
                aria-label="Author type filter"
                styles={{ input: { fontSize: 12 } }}
              />
              <Select
                size="xs"
                data={[
                  { value: 'newest', label: 'Newest' },
                  { value: 'oldest', label: 'Oldest' },
                ]}
                defaultValue="newest"
                w={90}
                styles={{ input: { fontSize: 12 } }}
              />
              {/* Tag filter */}
              <Box
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 5,
                  background: 'var(--app-bg-paper)',
                  border: '1px solid var(--app-border-default)',
                  borderRadius: 5,
                  padding: '0 9px',
                  height: 30,
                  transition: 'border-color .12s',
                }}
              >
                <IconTag size={12} color="var(--mantine-color-placeholder)" />
                <input
                  placeholder="Filter by tag"
                  value={tagFilter}
                  onChange={(e) => setTagFilter(e.currentTarget.value)}
                  style={{
                    background: 'transparent',
                    border: 'none',
                    outline: 'none',
                    color: 'var(--mantine-color-text)',
                    fontFamily: 'inherit',
                    fontSize: 12,
                    width: 96,
                  }}
                />
              </Box>
            </Box>
          </Box>

          {/* Comment list */}
          {filteredComments.length === 0 ? (
            <Text size="sm" c="dimmed" ta="center" py="xl">
              No comments yet.
            </Text>
          ) : (
            filteredComments.map((c) => {
              const isAgent = c.authorType === 'agent';
              const initials = (c.authorName ?? 'U')
                .split(' ')
                .map((w: string) => w[0])
                .join('')
                .slice(0, 2)
                .toUpperCase();
              return (
                <Box key={c.id} style={{ padding: '16px 0', borderBottom: '1px solid rgba(41,39,38,0.6)' }}>
                  {/* Comment header */}
                  <Box style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    {/* Avatar */}
                    <Box
                      style={{
                        width: 26,
                        height: 26,
                        borderRadius: '50%',
                        flexShrink: 0,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontSize: 10,
                        fontWeight: 700,
                        background: isAgent ? 'var(--mantine-color-brand-light)' : 'var(--mantine-color-brand-light)',
                        border: '1px solid var(--mantine-color-brand-light-hover)',
                        color: 'var(--app-primary-strong)',
                      }}
                    >
                      {initials}
                    </Box>
                    <Text style={{ fontSize: 13, fontWeight: 600, color: 'var(--mantine-color-text)' }}>
                      {c.authorName ?? 'System'}
                    </Text>
                    {c.authorType && (
                      <Box
                        style={{
                          fontSize: 10,
                          fontWeight: 600,
                          letterSpacing: '0.05em',
                          padding: '1px 7px',
                          borderRadius: 4,
                          background: isAgent ? 'var(--mantine-color-brand-light)' : 'rgba(209,207,205,0.05)',
                          border: `1px solid ${isAgent ? 'var(--mantine-color-brand-light-hover)' : 'rgba(209,207,205,0.14)'}`,
                          color: isAgent ? 'var(--app-primary)' : 'var(--mantine-color-dimmed)',
                          textTransform: 'uppercase',
                        }}
                      >
                        {c.authorType}
                      </Box>
                    )}
                    <Text style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--mantine-color-placeholder)' }}>
                      {formatDateTime(c.createdAt)}
                    </Text>
                  </Box>

                  {/* Comment body */}
                  <Box
                    className={styles.commentMd}
                    style={{ fontSize: 13, color: 'var(--mantine-color-dimmed)', lineHeight: 1.6, marginTop: 8 }}
                  >
                    <Markdown remarkPlugins={[remarkGfm]}>{c.body}</Markdown>
                  </Box>

                  {/* Tags */}
                  {c.tags && c.tags.length > 0 && (
                    <Box style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 6 }}>
                      {c.tags.map((t) => (
                        <Box
                          key={t}
                          style={{
                            fontSize: 10,
                            fontWeight: 600,
                            letterSpacing: '0.04em',
                            textTransform: 'uppercase',
                            padding: '2px 7px',
                            borderRadius: 4,
                            border: '1px solid rgba(209,207,205,0.14)',
                            background: 'rgba(209,207,205,0.05)',
                            color: 'var(--mantine-color-dimmed)',
                          }}
                        >
                          {t}
                        </Box>
                      ))}
                    </Box>
                  )}

                  {/* Actions */}
                  <Box style={{ display: 'flex', gap: 2, marginTop: 8 }}>
                    <Box
                      component="button"
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 5,
                        background: 'none',
                        border: 'none',
                        color: 'var(--mantine-color-placeholder)',
                        fontFamily: 'inherit',
                        fontSize: 12,
                        padding: '4px 8px',
                        borderRadius: 5,
                        cursor: 'pointer',
                        transition: 'color .12s, background .12s',
                      }}
                      className={styles.cmtAct}
                    >
                      <IconMessage size={13} />
                      Reply
                    </Box>
                    <Box
                      component="button"
                      onClick={() =>
                        navigator.clipboard?.writeText(`${window.location.href}#comment-${c.id}`).catch(() => undefined)
                      }
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 5,
                        background: 'none',
                        border: 'none',
                        color: 'var(--mantine-color-placeholder)',
                        fontFamily: 'inherit',
                        fontSize: 12,
                        padding: '4px 8px',
                        borderRadius: 5,
                        cursor: 'pointer',
                        transition: 'color .12s, background .12s',
                      }}
                      className={styles.cmtAct}
                    >
                      <IconLink size={13} />
                      Copy link
                    </Box>
                  </Box>
                </Box>
              );
            })
          )}
        </Tabs.Panel>

        {/* Assets — with upload and delete */}
        <Tabs.Panel value="assets" style={{ flex: 1, overflow: 'auto', padding: 20 }}>
          {/* Assets header: sec-label + upload button */}
          <Box
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: 14,
            }}
          >
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
              }}
            >
              <IconCloudUpload size={14} color="var(--app-primary-strong)" />
              Assets
            </Box>
            {canExecute && (
              <>
                <input ref={fileInputRef} type="file" hidden onChange={handleUploadAsset} />
                <Button
                  size="compact-sm"
                  leftSection={<IconCloudUpload size={13} />}
                  onClick={() => fileInputRef.current?.click()}
                  styles={{
                    root: {
                      background: 'transparent',
                      border: '1px solid var(--app-primary)',
                      color: 'var(--app-primary-strong)',
                      fontWeight: 600,
                      fontSize: 13,
                    },
                  }}
                >
                  Upload new
                </Button>
              </>
            )}
          </Box>

          {/* Asset list */}
          {(taskAssets ?? []).length === 0 ? (
            <Text size="sm" c="dimmed" ta="center" py="xl">
              No assets attached.
            </Text>
          ) : (
            <Stack gap={8}>
              {(taskAssets ?? []).map((a) => {
                const ext = a.name.split('.').pop()?.toLowerCase() ?? '';
                const isPdf = ext === 'pdf';
                const isImg = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].includes(ext);
                const sizeStr = a.fileSize
                  ? a.fileSize < 1024
                    ? `${a.fileSize} B`
                    : a.fileSize < 1024 * 1024
                      ? `${(a.fileSize / 1024).toFixed(1)} KB`
                      : `${(a.fileSize / (1024 * 1024)).toFixed(1)} MB`
                  : null;
                const subText = [a.contentType, sizeStr].filter(Boolean).join(' · ');
                return (
                  <Box
                    key={a.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 10,
                      padding: '10px 12px',
                      border: '1px solid var(--app-border-default)',
                      borderRadius: 8,
                      background: 'var(--app-bg-paper)',
                    }}
                  >
                    {/* File type icon */}
                    <Box style={{ flexShrink: 0, color: 'var(--mantine-color-placeholder)' }}>
                      {isPdf ? (
                        <IconFileTypePdf size={18} />
                      ) : isImg ? (
                        <IconLayoutGrid size={18} />
                      ) : (
                        <IconCloudUpload size={18} />
                      )}
                    </Box>

                    {/* Name + sub */}
                    <Box style={{ flex: 1, minWidth: 0 }}>
                      <Text style={{ fontSize: 13, color: 'var(--mantine-color-text)', fontWeight: 500 }} lineClamp={1}>
                        {a.name}
                      </Text>
                      {subText && (
                        <Text style={{ fontSize: 11, color: 'var(--mantine-color-placeholder)' }}>{subText}</Text>
                      )}
                    </Box>

                    {/* Actions */}
                    <Box style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                      {a.fileUrl && (
                        <ActionIcon component="a" href={a.fileUrl} target="_blank" variant="subtle" size="sm">
                          <IconDownload size={15} />
                        </ActionIcon>
                      )}
                      {canExecute && (
                        <ActionIcon
                          variant="subtle"
                          size="sm"
                          onClick={() => handleDeleteAsset(a.id)}
                          className={styles.dangerHover}
                          style={{ color: 'var(--mantine-color-placeholder)' }}
                        >
                          <IconTrash size={15} />
                        </ActionIcon>
                      )}
                    </Box>
                  </Box>
                );
              })}
            </Stack>
          )}
        </Tabs.Panel>

        {/* Activity */}
        <Tabs.Panel value="activity" style={{ flex: 1, overflow: 'auto', padding: 20 }}>
          {(activities ?? []).length === 0 ? (
            <Text size="sm" c="dimmed" ta="center" py="xl">
              No activity yet.
            </Text>
          ) : (
            (activities ?? []).map((a) => (
              <Box
                key={a.id}
                style={{
                  display: 'flex',
                  gap: 10,
                  padding: '12px 0',
                  borderBottom: '1px solid rgba(41,39,38,0.6)',
                }}
              >
                <ActivityAvatar actorType={a.actorType} actorName={a.actorName} />
                <Box style={{ flex: 1, minWidth: 0 }}>
                  <Text style={{ fontSize: 13, lineHeight: 1.5, color: 'var(--mantine-color-text)' }}>
                    <strong>{a.actorName}</strong>{' '}
                    {a.description.startsWith(a.actorName)
                      ? a.description.slice(a.actorName.length).trim()
                      : a.description}
                  </Text>
                  <Text style={{ fontSize: 11, color: 'var(--mantine-color-placeholder)', marginTop: 2 }}>
                    {formatRelativeTime(a.createdAt)}
                  </Text>
                </Box>
              </Box>
            ))
          )}
        </Tabs.Panel>

        {/* Analytics */}
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
                              <Cell key={i} fill="var(--app-primary)" />
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
                                borderBottom: '1px solid var(--app-border-default)',
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
                                borderBottom: '1px solid var(--app-border-default)',
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
                                borderBottom: '1px solid var(--app-border-default)',
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
                                borderBottom: '1px solid var(--app-border-default)',
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
                                  borderBottom: '1px solid var(--app-bg-elevated)',
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
                                  borderBottom: '1px solid var(--app-bg-elevated)',
                                }}
                              >
                                {formatCostCents(b.costCents)}
                              </td>
                              <td
                                style={{
                                  textAlign: 'right',
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--app-bg-elevated)',
                                }}
                              >
                                {formatTokens(b.totalTokens)}
                              </td>
                              <td
                                style={{
                                  textAlign: 'right',
                                  fontSize: 12,
                                  padding: '6px 8px',
                                  borderBottom: '1px solid var(--app-bg-elevated)',
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
                              ? { borderBottom: '1px solid var(--app-bg-elevated)' }
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

// --- Activity Feed (slide-over, non-modal — AC-27) ---

function formatRelativeTime(value: string): string {
  const date = new Date(value);
  if (isNaN(date.getTime())) return value;
  const diff = (Date.now() - date.getTime()) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  const days = Math.floor(diff / 86400);
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;
  return date.toLocaleDateString();
}

function ActivityAvatar({ actorType, actorName }: { actorType: string; actorName: string }) {
  const isAgent = actorType === 'agent';
  return (
    <Box
      style={{
        width: 28,
        height: 28,
        borderRadius: '50%',
        flexShrink: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 11,
        fontWeight: 600,
        background: isAgent ? 'var(--mantine-color-brand-light)' : 'rgba(209,207,205,0.07)',
        border: `1px solid ${isAgent ? 'var(--mantine-color-brand-light-hover)' : 'var(--app-border-default)'}`,
        color: isAgent ? 'var(--app-primary)' : 'var(--mantine-color-dimmed)',
      }}
    >
      {isAgent ? (
        <IconRobot size={13} />
      ) : (
        actorName
          .split(' ')
          .map((w) => w[0])
          .join('')
          .slice(0, 2)
          .toUpperCase()
      )}
    </Box>
  );
}

function ActivityFeedPanel({
  projectId,
  initialActivities,
  opened,
  onClose,
}: {
  projectId: number;
  initialActivities: ActivityItem[];
  opened: boolean;
  onClose: () => void;
}) {
  const { activities, loading, loadMore, hasMore } = useBoardActivitiesLoadMore(projectId, initialActivities);

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={340}
      withOverlay={false}
      lockScroll={false}
      withCloseButton
      title={
        <Text fw={600} size="sm">
          Activity
        </Text>
      }
      styles={{
        header: { borderBottom: '1px solid var(--app-border-default)', padding: '12px 16px' },
        body: { padding: '0 16px' },
      }}
    >
      {loading && activities.length === 0 ? (
        <Box ta="center" py="xl">
          <Loader size="sm" />
        </Box>
      ) : activities.length === 0 ? (
        <Text size="xs" c="dimmed" ta="center" py="xl">
          No activity yet.
        </Text>
      ) : (
        <>
          {activities.map((a) => (
            <Box
              key={a.id}
              style={{
                display: 'flex',
                gap: 10,
                padding: '12px 0',
                borderBottom: '1px solid rgba(41,39,38,0.6)',
              }}
            >
              <ActivityAvatar actorType={a.actorType} actorName={a.actorName} />
              <Box style={{ flex: 1, minWidth: 0 }}>
                <Text size="xs" style={{ lineHeight: 1.5, color: 'var(--mantine-color-text)' }}>
                  <strong>{a.actorName}</strong>{' '}
                  {a.description
                    .replace(a.actorName, '')
                    .trim()
                    .replace(/^moved '(.+?)' from/, "moved '$1' from")}
                </Text>
                <Text size="10px" c="dimmed" mt={2}>
                  {formatRelativeTime(a.createdAt)}
                </Text>
              </Box>
            </Box>
          ))}
          {hasMore && (
            <Button variant="subtle" size="xs" fullWidth mt="xs" onClick={loadMore} loading={loading}>
              Load more
            </Button>
          )}
        </>
      )}
    </Drawer>
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
        <ThemeIcon size={64} radius="xl" variant="light" color="brand">
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
              <ThemeIcon size={48} radius="md" variant="light" color="brand">
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
            showArchived: false,
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
            showArchived: false,
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
      showArchived: false,
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
          <Button
            variant="default"
            size="xs"
            leftSection={<IconAdjustmentsHorizontal size={13} />}
            rightSection={<IconChevronDown size={11} />}
            styles={{ root: { fontWeight: 400 } }}
          >
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
    archived: t.archived ?? false,
    pendingGates: t.pendingGates ?? [],
    recentWorkflowRuns: t.recentWorkflowRuns ?? [],
    assetsCount: t.assetsCount ?? 0,
    childrenCount: t.childrenCount ?? 0,
    commentsCount: t.commentsCount ?? 0,
  };
}

// Merge two task lists, deduping by id. Tasks in `primary` win over `extra`
// (used to fold on-demand-loaded archived tasks into the active board without
// duplicating any task that already appears in the active set).
function mergeTasksById(primary: Task[], extra: Task[]): Task[] {
  const ids = new Set(primary.map((t) => t.id));
  return [...primary, ...extra.filter((t) => !ids.has(t.id))];
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
  const { canExecute } = useProjectPermissions();

  const [filters, setFilters] = useState<BoardFilters>(EMPTY_FILTERS);
  const showArchived = filters.showArchived;

  // Archived tasks are fetched on demand — only when "Show archived" is enabled — so the
  // initial board load stays limited to active tasks (the core load optimization). Refetched
  // whenever the active task set changes so archive/unarchive stays reflected in this view.
  const [archivedTasks, setArchivedTasks] = useState<Task[]>([]);

  const [localTasks, setLocalTasks] = useState<Task[]>(() => (serverTasks ?? []).map(normalizeTask));
  useEffect(() => {
    const base = (serverTasks ?? []).map(normalizeTask);
    setLocalTasks(showArchived ? mergeTasksById(base, archivedTasks) : base);
  }, [serverTasks, archivedTasks, showArchived]);

  const [localColumns, setLocalColumns] = useState<Column[]>(() => columns ?? []);
  useEffect(() => {
    setLocalColumns(columns ?? []);
  }, [columns]);

  useEffect(() => {
    if (!showArchived || !board) {
      if (!showArchived) setArchivedTasks([]);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await apiFetch(`${apiV1ProjectTasksPath(project.id)}?archived=archived`);
        if (res.ok && !cancelled) {
          const data = await res.json();
          setArchivedTasks((Array.isArray(data) ? data : []).map(normalizeTask));
        }
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [showArchived, board, project.id, serverTasks]);

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
  const [activityOpen, setActivityOpen] = useState(false);
  const [activeTask, setActiveTask] = useState<Task | null>(null);
  const [hoverColumnId, setHoverColumnId] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
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

  // URL each task card links to. Kept in sync with openTask so a plain click and
  // "open in new tab" land on the same task detail view.
  const taskHref = useCallback((task: Task) => `${boardUrl}?task=${task.id}`, [boardUrl]);

  const closeTask = useCallback(() => {
    router.get(boardUrl, {}, { preserveState: true, preserveScroll: true });
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

  const allTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const t of localTasks) for (const tag of t.tags ?? []) tagSet.add(tag);
    return [...tagSet].sort();
  }, [localTasks]);

  const filteredTasks = useMemo(() => {
    return localTasks.filter((t) => {
      if (!filters.showArchived && t.archived) return false;
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
      parentTaskId: null,
      boardColumnId: '',
    },
  });

  // Epics available as a parent in the create drawer. Nesting is one level deep, so an epic
  // itself never gets a parent — the field is hidden when Type is Epic (see below).
  const epicOptions = useMemo(
    () => localTasks.filter((t) => t.taskType === 'epic').map((t) => ({ value: String(t.id), label: t.title })),
    [localTasks],
  );

  const handleCreateTask = useCallback(
    async (values: TaskFormValues) => {
      if (!board) return;
      setLoading(true);
      try {
        const isEpic = (values.taskType || 'not_specified') === 'epic';
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
              parentTaskId: !isEpic && values.parentTaskId ? Number(values.parentTaskId) : null,
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
  const dragTypeRef = useRef<'task' | 'column' | null>(null);

  const handleDragStart = useCallback(
    (event: DragStartEvent) => {
      const data = event.active.data.current;
      if (data?.type === 'column') {
        dragTypeRef.current = 'column';
        setActiveTask(null);
      } else {
        dragTypeRef.current = 'task';
        const taskData = data?.task as Task | undefined;
        setActiveTask(taskData ?? null);
        draggedIdRef.current = taskData?.id ?? null;
        preDragSnapshotRef.current = localTasks.map((t) => ({ ...t }));
      }
      setHoverColumnId(null);
    },
    [], // no dependencies needed; only reads refs and sets state
  );

  const handleDragOver = useCallback((event: DragOverEvent) => {
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
      const { active, over } = event;

      // ── Column reorder ──────────────────────────────────────────────────────
      if (dragTypeRef.current === 'column') {
        dragTypeRef.current = null;
        if (!over || active.id === over.id) return;

        const oldIdx = localColumns.findIndex((c) => `col-${c.id}` === active.id);
        const newIdx = localColumns.findIndex((c) => `col-${c.id}` === over.id);
        if (oldIdx === -1 || newIdx === -1) return;

        const newOrder = arrayMove(localColumns, oldIdx, newIdx);
        setLocalColumns(newOrder);

        // persist to server with error recovery
        apiFetch(reorderApiV1ProjectColumnsPath(project.id), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ columnIds: newOrder.map((c) => c.id) }),
        })
          .then(() => router.reload({ only: ['columns'] }))
          .catch(() => {
            setLocalColumns(localColumns); // revert on error
            // Error toast would be shown by global error handler
          });
        return;
      }

      // ── Task move ──────────────────────────────────────────────────────────
      dragTypeRef.current = null;
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
    [board, project.id, localColumns],
  );

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
      try {
        await apiFetch(triggerWorkflowApiV1ProjectTaskPath(project.id, task.id), {
          method: 'POST',
          headers: jsonHeaders,
        });
        router.reload({ only: ['tasks', 'selected_task', 'task_workflow_runs'] });
      } catch (error) {
        console.error('Failed to retry task:', error);
        // Error toast would be shown by global error handler
      }
    },
    [project.id, jsonHeaders],
  );

  const handleRenameColumn = useCallback(
    async (columnId: number, name: string) => {
      await apiFetch(apiV1ProjectColumnPath(project.id, columnId), {
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
          await apiFetch(apiV1ProjectColumnPath(project.id, columnId), { method: 'DELETE' });
          router.reload({ only: ['columns', 'tasks'] });
        },
      });
    },
    [project.id],
  );

  const handleAddColumnInline = useCallback(async () => {
    const res = await apiFetch(apiV1ProjectColumnsPath(project.id), {
      method: 'POST',
      headers: jsonHeaders,
      body: JSON.stringify({ boardColumn: { name: 'New column' } }),
    });
    if (res.ok) {
      router.reload({ only: ['columns'] });
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
        closeTask();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [closeTask, canExecute]);

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
            <Menu shadow="md" width={200} position="bottom-start" closeOnItemClick={false}>
              <Menu.Target>
                <Button
                  variant="default"
                  size="xs"
                  leftSection={<IconTag size={12} />}
                  styles={{
                    root: {
                      fontWeight: 400,
                      color: filters.tags.length > 0 ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
                    },
                  }}
                >
                  Tags:{' '}
                  {filters.tags.length === 0
                    ? 'All'
                    : filters.tags.length === 1
                      ? filters.tags[0]
                      : `${filters.tags.length} selected`}
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                {allTags.map((tag) => (
                  <Menu.Item
                    key={tag}
                    onClick={() =>
                      setFilters((f) => ({
                        ...f,
                        tags: f.tags.includes(tag) ? f.tags.filter((t) => t !== tag) : [...f.tags, tag],
                      }))
                    }
                    rightSection={filters.tags.includes(tag) ? <IconCheck size={12} /> : null}
                    fw={filters.tags.includes(tag) ? 600 : 400}
                  >
                    {tag}
                  </Menu.Item>
                ))}
                {filters.tags.length > 0 && (
                  <>
                    <Menu.Divider />
                    <Menu.Item color="gray" onClick={() => setFilters((f) => ({ ...f, tags: [] }))}>
                      Clear tags
                    </Menu.Item>
                  </>
                )}
              </Menu.Dropdown>
            </Menu>
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
                  taskHref={taskHref}
                  onAddTask={openCreateForColumn}
                  onTaskClick={openTask}
                  onRetryTask={handleRetryTask}
                  collapsed={collapsedColumns.has(col.id)}
                  onToggleCollapse={handleToggleCollapse}
                  onMoveLeft={
                    idx > 0
                      ? () => {
                          const ids = localColumns.map((c) => c.id);
                          const next = [...ids];
                          [next[idx - 1], next[idx]] = [next[idx], next[idx - 1]];
                          apiFetch(reorderApiV1ProjectColumnsPath(project.id), {
                            method: 'PATCH',
                            headers: jsonHeaders,
                            body: JSON.stringify({ columnIds: next }),
                          }).then(() => router.reload({ only: ['columns'] }));
                        }
                      : undefined
                  }
                  onMoveRight={
                    idx < localColumns.length - 1
                      ? () => {
                          const ids = localColumns.map((c) => c.id);
                          const next = [...ids];
                          [next[idx], next[idx + 1]] = [next[idx + 1], next[idx]];
                          apiFetch(reorderApiV1ProjectColumnsPath(project.id), {
                            method: 'PATCH',
                            headers: jsonHeaders,
                            body: JSON.stringify({ columnIds: next }),
                          }).then(() => router.reload({ only: ['columns'] }));
                        }
                      : undefined
                  }
                  onDeleteColumn={() => handleDeleteColumn(col.id)}
                  onRenameColumn={handleRenameColumn}
                  isFiltered={hasActiveFilters}
                  isDropTarget={hoverColumnId === col.id}
                  canExecute={canExecute}
                />
              ))}
            </SortableContext>

            {/* Add column button — strip when all columns are collapsed, pill otherwise */}
            {(() => {
              const allCollapsed = allColumnsCollapsed;
              return allCollapsed ? (
                <Box
                  onClick={handleAddColumnInline}
                  className={styles.addColumnBtn}
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
              );
            })()}
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
