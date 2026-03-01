import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Box } from '@mui/material';

import type { BoardTask } from 'entities/board-task';
import { TaskCard } from 'entities/board-task';

interface SortableTaskCardProps {
  task: BoardTask;
  onClick?: (task: BoardTask) => void;
}

export const SortableTaskCard = ({ task, onClick }: SortableTaskCardProps) => {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: `task-${task.id}`,
    data: { task },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <Box ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <TaskCard task={task} onClick={onClick} isDragging={isDragging} />
    </Box>
  );
};
