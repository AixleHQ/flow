import ChatBubbleOutlineIcon from '@mui/icons-material/ChatBubbleOutline';
import { Avatar, Box, Card, CardActionArea, CardContent, Chip, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import type { BoardTask } from '../model/types';
import { PRIORITY_COLORS, TASK_TYPE_COLORS } from '../model/types';
import { WORKFLOW_ACTIVE_STATES, workflowPulse, workflowStatusColor } from '../model/workflowStatus';

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
  workflowDots: {
    display: 'flex',
    alignItems: 'center',
    gap: '3px',
    flexShrink: 0,
    ml: 0.5,
  },
} satisfies Record<string, SxProps<Theme>>;

function workflowDotLabel(state: string): string {
  return state.charAt(0).toUpperCase() + state.slice(1);
}

export const TaskCard = ({ task, onClick, isDragging }: TaskCardProps) => {
  const visibleTags = task.tags.slice(0, 3);
  const overflowCount = task.tags.length - 3;
  const hasPendingWaits = task.pendingWaits.length > 0;
  const workflowTooltip = [
    ...task.recentWorkflowRuns.map((run) => `#${run.id} ${workflowDotLabel(run.state)}`),
    ...task.pendingWaits.map((wait) =>
      wait.waitType === 'github_checks_completed'
        ? `Wait: ${wait.metadata.repoFullName ?? 'Unknown repo'} #${wait.metadata.prNumber ?? 'Unknown PR'}`
        : `Wait: ${wait.waitType.replace(/_/g, ' ')}`,
    ),
  ].join(', ');

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
            {(hasPendingWaits || task.recentWorkflowRuns.length > 0) && (
              <Tooltip title={workflowTooltip}>
                <Box sx={styles.workflowDots}>
                  {[...task.recentWorkflowRuns].reverse().map((run) => (
                    <Box
                      key={run.id}
                      sx={{
                        width: 7,
                        height: 7,
                        borderRadius: '50%',
                        backgroundColor: workflowStatusColor(run.state),
                        ...(WORKFLOW_ACTIVE_STATES.has(run.state) && {
                          animation: `${workflowPulse} 1.5s ease-in-out infinite`,
                        }),
                      }}
                    />
                  ))}
                  {hasPendingWaits && (
                    <Box
                      sx={{
                        width: 7,
                        height: 7,
                        borderRadius: '50%',
                        backgroundColor: '#eab308',
                      }}
                    />
                  )}
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
