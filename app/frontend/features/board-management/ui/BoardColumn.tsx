import { useDroppable } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import AddIcon from '@mui/icons-material/Add';
import ChevronLeftIcon from '@mui/icons-material/ChevronLeft';
import ChevronRightIcon from '@mui/icons-material/ChevronRight';
import { Badge, Box, IconButton, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import type { BoardColumn as BoardColumnType, BoardTask } from 'entities/board-task';

import { SortableTaskCard } from './SortableTaskCard';

interface BoardColumnProps {
  column: BoardColumnType;
  tasks: BoardTask[];
  onTaskClick?: (task: BoardTask) => void;
  onAddTask?: (columnId: number) => void;
  isFiltered?: boolean;
  collapsed?: boolean;
  onToggleCollapse?: (columnId: number) => void;
}

const styles = {
  column: {
    flex: '0 0 280px',
    minWidth: 280,
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'background.paper',
    borderRadius: '10px',
    maxHeight: '100%',
  },
  collapsed: {
    flex: '0 0 44px',
    minWidth: 44,
    maxWidth: 44,
    backgroundColor: 'background.paper',
    borderRadius: '10px',
    maxHeight: '100%',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    cursor: 'pointer',
    py: 1.5,
    gap: 1,
    '&:hover': { backgroundColor: 'action.hover' },
    transition: 'background-color 0.15s',
  },
  columnOver: {
    backgroundColor: 'primary.50',
    outline: '2px solid',
    outlineColor: 'primary.main',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    p: '12px 12px 8px',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 1,
    overflow: 'hidden',
    cursor: 'pointer',
  },
  name: {
    fontSize: '13px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  collapsedName: {
    writingMode: 'vertical-rl',
    textOrientation: 'mixed',
    fontSize: '12px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    whiteSpace: 'nowrap',
  },
  count: {
    fontSize: '11px',
    fontWeight: 600,
    color: 'text.disabled',
    backgroundColor: 'action.hover',
    borderRadius: '10px',
    px: 0.75,
    py: 0.15,
    flexShrink: 0,
  },
  taskList: {
    flex: 1,
    overflowY: 'auto',
    px: 1.5,
    pb: 1.5,
    minHeight: 60,
  },
  empty: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    py: 4,
    color: 'text.disabled',
    fontSize: '13px',
  },
} satisfies Record<string, SxProps<Theme>>;

export const BoardColumnComponent = ({
  column,
  tasks,
  onTaskClick,
  onAddTask,
  isFiltered,
  collapsed,
  onToggleCollapse,
}: BoardColumnProps) => {
  const { setNodeRef, isOver } = useDroppable({ id: `column-${column.id}`, data: { columnId: column.id } });

  if (collapsed) {
    return (
      <Tooltip title={`${column.name} (${tasks.length})`} placement="top" arrow>
        <Box
          sx={{ ...styles.collapsed, ...(isOver ? styles.columnOver : {}) }}
          ref={setNodeRef}
          onClick={() => onToggleCollapse?.(column.id)}
        >
          <Badge badgeContent={tasks.length} color="default" max={99}>
            <ChevronRightIcon fontSize="small" sx={{ color: 'text.disabled' }} />
          </Badge>
          <Typography sx={styles.collapsedName}>{column.name}</Typography>
        </Box>
      </Tooltip>
    );
  }

  const sortedTasks = [...tasks].sort((a, b) => a.position - b.position);
  const taskIds = sortedTasks.map((t) => `task-${t.id}`);

  return (
    <Box sx={{ ...styles.column, ...(isOver ? styles.columnOver : {}) }} ref={setNodeRef}>
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Tooltip title="Collapse column">
            <IconButton size="small" onClick={() => onToggleCollapse?.(column.id)} sx={{ p: 0.25 }}>
              <ChevronLeftIcon sx={{ fontSize: 16, color: 'text.disabled' }} />
            </IconButton>
          </Tooltip>
          {column.purpose ? (
            <Tooltip title={column.purpose} arrow>
              <Typography sx={styles.name}>{column.name}</Typography>
            </Tooltip>
          ) : (
            <Typography sx={styles.name}>{column.name}</Typography>
          )}
          <Typography sx={styles.count}>{tasks.length}</Typography>
        </Box>
        <IconButton size="small" onClick={() => onAddTask?.(column.id)}>
          <AddIcon fontSize="small" />
        </IconButton>
      </Box>

      <SortableContext items={taskIds} strategy={verticalListSortingStrategy}>
        <Box sx={styles.taskList}>
          {sortedTasks.length === 0 ? (
            <Box sx={styles.empty}>{isFiltered ? 'No matching tasks' : 'No tasks yet'}</Box>
          ) : (
            sortedTasks.map((task) => <SortableTaskCard key={task.id} task={task} onClick={onTaskClick} />)
          )}
        </Box>
      </SortableContext>
    </Box>
  );
};
