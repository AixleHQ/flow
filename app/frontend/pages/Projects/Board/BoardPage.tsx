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
} from '@dnd-kit/core';
import {
  SortableContext,
  verticalListSortingStrategy,
  horizontalListSortingStrategy,
  sortableKeyboardCoordinates,
  useSortable,
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
  Combobox,
  Drawer,
  Group,
  Loader,
  Menu,
  Modal,
  Paper,
  ScrollArea,
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
  useCombobox,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
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
import { formatElapsedTime } from 'shared/lib/formatElapsedTime';
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

import { formatCostCents, formatDuration, formatTokens } from './boardFormat';
import styles from './BoardPage.module.css';
import { CHIP_TOOLTIP_PROPS } from './chipTooltip';
import { GATE_CHIP_WIDTH, GateStatusChip } from './GateStatusChip';
import { LatestRunTile } from './LatestRunTile';
import { SelectionBar } from './SelectionBar';
import { WORKFLOW_ACTIVE_STATES, type TaskWorkflowRun } from './taskRuns';
import { TaskRunsPanel } from './TaskRunsPanel';
import { useBoardDnd } from './useBoardDnd';
import { useBoardTaskPages } from './useBoardTaskPages';
import { useBulkActions } from './useBulkActions';

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
  // Every active task in the column, not just the loaded page — the column header count.
  // Optional so a partial reload serialized before this field existed still types.
  tasksCount?: number;
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
  // `status` is the gate's lifecycle (pending / resolved / stale); `ciStatus` collapses it with the
  // provider's verdict into the four states a board reader cares about: pending, succeeded, failed,
  // stale. A stale gate is one reconciliation gave up on — see `diagnosticReason` for why.
  status?: string;
  ciStatus?: string;
  conclusion?: string | null;
  ageSeconds?: number;
  expiresAt?: string | null;
  expired?: boolean;
  diagnosticReason?: string | null;
  source?: { provider?: string; repoFullName?: string; referenceType?: string; reference?: unknown };
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
  // Also detail-payload-only: an epic's children, which a board holding one page per column can
  // no longer be filtered for.
  childTasks?: Array<{ id: number; title: string; taskType: string }>;
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
  // Every CI gate the task has had, newest first — pending, passed, failed and stale alike, which is
  // what lets a card say which of those four things CI is currently doing. Optional so a payload
  // serialized before this field existed (or a partial reload) still types.
  ciGates?: Gate[];
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
  // First page of each column only; the rest arrives through useBoardTaskPages.
  tasks: Task[];
  tasksPageSize?: number;
  // Board-wide filter/picker options, which can no longer be derived from `tasks`.
  boardTags?: string[];
  epics?: Array<{ id: number; title: string }>;
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

// Gate states that still hold the column auto-trigger or still need a person — the only ones worth
// offering a delete button for.
const GATE_UNRESOLVED_STATUSES = new Set(['pending', 'stale']);

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
  onTagClick,
  activeTags,
  isSelected,
  onToggleSelect,
  selectionMode,
}: {
  task: Task;
  href?: string;
  onClick?: (t: Task) => void;
  onRetry?: (task: Task) => void;
  onTagClick?: (tag: string) => void;
  activeTags?: string[];
  isSelected?: boolean;
  onToggleSelect?: (id: number, checked: boolean) => void;
  selectionMode?: boolean;
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
      <TaskCardUI
        task={task}
        href={href}
        onClick={onClick}
        onRetry={onRetry}
        onTagClick={onTagClick}
        activeTags={activeTags}
        isSelected={isSelected}
        onToggleSelect={onToggleSelect}
        selectionMode={selectionMode}
      />
    </Box>
  );
}

// What a gate's CI state is, tolerating a payload that predates ciStatus: a gate the server did not
// classify is pending unless it says otherwise.
function gateCiStatus(gate: Gate): string {
  return gate.ciStatus ?? gate.status ?? 'pending';
}

