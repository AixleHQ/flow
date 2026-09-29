import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Box } from '@mantine/core';

import { TaskCardUI } from './TaskCardUI';
import type { Task } from './types';

// --- TaskCard (no grip handle, legacy style) ---

export function SortableTaskCard({
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
