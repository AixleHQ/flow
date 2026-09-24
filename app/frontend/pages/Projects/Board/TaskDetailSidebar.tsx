import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  CopyButton,
  Drawer,
  Group,
  Modal,
  Paper,
  Select,
  SimpleGrid,
  Skeleton,
  Stack,
  Tabs,
  Text,
  Textarea,
  ThemeIcon,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import {
  IconAlertCircle,
  IconArchive,
  IconArchiveOff,
  IconArrowsMaximize,
  IconArrowsMinimize,
  IconBolt,
  IconChartBar,
  IconCircleCheck,
  IconClock,
  IconCloudUpload,
  IconCoin,
  IconDownload,
  IconFileTypePdf,
  IconHourglass,
  IconLayoutGrid,
  IconLink,
  IconListDetails,
  IconMessage,
  IconPlayerPlay,
  IconSend,
  IconTag,
  IconTrash,
  IconWorld,
  IconWorldOff,
  IconX,
} from '@tabler/icons-react';
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

import type BoardActivity from 'types/generated/BoardActivity';
import type BoardMember from 'types/generated/BoardMember';
import type TaskAsset from 'types/generated/TaskAsset';
import type TaskComment from 'types/generated/TaskComment';
import type TaskStatistics from 'types/generated/TaskStatistics';
import type TaskWorkflowRun from 'types/generated/TaskWorkflowRun';

import { apiMutate } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';
import {
  apiV1ProjectTaskPath,
  apiV1ProjectTaskCommentsPath,
  apiV1ProjectTaskAssetsPath,
  apiV1ProjectTaskAssetPath,
  shareApiV1ProjectTaskAssetPath,
  apiV1ProjectTaskGatePath,
  moveApiV1ProjectTaskPath,
  archiveApiV1ProjectTaskPath,
  unarchiveApiV1ProjectTaskPath,
  triggerWorkflowApiV1ProjectTaskPath,
} from 'shared/routes';
import { CHART_SERIES } from 'shared/theme/chartPalette';

import { ActivityAvatar } from './ActivityAvatar';
import { formatCostCents, formatDuration, formatRelativeTime, formatTokens } from './boardFormat';
import styles from './BoardPage.module.css';
import { gateCiStatus, gateDetail, gateLink, gateTooltip } from './gates';
import { GATE_CHIP_WIDTH, GateStatusChip } from './GateStatusChip';
import { InlineTagsEditor } from './InlineTagsEditor';
import { LatestRunTile } from './LatestRunTile';
import { TaskDetailSkeleton } from './TaskDetailSkeleton';
import { WORKFLOW_ACTIVE_STATES } from './taskRuns';
import { TaskRunsPanel } from './TaskRunsPanel';
import { jsonHeaders, TASK_TYPE_COLORS, type Column, type Gate, type Task } from './types';

const COMMENT_TAG_SUGGESTIONS = ['feedback', 'tech_design', 'code_review', 'qa_report', 'implementation_notes'];
const AUTHOR_TYPES = [
  { value: '', label: 'All' },
  { value: 'human', label: 'Human' },
  { value: 'agent', label: 'Agent' },
  { value: 'system', label: 'System' },
];

// Gate states that still hold the column auto-trigger or still need a person — the only ones worth
// offering a delete button for.
const GATE_UNRESOLVED_STATUSES = new Set(['pending', 'stale']);

const CHART_COLORS = CHART_SERIES;
const CHART_TOOLTIP_STYLE: React.CSSProperties = {
  backgroundColor: 'var(--app-bg-default)',
  border: '1px solid rgba(255,255,255,0.12)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--app-text-primary)',
};

async function addTaskComment(projectId: number, taskId: number, body: string, tags: string[] = []) {
  const saved = await apiMutate(apiV1ProjectTaskCommentsPath(projectId, taskId), {
    method: 'POST',
    headers: jsonHeaders,
    body: JSON.stringify({ taskComment: { body, tags } }),
  });
  if (saved) router.reload({ only: ['task_comments', 'task_activities'] });
  return saved;
}

async function uploadTaskAsset(projectId: number, taskId: number, file: File) {
  const formData = new FormData();
  formData.append('task_asset[name]', file.name);
  formData.append('task_asset[file]', file);
  const saved = await apiMutate(apiV1ProjectTaskAssetsPath(projectId, taskId), {
    method: 'POST',
    body: formData,
  });
  if (saved) router.reload({ only: ['task_assets', 'task_activities'] });
}

async function deleteTaskAsset(projectId: number, taskId: number, assetId: number) {
  const deleted = await apiMutate(apiV1ProjectTaskAssetPath(projectId, taskId, assetId), {
    method: 'DELETE',
  });
  if (deleted) router.reload({ only: ['task_assets', 'task_activities'] });
}

async function unshareTaskAsset(projectId: number, taskId: number, assetId: number) {
  const unshared = await apiMutate(shareApiV1ProjectTaskAssetPath(projectId, taskId, assetId), {
    method: 'DELETE',
  });
  if (unshared) router.reload({ only: ['task_assets'] });
}

function deleteTaskGate(projectId: number, taskId: number, gateId: number): Promise<boolean> {
  return apiMutate(apiV1ProjectTaskGatePath(projectId, taskId, gateId), { method: 'DELETE' });
}