// The CI verdict a card advertises, from the newest CI gate the task has: which of the four states
// (waiting / passed / failed / stale) it is in, and the one-line reason a reader needs. Stale is its
// own state on purpose — it means "no CI verdict was ever obtained", which is neither a pass nor a
// failure, and it is the state a lost webhook now lands in instead of waiting forever.
function ciGateSummary(task: Task): { label: string; color: string; tooltip: string } | null {
  const gate = (task.ciGates ?? [])[0];
  if (!gate) return null;

  const kind = gateCiStatus(gate);
  const name = gate.gateType.replace(/_/g, ' ');

  switch (kind) {
    case 'stale':
      return {
        label: 'CI stale',
        color: 'orange',
        tooltip: gate.diagnosticReason
          ? `${name} — stale: ${gate.diagnosticReason}`
          : `${name} — no CI result was ever obtained`,
      };
    case 'failed':
      return {
        label: 'CI failed',
        color: 'red',
        tooltip: `${name} — ${gate.conclusion ?? 'failed'}`,
      };
    case 'succeeded':
      return { label: 'CI passed', color: 'green', tooltip: `${name} — ${gate.conclusion ?? 'success'}` };
    default:
      return {
        label: 'CI pending',
        color: 'yellow',
        tooltip: `${name} — waiting ${formatElapsedTime(gate.createdAt)}${gate.expired ? ' (past its TTL)' : ''}`,
      };
  }
}

// The part of a gate's story its chip does NOT already tell, as a short muted suffix. The state
// itself is the chip's label, so repeating it here would only be noise; age is not — "waiting"
// reads very differently at two minutes and at eleven hours — and neither is a failure that ended
// in something other than a plain failed check (timed out, cancelled, action required).
function gateDetail(gate: Gate): string | null {
  const kind = gateCiStatus(gate);
  if (kind === 'succeeded') return null;
  if (kind === 'failed') {
    const conclusion = gate.conclusion;
    if (!conclusion || conclusion === 'failure' || conclusion === 'failed') return null;
    return conclusion.replace(/_/g, ' ');
  }

  const elapsed = formatElapsedTime(gate.createdAt);
  if (kind === 'stale') return elapsed;
  return gate.expired ? `${elapsed} · past TTL` : elapsed;
}

// What the chip's tooltip spells out: the gate type the row no longer prints as a pill, plus the
// provider's own conclusion when there is one worth naming — and, for a stale gate, why
// reconciliation gave up. That last one is a sentence of prose, not a label: it rides in the
// tooltip so a stale row stays as compact as every other one, worded the same way the card's CI
// summary chip words it.
function gateTooltip(gate: Gate): string {
  const name = gate.gateType.replace(/_/g, ' ');
  if (gateCiStatus(gate) === 'stale') {
    return gate.diagnosticReason
      ? `${name} — stale: ${gate.diagnosticReason}`
      : `${name} — stale: no CI result was ever obtained`;
  }
  return gate.conclusion ? `${name} — ${gate.conclusion}` : name;
}

// The provider page a gate row links to: the pull request for a checks gate, the run page for a
// workflow gate. Null when the metadata a link needs was never recorded.
function gateLink(gate: Gate): { href: string; label: string; kind: 'pr' | 'run' } | null {
  const repo = gate.metadata.repoFullName;
  if (!repo) return null;

  if (gate.gateType === 'github_checks_completed' && gate.metadata.prNumber) {
    return {
      href: `https://github.com/${repo}/pull/${gate.metadata.prNumber}`,
      label: `${repo} #${gate.metadata.prNumber}`,
      kind: 'pr',
    };
  }
  if (gate.gateType === 'github_workflow_completed' && gate.metadata.runId) {
    return {
      href: `https://github.com/${repo}/actions/runs/${gate.metadata.runId}`,
      label: `${repo} #${gate.metadata.runId}`,
      kind: 'run',
    };
  }
  return null;
}

