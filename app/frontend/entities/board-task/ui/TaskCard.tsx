import ChatBubbleOutlineIcon from '@mui/icons-material/ChatBubbleOutline';
import {
  Avatar,
  Box,
  Card,
  CardActionArea,
  CardContent,
  Chip,
  CircularProgress,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import type { BoardTask } from '../model/types';
import { PRIORITY_COLORS, TASK_TYPE_COLORS } from '../model/types';

interface TaskCardProps {
  task: BoardTask;
  onClick?: (task: BoardTask) => void;
  isDragging?: boolean;
}

const styles = {
  card: {
    mb: 1,
    borderRadius: '8px',
    transition: 'box-shadow 0.15s',
    '&:hover': { boxShadow: 3 },
  },
  dragging: {
    opacity: 0.5,
  },
  content: {
    p: '10px !important',
    '&:last-child': { pb: '10px !important' },
  },
  titleRow: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 0.5,
    mb: 0.5,
  },
  title: {
    fontSize: '13px',
    fontWeight: 500,
    lineHeight: 1.3,
    flex: 1,
    wordBreak: 'break-word',
  },
  meta: {
    display: 'flex',
    alignItems: 'center',
    gap: 0.75,
    flexWrap: 'wrap',
    mt: 0.75,
  },
  typeChip: {
    height: 20,
    fontSize: '10px',
    fontWeight: 600,
  },
  priorityDot: {
    width: 8,
    height: 8,
    borderRadius: '50%',
    flexShrink: 0,
  },
  tagChip: {
    height: 18,
    fontSize: '10px',
  },
  footer: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    mt: 0.75,
  },
  commentBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: 0.25,
    color: 'text.secondary',
    fontSize: '11px',
  },
  workflowIndicator: {
    display: 'flex',
    alignItems: 'center',
  },
} satisfies Record<string, SxProps<Theme>>;

export const TaskCard = ({ task, onClick, isDragging }: TaskCardProps) => {
  const visibleTags = task.tags.slice(0, 3);
  const overflowCount = task.tags.length - 3;

  return (
    <Card sx={{ ...styles.card, ...(isDragging ? styles.dragging : {}) }} elevation={1}>
      <CardActionArea onClick={() => onClick?.(task)} disabled={!onClick}>
        <CardContent sx={styles.content}>
          <Box sx={styles.titleRow}>
            {task.priority && (
              <Tooltip title={task.priority}>
                <Box sx={{ ...styles.priorityDot, backgroundColor: PRIORITY_COLORS[task.priority] || '#9e9e9e' }} />
              </Tooltip>
            )}
            <Typography sx={styles.title}>{task.title}</Typography>
            {task.activeWorkflowRun && (
              <Tooltip title={`Workflow ${task.activeWorkflowRun.status}`}>
                <Box sx={styles.workflowIndicator}>
                  <CircularProgress size={14} />
                </Box>
              </Tooltip>
            )}
          </Box>

          <Box sx={styles.meta}>
            <Chip
              label={task.taskType.replace('_', ' ')}
              size="small"
              sx={{ ...styles.typeChip, backgroundColor: TASK_TYPE_COLORS[task.taskType] || '#9e9e9e', color: '#fff' }}
            />
            {visibleTags.map((tag) => (
              <Chip key={tag} label={tag} size="small" variant="outlined" sx={styles.tagChip} />
            ))}
            {overflowCount > 0 && (
              <Chip label={`+${overflowCount}`} size="small" variant="outlined" sx={styles.tagChip} />
            )}
          </Box>

          <Box sx={styles.footer}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
              {task.assigneeId && (
                <Tooltip title={task.assigneeName || 'Assigned'}>
                  <Avatar sx={{ width: 20, height: 20, fontSize: '10px' }}>
                    {task.assigneeName
                      ? task.assigneeName
                          .split(' ')
                          .map((w) => w[0])
                          .join('')
                          .slice(0, 2)
                          .toUpperCase()
                      : 'U'}
                  </Avatar>
                </Tooltip>
              )}
            </Box>
            {task.commentsCount > 0 && (
              <Box sx={styles.commentBadge}>
                <ChatBubbleOutlineIcon sx={{ fontSize: 12 }} />
                {task.commentsCount}
              </Box>
            )}
          </Box>
        </CardContent>
      </CardActionArea>
    </Card>
  );
};
