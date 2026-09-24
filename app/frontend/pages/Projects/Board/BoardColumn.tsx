import { useDroppable } from '@dnd-kit/core';
import { SortableContext, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { ActionIcon, Box, Button, Group, Menu, Text, TextInput, Tooltip } from '@mantine/core';
import {
  IconArrowLeft,
  IconArrowRight,
  IconBolt,
  IconCheck,
  IconChevronDown,
  IconChevronsRight,
  IconDots,
  IconFold,
  IconMinus,
  IconPencil,
  IconPlus,
  IconTrash,
} from '@tabler/icons-react';
import { useEffect, useMemo, useRef, useState } from 'react';

import styles from './BoardPage.module.css';
import { CollapsedTaskChip } from './CollapsedTaskChip';
import { SortableTaskCard } from './SortableTaskCard';
import { workflowStatusColor } from './taskRuns';
import type { Column, Task } from './types';

// How close to the bottom of a column the scroll has to get before its next page is fetched.
const LOAD_MORE_SCROLL_THRESHOLD_PX = 200;

export function BoardColumn({
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
  onToggleColumn,
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
  onToggleColumn?: (columnId: number, taskIds: number[], select: boolean) => void;
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
          ...colStyle,
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

        {/* Column name — vertical-rl, no rotation, reads naturally. Carries the drag
            listeners (mirroring the expanded header's title) so a collapsed column can
            still be reordered instead of only being expandable/collapsible. */}
        <Tooltip label={column.name} position="right">
          <div
            {...colListeners}
            style={{
              writingMode: 'vertical-rl',
              color: 'var(--mantine-color-text)',
              fontWeight: 600,
              fontSize: 13,
              letterSpacing: '-0.01em',
              userSelect: 'none',
              cursor: 'grab',
              touchAction: 'none',
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
        {/* Left: column tri-state checkbox (selection mode) + name (drag handle) + count + bolt chip */}
        <Group gap={6} style={{ overflow: 'hidden', flex: 1, minWidth: 0 }}>
          {selectionMode &&
            onToggleColumn &&
            (() => {
              const colTaskIds = tasks.map((t) => t.id);
              const selectedInCol = colTaskIds.filter((id) => selectedIds?.has(id)).length;
              const allSelected = colTaskIds.length > 0 && selectedInCol === colTaskIds.length;
              const someSelected = selectedInCol > 0 && !allSelected;
              return (
                <Box
                  component="button"
                  className={[
                    styles.colHeaderCheck,
                    styles.colHeaderCheckVisible,
                    allSelected ? styles.colHeaderCheckOn : someSelected ? styles.colHeaderCheckSome : '',
                  ]
                    .filter(Boolean)
                    .join(' ')}
                  aria-label={`Toggle all tasks in ${column.name}`}
                  aria-pressed={allSelected}
                  onClick={(e: React.MouseEvent) => {
                    e.stopPropagation();
                    onToggleColumn(column.id, colTaskIds, !allSelected);
                  }}
                  onMouseDown={(e: React.MouseEvent) => e.stopPropagation()}
                >
                  {allSelected && <IconCheck size={10} />}
                  {someSelected && <IconMinus size={10} />}
                </Box>
              );
            })()}
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
        <Box onScroll={handleScroll} style={{ flex: 1, overflowY: 'auto', padding: '8px 12px 12px', minHeight: 60 }}>
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