// Status a collapsed ticket chip advertises: the bar colour and the hover tooltip both come
// from here, so the folded strip still tells you which tickets are running, failed or waiting
// without unfolding the column.
function collapsedTaskStatus(task: Task): { color: string; hasActiveRun: boolean; tooltipLabel: string } {
  const latestRun = task.recentWorkflowRuns?.[0];
  const hasPendingGates = (task.pendingGates?.length ?? 0) > 0;
  const staleGate = (task.ciGates ?? []).find((g) => gateCiStatus(g) === 'stale');

  let color = 'var(--app-text-tertiary)';
  let hasActiveRun = false;
  if (latestRun) {
    color = workflowStatusColor(latestRun.state);
    hasActiveRun = WORKFLOW_ACTIVE_STATES.has(latestRun.state);
  }
  // A pending gate outranks the run state: the ticket is parked, so it must not read as active.
  if (hasPendingGates) {
    color = 'var(--app-warning-fg)';
    hasActiveRun = false;
  }
  // A stale gate outranks a pending one: nobody is going to resolve it, so it needs a human.
  if (staleGate) {
    color = 'var(--app-danger-fg)';
    hasActiveRun = false;
  }

  const tooltipParts: string[] = [task.title];
  if (latestRun) {
    if (latestRun.state === 'running' && latestRun.createdAt) {
      tooltipParts.push(`Running — ${formatElapsedTime(latestRun.createdAt)}`);
    } else {
      tooltipParts.push(`Status: ${latestRun.state}`);
    }
  }
  if (hasPendingGates) {
    const oldestGate = task.pendingGates.reduce((a, b) => (a.createdAt < b.createdAt ? a : b));
    tooltipParts.push(`Waiting — ${formatElapsedTime(oldestGate.createdAt)}`);
  }
  if (staleGate) {
    tooltipParts.push(`CI stale — ${staleGate.diagnosticReason ?? 'no CI result'}`);
  }

  return { color, hasActiveRun, tooltipLabel: tooltipParts.join(' · ') };
}

