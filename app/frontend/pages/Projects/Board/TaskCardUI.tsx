import { ActionIcon, Avatar, Badge, Box, Button, CopyButton, Group, Paper, Text, Tooltip } from '@mantine/core';
import {
  IconAlertCircle,
  IconArchive,
  IconBolt,
  IconCheck,
  IconCircleCheck,
  IconHourglass,
  IconMessage,
  IconRefresh,
  IconX,
} from '@tabler/icons-react';

import { formatDuration } from './boardFormat';
import styles from './BoardPage.module.css';
import { ciGateSummary } from './gates';
import { WORKFLOW_ACTIVE_STATES } from './taskRuns';
import { PRIORITY_COLORS, TASK_TYPE_COLORS, type Task } from './types';

function avatarInitials(name: string): string {
  return name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

export function TaskCardUI({
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
    if (e.defaultPrevented) return;
    if (!isLink) {
      onClick?.(task);
      return;
    }
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    onClick?.(task);
  };

  const cardClasses = [
    styles.taskCard,
    selectionMode || isSelected ? styles.taskCardSelectionMode : '',
    isSelected ? styles.taskCardSelected : '',
  ]
    .filter(Boolean)
    .join(' ');

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
      className={cardClasses}
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
        if (!isSelected) {
          (e.currentTarget as HTMLElement).style.borderColor = 'var(--mantine-color-brand-4)';
          (e.currentTarget as HTMLElement).style.backgroundColor = 'var(--app-bg-paper)';
        }
      }}
      onMouseLeave={(e: React.MouseEvent<HTMLElement>) => {
        if (!isSelected) {
          (e.currentTarget as HTMLElement).style.borderColor = 'var(--app-border-strong)';
          (e.currentTarget as HTMLElement).style.backgroundColor = 'var(--app-bg-elevated)';
        }
      }}
    >
      {/* Absolutely-positioned selection checkbox — slides in on hover or selection mode */}
      {onToggleSelect && (
        <Box
          component="button"
          role="checkbox"
          className={[styles.taskCardCheck, isSelected ? styles.taskCardCheckSelected : ''].filter(Boolean).join(' ')}
          aria-label={`Select ${task.title}`}
          aria-checked={!!isSelected}
          onPointerDown={(e: React.PointerEvent) => e.stopPropagation()}
          onClick={(e: React.MouseEvent) => {
            e.preventDefault();
            e.stopPropagation();
            onToggleSelect(task.id, !isSelected);
          }}
        >
          {isSelected && <IconCheck size={10} />}
        </Box>
      )}

      {/* Title row — padding-left animates in when checkbox is shown */}
      <Group gap={8} align="flex-start" wrap="nowrap" className={styles.taskCardTop}>
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
        <CopyButton value={String(task.id)}>
          {({ copied, copy }) => (
            <Tooltip label={copied ? 'Copied' : 'Copy ID'} withArrow>
              <Text
                size="sm"
                c="dimmed"
                style={{ flexShrink: 0, whiteSpace: 'nowrap', fontSize: 13, cursor: 'pointer' }}
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  copy();
                }}
              >
                #{task.id}
              </Text>
            </Tooltip>
          )}
        </CopyButton>
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

      {/* Duration on succeeded cards */}
      {isSuccess && latestRun && latestRun.durationSeconds != null && (
        <Group gap={8} mt={4}>
          <Text size="xs" c="dimmed" style={{ fontSize: 11 }}>
            ⏱ {formatDuration(latestRun.durationSeconds)}
          </Text>
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
