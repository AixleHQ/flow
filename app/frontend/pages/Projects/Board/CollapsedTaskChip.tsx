import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Box, Tooltip } from '@mantine/core';

import { formatElapsedTime } from 'shared/lib/formatElapsedTime';

import { CHIP_TOOLTIP_PROPS } from './chipTooltip';
import { gateCiStatus } from './gates';
import { WORKFLOW_ACTIVE_STATES, workflowStatusColor } from './taskRuns';
import type { Task } from './types';

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

  const tooltipParts: string[] = [`#${task.id} · ${task.title}`];
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
export function CollapsedTaskChip({ task, onClick }: { task: Task; onClick?: (t: Task) => void }) {
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
          width: 34,
          height: 16,
          borderRadius: 3,
          backgroundColor: color,
          cursor: 'grab',
          touchAction: 'none',
          flexShrink: 0,
          animation: hasActiveRun ? 'priorityBarPulse 2s ease-in-out infinite' : undefined,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
        {...attributes}
        {...listeners}
      >
        <span
          style={{
            fontSize: 9,
            fontWeight: 600,
            color: 'rgba(255,255,255,0.75)',
            lineHeight: 1,
            userSelect: 'none',
            pointerEvents: 'none',
          }}
        >
          #{task.id}
        </span>
      </Box>
    </Tooltip>
  );
}