// A compact, draggable stand-in for a task shown inside a collapsed column strip.
// It keeps the ticket present in the DOM as a sortable item so a drag can still be
// initiated from a collapsed source column (board requirement 3). It renders no task
// title text — only a small status bar — so a collapsed column stays lightweight and does
// not reveal card content while folded; the title and run status live in the tooltip.
// Clicking a chip opens the task detail sidebar, the same as clicking a full card in an
// expanded column. The pointer sensor only starts a drag past an 8px threshold, so a plain
// click still reaches onClick and dragging the chip out of the column is unaffected.
function CollapsedTaskChip({ task, onClick }: { task: Task; onClick?: (t: Task) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: `task-${task.id}`,
    data: { type: 'task', task },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  const { color, hasActiveRun, tooltipLabel } = collapsedTaskStatus(task);

  return (
    <Tooltip {...CHIP_TOOLTIP_PROPS} label={tooltipLabel}>
      <Box
        ref={setNodeRef}
        aria-label={`Drag ${task.title}`}
        onClick={() => onClick?.(task)}
        style={{
          ...style,
          width: 30,
          height: 12,
          borderRadius: 3,
          backgroundColor: color,
          cursor: 'grab',
          touchAction: 'none',
          flexShrink: 0,
          animation: hasActiveRun ? 'priorityBarPulse 2s ease-in-out infinite' : undefined,
        }}
        {...attributes}
        {...listeners}
      />
    </Tooltip>
  );
}

function TaskCardUI({
  task,
  href,
  onClick,
  isDragOverlay,
  onRetry,
  onTagClick,
  activeTags,
  isSelected,
  onToggleSelect,
  selectionMode,
}: {
  task: Task;
  href?: string;
  onClick?: (t: Task) => void;
  isDragOverlay?: boolean;
  onRetry?: (task: Task) => void;
  onTagClick?: (tag: string) => void;
  activeTags?: string[];
  isSelected?: boolean;
  onToggleSelect?: (id: number, checked: boolean) => void;
  selectionMode?: boolean;
}) {
  const [cardHovered, setCardHovered] = useState(false);

  // A card shows at most three tags. Whichever ones the board is filtered by come first, so the
  // filter that put this card on screen is always the one you can click to take it back off.
  const cardTags = (activeTags ?? []).length
    ? [...(task.tags ?? [])].sort(
        (a, b) => Number((activeTags ?? []).includes(b)) - Number((activeTags ?? []).includes(a)),
      )
    : (task.tags ?? []);
  const visibleTags = cardTags.slice(0, 3);
  const overflowCount = cardTags.length - 3;

  const ciSummary = ciGateSummary(task);
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
        setCardHovered(true);
      }}
      onMouseLeave={(e: React.MouseEvent<HTMLElement>) => {
        (e.currentTarget as HTMLElement).style.borderColor = 'var(--app-border-strong)';
        (e.currentTarget as HTMLElement).style.backgroundColor = 'var(--app-bg-elevated)';
        setCardHovered(false);
      }}
    >
      {/* Title row with selection checkbox, priority dot */}
      <Group gap={8} align="flex-start" wrap="nowrap">
        {onToggleSelect && (
          <Box
            className={[
              styles.selectionCheckboxWrapper,
              isSelected || selectionMode || cardHovered ? styles.selectionCheckboxVisible : '',
            ].join(' ')}
            onPointerDown={(e: React.PointerEvent) => e.stopPropagation()}
            onClick={(e: React.MouseEvent) => {
              e.stopPropagation();
            }}
          >
            <Checkbox
              size="xs"
              checked={!!isSelected}
              onChange={(e) => onToggleSelect(task.id, e.currentTarget.checked)}
              aria-label={`Select ${task.title}`}
            />
          </Box>
        )}
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

      {/* Workflow status chip — filled colored badge (AC-11). The chip names only the latest run,
          so the tooltip keeps listing every recent run's state as it did before the board redesign. */}
      {latestRun && dotColor && runLabel && (
        <Tooltip label={(task.recentWorkflowRuns ?? []).map((r) => r.state).join(', ')}>
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
        </Tooltip>
      )}

      {/* CI chip — the card's own answer to "what is CI doing?", kept separate from the workflow
          chip above because a green run and a red CI are entirely compatible states. */}
      {ciSummary && (
        <Tooltip label={ciSummary.tooltip} multiline maw={320}>
          <Group gap={4} mt={6} align="center">
            <Badge
              size="xs"
              variant="filled"
              color={ciSummary.color}
              leftSection={
                ciSummary.label === 'CI stale' ? (
                  <IconAlertCircle size={9} />
                ) : ciSummary.label === 'CI passed' ? (
                  <IconCircleCheck size={9} />
                ) : ciSummary.label === 'CI failed' ? (
                  <IconX size={9} />
                ) : (
                  <IconHourglass size={9} />
                )
              }
              style={{ fontSize: 10, cursor: 'default', textTransform: 'uppercase', letterSpacing: 0.3 }}
            >
              {ciSummary.label}
            </Badge>
          </Group>
        </Tooltip>
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
        {visibleTags.map((tag) => {
          const isFiltered = (activeTags ?? []).includes(tag);
          if (!onTagClick) {
            return (
              <Badge key={tag} size="xs" variant="outline" color="gray" style={{ fontSize: 10 }}>
                {tag}
              </Badge>
            );
          }
          return (
            // A tag on a card is the shortest path to "show me the other tasks like this one", so it
            // toggles the board's tag filter. The card itself is a link and a drag handle, hence both
            // the click (open task) and the pointerdown (start drag) stop here.
            <Badge
              key={tag}
              component="button"
              type="button"
              size="xs"
              variant={isFiltered ? 'filled' : 'outline'}
              color="gray"
              aria-pressed={isFiltered}
              title={isFiltered ? `Remove tag filter ${tag}` : `Filter board by tag ${tag}`}
              onPointerDown={(e: React.PointerEvent) => e.stopPropagation()}
              onClick={(e: React.MouseEvent) => {
                e.preventDefault();
                e.stopPropagation();
                onTagClick(tag);
              }}
              style={{ fontSize: 10, cursor: 'pointer' }}
            >
              {tag}
            </Badge>
          );
        })}
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
  totalCount,
  hasMore,
  loadingMore,
  onLoadMore,
  taskHref,
  onAddTask,
  onTaskClick,
  onRetryTask,
  onTagClick,
  activeTags,
  collapsed,
  onToggleCollapse,
  onMoveLeft,
  onMoveRight,
  onDeleteColumn,
  onRenameColumn,
  isFiltered,
  isDropTarget,
  canExecute,
  selectedIds,
  onToggleSelect,
  selectionMode,
}: {
  column: Column;
  /** The pages of this column the client has loaded — not necessarily all of it. */
  tasks: Task[];
  /** Every task in the column, which is what the header count means. */
  totalCount: number;
  hasMore: boolean;
  loadingMore: boolean;
  onLoadMore: (columnId: number) => void;
  taskHref: (task: Task) => string;
  onAddTask: (columnId: number) => void;
  onTaskClick: (task: Task) => void;
  onRetryTask: (task: Task) => void;
  onTagClick: (tag: string) => void;
  activeTags: string[];
  collapsed: boolean;
  onToggleCollapse: (id: number) => void;
  onMoveLeft?: () => void;
  onMoveRight?: () => void;
  onDeleteColumn?: () => void;
  onRenameColumn?: (columnId: number, name: string) => void;
  isFiltered: boolean;
  isDropTarget: boolean;
  canExecute: boolean;
  selectedIds?: Set<number>;
  onToggleSelect?: (id: number, checked: boolean) => void;
  selectionMode?: boolean;
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

  // Infinite scroll: the next page is pulled as the column nears its end. The Load more button
  // below stays as the explicit (and keyboard-reachable) way to do the same thing.
  const handleScroll = (event: React.UIEvent<HTMLDivElement>) => {
    if (!hasMore || loadingMore) return;
    const { scrollTop, scrollHeight, clientHeight } = event.currentTarget;
    if (scrollHeight - scrollTop - clientHeight <= LOAD_MORE_SCROLL_THRESHOLD_PX) onLoadMore(column.id);
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
          {totalCount}
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
            collapsed source column (board requirement 3). No title text is rendered here.
            A chip click opens the task detail sidebar; stopPropagation keeps it from also
            hitting the column's expand toggle. */}
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
                <CollapsedTaskChip key={task.id} task={task} onClick={onTaskClick} />
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
            // A column that declares a purpose explains it on hover, as it did before the board
            // redesign. Without a purpose the name keeps the plain drag-affordance title.
            <Tooltip label={column.purpose} multiline w={200} disabled={!column.purpose}>
              <Text
                {...colListeners}
                fw={600}
                title={column.purpose ? undefined : 'Drag to reorder column'}
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
            </Tooltip>
          )}
          <Text fw={500} c="dimmed" style={{ flexShrink: 0, fontSize: 12 }}>
            {totalCount}
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

      {/* Task list — one page at a time, extended as it is scrolled */}
      <SortableContext items={taskIds} strategy={verticalListSortingStrategy}>
        <Box onScroll={handleScroll} style={{ flex: 1, overflowY: 'auto', padding: '0 12px 12px', minHeight: 60 }}>
          {tasks.length === 0 && !loadingMore ? (
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
                onTagClick={onTagClick}
                activeTags={activeTags}
                isSelected={selectedIds?.has(task.id)}
                onToggleSelect={onToggleSelect}
                selectionMode={selectionMode}
              />
            ))
          )}
          {hasMore && (
            <Button
              variant="subtle"
              size="xs"
              fullWidth
              mt={4}
              loading={loadingMore}
              onClick={() => onLoadMore(column.id)}
            >
              {`Load more (${tasks.length} of ${totalCount})`}
            </Button>
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

// --- Inline tags editor (matches reference .tag / .add-tag / .tag-input pattern) ---

function InlineTagsEditor({
  tags,
  onChange,
  disabled,
  suggestions,
}: {
  tags: string[];
  onChange: (tags: string[]) => void;
  disabled?: boolean;
  suggestions?: string[];
}) {
  const [inputVisible, setInputVisible] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const combobox = useCombobox({ onDropdownClose: () => combobox.resetSelectedOption() });

  // Tags the board already uses, minus the ones on this task — picking from these is what keeps
  // "frontend" from silently becoming "front-end" on the next task.
  const options = useMemo(() => {
    const query = inputValue.trim().toLowerCase();
    return (suggestions ?? []).filter((s) => !tags.includes(s) && (query === '' || s.toLowerCase().includes(query)));
  }, [suggestions, tags, inputValue]);

  const showInput = () => {
    setInputVisible(true);
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const addTag = (tag: string) => {
    if (tag && !tags.includes(tag)) onChange([...tags, tag]);
    setInputValue('');
    setInputVisible(false);
    combobox.closeDropdown();
  };

  const commitTag = () => addTag(inputValue.trim());

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
        <Combobox store={combobox} position="bottom-start" shadow="md" withinPortal onOptionSubmit={addTag}>
          <Combobox.Target>
            <input
              ref={inputRef}
              value={inputValue}
              aria-label="Tag name"
              onFocus={() => combobox.openDropdown()}
              onChange={(e) => {
                setInputValue(e.currentTarget.value);
                combobox.openDropdown();
                combobox.resetSelectedOption();
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  // An arrow-key-highlighted suggestion wins over the raw text: Mantine's own
                  // handler runs right after this one and submits the option.
                  if (combobox.getSelectedOptionIndex() !== -1) return;
                  e.preventDefault();
                  commitTag();
                }
                if (e.key === 'Escape') {
                  // First Escape dismisses the suggestions, a second one leaves the input.
                  if (combobox.dropdownOpened) return;
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
          </Combobox.Target>
          <Combobox.Dropdown hidden={options.length === 0}>
            <Combobox.Options>
              <ScrollArea.Autosize mah={180} type="scroll">
                {options.map((tag) => (
                  <Combobox.Option value={tag} key={tag}>
                    <Text size="xs">{tag}</Text>
                  </Combobox.Option>
                ))}
              </ScrollArea.Autosize>
            </Combobox.Options>
          </Combobox.Dropdown>
        </Combobox>
      )}
    </Box>
  );
}

// --- Task Detail Sidebar ---

function TaskDetailSidebar({
  task,
  allTasks,
  epics,
  knownTags,
  onClose,
  onDelete,
  onOpenTaskId,
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
  /** The pages the board holds — a fallback source, not the whole board. */
  allTasks: Task[];
  /** Every epic on the board, for the Parent Epic picker. */
  epics: Array<{ id: number; title: string }>;
  /** Every tag on the board, offered as autocomplete when tagging this task. */
  knownTags: string[];
  onClose: () => void;
  onDelete: (taskId: number) => void;
  /** Opens a task by id — the board may hold no card for it (an unloaded child or parent). */
  onOpenTaskId: (taskId: number) => void;
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

  // Board-wide epics, from their own prop: the loaded pages hold only some of them.
  const epicTasks = useMemo(() => epics.filter((e) => e.id !== task?.id), [epics, task?.id]);

  // Children come with the task payload. The board-derived list is the fallback for a render that
  // has not received the detail payload yet (a card opened straight from a partial reload).
  const childTasks = useMemo(() => {
    if (task?.childTasks) {
      return task.childTasks.map((c) => ({ id: c.id, title: c.title, taskType: c.taskType }));
    }
    return allTasks
      .filter((t) => t.parentTaskId === task?.id)
      .map((t) => ({ id: t.id, title: t.title, taskType: t.taskType }));
  }, [task?.childTasks, allTasks, task?.id]);

  // The drawer lists the task's whole CI history, not only what is still blocking it: a failed or a
  // stale gate is the most interesting thing on a card, and both have already left `pendingGates`.
  // The fallback keeps the panel working for a payload serialized before `ciGates` existed.
  const gatesForPanel = useMemo<Gate[]>(() => {
    const history = task?.ciGates ?? [];
    return history.length > 0 ? history : (task?.pendingGates ?? []);
  }, [task?.ciGates, task?.pendingGates]);

  const hasStaleGate = useMemo(() => gatesForPanel.some((gate) => gateCiStatus(gate) === 'stale'), [gatesForPanel]);

  const parentTask = useMemo(
    () => (task?.parentTaskId ? allTasks.find((t) => t.id === task.parentTaskId) : null) ?? null,
    [allTasks, task?.parentTaskId],
  );

  // The board only loads active tasks, so an archived parent epic is absent from `allTasks`.
  // The serialized parentTaskTitle keeps the link visible (and the select's current value
  // selectable) even when the epic itself was never loaded onto the board.
  // The epic may be on a page this board has not loaded; it is still openable by id, and the
  // epics prop names it. Only a task missing from both (an archived epic) has no card to open.
  const parentEpic = useMemo(
    () => (task?.parentTaskId ? epics.find((e) => e.id === task.parentTaskId) : undefined) ?? null,
    [epics, task?.parentTaskId],
  );
  const parentLinkId = parentTask?.id ?? parentEpic?.id ?? null;

  const parentTaskTitle = parentTask?.title ?? parentEpic?.title ?? task?.parentTaskTitle ?? null;

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
  // A task keeps its run history wherever it is parked — a workflow that finishes usually moves the
  // task out of the bound column, and gating the run surfaces on the binding hid the history (and
  // the session shortcut) exactly then. The runs themselves decide; the binding only decides whether
  // a *new* run can be started from here (canTriggerWorkflow).
  const hasRuns = (workflowRuns ?? []).length > 0;
  const showRuns = !!columnWorkflowBinding || hasRuns;
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
          {showRuns && <Tabs.Tab value="runs">Runs ({(workflowRuns ?? []).length})</Tabs.Tab>}
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

          {/* Latest run summary (AC-19) — whenever the task has runs, bound column or not */}
          {hasRuns && (
            <LatestRunTile run={(workflowRuns ?? [])[0]} projectId={projectId} onViewRuns={() => setTab('runs')} />
          )}

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
                suggestions={knownTags}
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
                      onClick={() => onOpenTaskId(child.id)}
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
              {parentLinkId ? (
                <UnstyledButton onClick={() => onOpenTaskId(parentLinkId)}>
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
                    {parentTaskTitle}
                  </Text>
                </UnstyledButton>
              ) : (
                // Archived (or otherwise not-loaded) epic: still name it, but there is no
                // board card to open, so it is plain text rather than a dead link.
                <Text size="sm">{parentTaskTitle ?? `#${task.parentTaskId}`}</Text>
              )}
            </Box>
          )}

          {/* CI gates — pending, passed, failed and stale. A stale gate is the case this panel exists
              for: its webhook never arrived, reconciliation could not get a verdict either, and it is
              now waiting on a person rather than on CI. */}
          {gatesForPanel.length > 0 && (
            <Box>
              <Group gap={6} mb={4}>
                <ThemeIcon size={18} variant="light" color={hasStaleGate ? 'orange' : 'yellow'} radius="xl">
                  {hasStaleGate ? <IconAlertCircle size={12} /> : <IconHourglass size={12} />}
                </ThemeIcon>
                <Text size="xs" c="dimmed" fw={600} tt="uppercase">
                  CI Gates ({gatesForPanel.length})
                </Text>
              </Group>
              <Stack gap={4}>
                {gatesForPanel.map((wait) => {
                  const kind = gateCiStatus(wait);
                  const link = gateLink(wait);
                  const detail = gateDetail(wait);

                  return (
                    // One line per gate, stale ones included: why reconciliation gave up is prose,
                    // so it lives in the chip's tooltip rather than as a second line under the row.
                    <Group key={wait.id} gap={8} align="center" wrap="nowrap">
                      {/* A floor, not a fixed width: every state word fits inside it so the links
                          still align, but a chip that ever outgrew it would widen the column
                          rather than have its label clipped by the badge's ellipsis. */}
                      <Box miw={GATE_CHIP_WIDTH} style={{ flexShrink: 0 }}>
                        <GateStatusChip status={kind} tooltip={gateTooltip(wait)} />
                      </Box>
                      {link ? (
                        <Text
                          component="a"
                          href={link.href}
                          target="_blank"
                          rel="noopener noreferrer"
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
                          <IconLink size={10} style={{ flexShrink: 0 }} />
                          <Box
                            component="span"
                            style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                          >
                            {link.label}
                          </Box>
                        </Text>
                      ) : (
                        // A gate whose metadata carries no linkable reference still has to say what
                        // it is waiting on, and the chip only carries the state.
                        <Text size="xs" c="dimmed" style={{ flex: 1, minWidth: 0 }} lineClamp={1}>
                          {wait.gateType.replace(/_/g, ' ')}
                        </Text>
                      )}
                      {/* Age, TTL and an unusual conclusion — what the chip cannot say on its own:
                          "waiting" reads very differently at two minutes and at eleven hours. */}
                      {detail && (
                        <Text size="xs" c="dimmed" style={{ fontSize: 11, flexShrink: 0 }}>
                          {detail}
                        </Text>
                      )}
                      {canExecute && GATE_UNRESOLVED_STATUSES.has(kind) && (
                        <ActionIcon
                          size="xs"
                          variant="subtle"
                          color="gray"
                          aria-label={`Delete gate ${wait.id}`}
                          onClick={() => handleDeleteGate(wait.id)}
                          loading={deletingGateId === wait.id}
                        >
                          <IconX size={12} />
                        </ActionIcon>
                      )}
                    </Group>
                  );
                })}
              </Stack>
            </Box>
          )}
        </Tabs.Panel>

        {/* Runs tab — hidden only for manual tasks that never ran (AC-22) */}
        {showRuns && (
          <TaskRunsPanel
            runs={workflowRuns ?? []}
            projectId={projectId}
            canRetry={canExecute && !!columnWorkflowBinding}
            retrying={triggeringWorkflow}
            onRetry={handleTriggerWorkflow}
          />
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
                      {stats.gateStats.filter((w) => w.status === 'resolved').length} resolved &middot;{' '}
                      {stats.gateStats.filter((w) => w.status === 'stale').length} stale
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
                          ) : w.status === 'stale' ? (
                            <IconAlertCircle
                              size={14}
                              color="var(--mantine-color-orange-6)"
                              style={{ flexShrink: 0 }}
                            />
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
                            color={w.status === 'resolved' ? 'green' : w.status === 'stale' ? 'orange' : 'yellow'}
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

// --- Tag filter ---

// A board accumulates tags without bound, so the filter is a searchable combobox rather than a
// plain menu: type to narrow, arrows + Enter to pick, and the option list scrolls instead of
// growing past the viewport — every tag stays reachable no matter how many there are.
function TagFilterCombobox({
  allTags,
  selected,
  onToggle,
  onClear,
}: {
  allTags: string[];
  selected: string[];
  onToggle: (tag: string) => void;
  onClear: () => void;
}) {
  const [search, setSearch] = useState('');
  const combobox = useCombobox({
    onDropdownClose: () => {
      combobox.resetSelectedOption();
      setSearch('');
    },
    // Focus the search box on open so typing filters immediately, without a second click.
    onDropdownOpen: () => combobox.focusSearchInput(),
  });

  const matches = useMemo(() => {
    const query = search.trim().toLowerCase();
    return query ? allTags.filter((tag) => tag.toLowerCase().includes(query)) : allTags;
  }, [allTags, search]);

  const label = selected.length === 0 ? 'All' : selected.length === 1 ? selected[0] : `${selected.length} selected`;

  return (
    <Combobox
      store={combobox}
      width={240}
      position="bottom-start"
      shadow="md"
      withinPortal
      // Tags filter as a set, so submitting an option toggles it and leaves the dropdown open —
      // several tags can be picked in one pass.
      onOptionSubmit={(tag) => onToggle(tag)}
    >
      <Combobox.Target targetType="button">
        <Button
          variant="default"
          size="xs"
          leftSection={<IconTag size={12} />}
          onClick={() => combobox.toggleDropdown()}
          styles={{
            root: {
              fontWeight: 400,
              color: selected.length > 0 ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
            },
          }}
        >
          Tags: {label}
        </Button>
      </Combobox.Target>

      <Combobox.Dropdown>
        <Combobox.Search
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          placeholder="Search tags"
          aria-label="Search tags"
        />
        <Combobox.Options>
          <ScrollArea.Autosize mah={240} type="scroll">
            {matches.length === 0 ? (
              <Combobox.Empty>No tags found</Combobox.Empty>
            ) : (
              matches.map((tag) => {
                const isSelected = selected.includes(tag);
                return (
                  <Combobox.Option value={tag} key={tag} active={isSelected}>
                    <Group gap={6} wrap="nowrap">
                      <IconCheck size={12} style={{ flexShrink: 0, visibility: isSelected ? 'visible' : 'hidden' }} />
                      <Text size="xs" fw={isSelected ? 600 : 400} style={{ wordBreak: 'break-word' }}>
                        {tag}
                      </Text>
                    </Group>
                  </Combobox.Option>
                );
              })
            )}
          </ScrollArea.Autosize>
        </Combobox.Options>
        {selected.length > 0 && (
          <Combobox.Footer>
            <Button variant="subtle" color="gray" size="compact-xs" onClick={onClear}>
              Clear tags
            </Button>
          </Combobox.Footer>
        )}
      </Combobox.Dropdown>
    </Combobox>
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

// How close to the bottom of a column the scroll has to get before its next page is fetched.
const LOAD_MORE_SCROLL_THRESHOLD_PX = 200;

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
  } = usePage<{ props: Props }>().props as unknown as Props;
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

  const toggleSelect = useCallback((id: number, checked: boolean) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (checked) next.add(id);
      else next.delete(id);
      return next;
    });
  }, []);

  const clearSelection = useCallback(() => setSelectedIds(new Set()), []);

  const { execute: executeBulkAction } = useBulkActions({ projectId: project.id, onSuccess: clearSelection });

  // Opening by id, for a task the board may not hold a card for — an epic's child or parent that
  // lives on a page no column has loaded.
  const openTaskById = useCallback(
    (taskId: number) => {
      router.get(boardUrl, { task: taskId }, { preserveState: true, preserveScroll: true });
    },
    [boardUrl],
  );

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
    [board, project.id, form, setLocalTasks],
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
                  selectedIds={selectedIds}
                  onToggleSelect={canExecute ? toggleSelect : undefined}
                  selectionMode={canExecute && selectedIds.size > 0}
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

      <SelectionBar
        selectedCount={selectedIds.size}
        columns={localColumns}
        canExecute={canExecute}
        onAction={(action, columnId) => executeBulkAction(action, [...selectedIds], columnId)}
        onClear={clearSelection}
      />

      <TaskDetailSidebar
        task={selectedTask}
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