export function TaskDetailSidebar({
  task,
  pendingTaskId,
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
  /** A task id whose props are still in flight — draws the skeleton until it resolves. */
  pendingTaskId: number | null;
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
  members: BoardMember[];
  comments: TaskComment[];
  activities: BoardActivity[];
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
    const ok = await apiMutate(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { title: saved } }),
    });
    // On success the cable refreshes selectedTask, and the effect above clears pendingTitle.
    if (!ok) setPendingTitle(null);
  };

  const saveDescription = async () => {
    setEditingDesc(false);
    if (!task || descValue === (task.description ?? '')) return;
    const saved = descValue;
    setPendingDesc(saved);
    const ok = await apiMutate(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { description: saved } }),
    });
    if (!ok) setPendingDesc(null);
  };

  const saveField = async (field: string, value: string | string[] | null) => {
    if (!task) return;
    await apiMutate(apiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ boardTask: { [field]: value } }),
    });
    router.reload({ only: ['selected_task'] });
  };

  const moveToColumn = async (columnId: string) => {
    if (!task) return;
    await apiMutate(moveApiV1ProjectTaskPath(projectId, task.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      body: JSON.stringify({ columnId: Number(columnId) }),
    });
    router.reload({ only: ['tasks', 'selected_task'] });
  };

  const handleSubmitComment = async () => {
    if (!commentBody.trim() || !task) return;
    setSubmittingComment(true);
    if (await addTaskComment(projectId, task.id, commentBody.trim(), commentTags)) {
      setCommentBody('');
      setCommentTags([]);
    }
    setSubmittingComment(false);
  };

  const handleTriggerWorkflow = useCallback(async () => {
    if (!task) return;
    setTriggeringWorkflow(true);
    const triggered = await apiMutate(triggerWorkflowApiV1ProjectTaskPath(projectId, task.id), {
      method: 'POST',
      headers: jsonHeaders,
    });
    if (triggered) router.reload({ only: ['selected_task', 'task_workflow_runs', 'task_activities'] });
    setTriggeringWorkflow(false);
  }, [projectId, task]);

  const handleToggleArchive = useCallback(async () => {
    if (!task) return;
    setArchiving(true);
    const path = task.archived
      ? unarchiveApiV1ProjectTaskPath(projectId, task.id)
      : archiveApiV1ProjectTaskPath(projectId, task.id);
    if (await apiMutate(path, { method: 'PATCH', headers: jsonHeaders })) {
      router.reload({ only: ['tasks', 'selected_task'] });
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

  const handleUnshareAsset = useCallback(
    async (assetId: number) => {
      if (!task) return;
      await unshareTaskAsset(projectId, task.id, assetId);
    },
    [projectId, task],
  );

  // Nothing open and nothing requested — stay unmounted, same as before.
  if (!task && pendingTaskId === null) return null;

  // A click landed and the request for it hasn't resolved yet (opening fresh, or switching from
  // whatever task — if any — was already showing). Keep the drawer's own chrome (size, padding,
  // header/tabs shape) so the real content that replaces this doesn't shift anything when it
  // lands, and skip straight to skeleton content instead of a stale or empty panel.
  if (!task || (pendingTaskId !== null && pendingTaskId !== task.id)) {
    return (
      <Drawer
        opened
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
        <TaskDetailSkeleton onClose={onClose} />
      </Drawer>
    );
  }

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
              // The `#id` is a sibling of the editable title div, never a child of it: putting it
              // inside would make it part of the text saveTitle reads and persists.
              <Box style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <div
                  className={styles.ptTitle}
                  onClick={() => canExecute && setEditingTitle(true)}
                  style={{ cursor: canExecute ? 'text' : 'default', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}
                >
                  {pendingTitle ?? task.title}
                </div>
                <CopyButton value={String(task.id)}>
                  {({ copied, copy }) => (
                    <Tooltip label={copied ? 'Copied' : 'Copy ID'} withArrow>
                      <Text
                        c="dimmed"
                        style={{ flexShrink: 0, whiteSpace: 'nowrap', cursor: 'pointer' }}
                        onClick={copy}
                      >
                        #{task.id}
                      </Text>
                    </Tooltip>
                  )}
                </CopyButton>
              </Box>
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
                    <Markdown
                      remarkPlugins={[remarkGfm]}
                      components={{
                        a: ({ onClick, ...props }) => (
                          <a
                            {...props}
                            target="_blank"
                            rel="noopener noreferrer"
                            onClick={(event) => {
                              event.stopPropagation();
                              onClick?.(event);
                            }}
                          />
                        ),
                      }}
                    >
                      {pendingDesc ?? task.description ?? ''}
                    </Markdown>
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
                      {a.shareUrl && (
                        <Tooltip label="Shared publicly">
                          <ActionIcon
                            component="a"
                            href={a.shareUrl}
                            target="_blank"
                            rel="noreferrer"
                            variant="subtle"
                            size="sm"
                            aria-label={`Public link to ${a.name}`}
                            style={{ color: 'var(--app-warning-fg)' }}
                          >
                            <IconWorld size={15} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                      {a.shareUrl && canExecute && (
                        <Tooltip label="Stop sharing">
                          <ActionIcon
                            variant="subtle"
                            size="sm"
                            onClick={() => handleUnshareAsset(a.id)}
                            aria-label={`Stop sharing ${a.name}`}
                            style={{ color: 'var(--mantine-color-placeholder)' }}
                          >
                            <IconWorldOff size={15} />
                          </ActionIcon>
                        </Tooltip>
                      )}
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
