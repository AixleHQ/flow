import AddIcon from '@mui/icons-material/Add';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import { Autocomplete, Box, Button, Chip, Link, MenuItem, TextField, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useCallback, useMemo, useState } from 'react';

import type { BoardTask } from 'entities/board-task';
import { TASK_TYPE_COLORS } from 'entities/board-task';
import { Routes } from 'shared/routes';

import {
  useCreateTaskMutation,
  useGetBoardQuery,
  useGetProjectMembersQuery,
  useGetTaskWorkflowRunsQuery,
  useUpdateTaskMutation,
} from '../api/boardApi';
import { useBoardSidebarStore } from '../model/useBoardSidebarStore';

import { CreateTaskDialog } from './CreateTaskDialog';

interface TaskDetailsTabProps {
  task: BoardTask;
  projectId: number;
}

const styles = {
  section: { mb: 2.5 },
  label: { fontSize: '12px', fontWeight: 600, color: 'text.secondary', textTransform: 'uppercase', mb: 0.5 },
  description: { fontSize: '14px', color: 'text.primary', whiteSpace: 'pre-wrap' },
  tags: { display: 'flex', gap: 0.5, flexWrap: 'wrap' },
  hierarchy: { mt: 2, p: 1.5, backgroundColor: 'action.hover', borderRadius: '8px' },
  childItem: {
    display: 'flex',
    alignItems: 'center',
    gap: 1,
    py: 0.5,
    cursor: 'pointer',
    '&:hover': { backgroundColor: 'action.hover' },
    borderRadius: '4px',
    px: 0.5,
  },
} satisfies Record<string, SxProps<Theme>>;

export const TaskDetailsTab = ({ task, projectId }: TaskDetailsTabProps) => {
  const [updateTask] = useUpdateTaskMutation();
  const [createTask] = useCreateTaskMutation();
  const [editingDesc, setEditingDesc] = useState(false);
  const [descValue, setDescValue] = useState(task.description || '');
  const [childDialogOpen, setChildDialogOpen] = useState(false);
  const { openTask } = useBoardSidebarStore();

  const { data: collaborators } = useGetProjectMembersQuery(projectId);
  const { data: boardData } = useGetBoardQuery(projectId);
  const { data: workflowRuns = [] } = useGetTaskWorkflowRunsQuery({ projectId, taskId: task.id });

  const members = collaborators?.items || [];
  const epicTasks = useMemo(
    () => boardData?.tasks.filter((t) => t.taskType === 'epic' && t.id !== task.id) || [],
    [boardData, task.id],
  );
  const childTasks = useMemo(
    () => boardData?.tasks.filter((t) => t.parentTaskId === task.id) || [],
    [boardData, task.id],
  );
  const columns = boardData?.board.boardColumns || [];

  const handleDescBlur = useCallback(() => {
    setEditingDesc(false);
    if (descValue !== (task.description || '')) {
      updateTask({ projectId, taskId: task.id, boardTask: { description: descValue } });
    }
  }, [descValue, task, projectId, updateTask]);

  const handleFieldChange = useCallback(
    (field: string, value: string | number | string[] | null) => {
      updateTask({ projectId, taskId: task.id, boardTask: { [field]: value } });
    },
    [projectId, task.id, updateTask],
  );

  return (
    <Box>
      <Box sx={styles.section}>
        <Typography sx={styles.label}>Description</Typography>
        {editingDesc ? (
          <TextField
            multiline
            fullWidth
            minRows={3}
            size="small"
            value={descValue}
            onChange={(e) => setDescValue(e.target.value)}
            onBlur={handleDescBlur}
            autoFocus
          />
        ) : (
          <Box onClick={() => setEditingDesc(true)} sx={{ cursor: 'pointer', minHeight: 40 }}>
            <Typography sx={styles.description}>{task.description || 'Click to add description...'}</Typography>
          </Box>
        )}
      </Box>

      <Box sx={styles.section}>
        <Typography sx={styles.label}>Assignee</Typography>
        <TextField
          select
          size="small"
          fullWidth
          value={task.assigneeId ?? ''}
          onChange={(e) => handleFieldChange('assigneeId', e.target.value ? Number(e.target.value) : null)}
        >
          <MenuItem value="">Unassigned</MenuItem>
          {members.map((m) => (
            <MenuItem key={m.id} value={m.id}>
              {m.name || m.email}
            </MenuItem>
          ))}
        </TextField>
      </Box>

      <Box sx={styles.section}>
        <Typography sx={styles.label}>Type</Typography>
        <TextField
          select
          size="small"
          fullWidth
          value={task.taskType}
          onChange={(e) => handleFieldChange('taskType', e.target.value)}
        >
          <MenuItem value="not_specified">Not specified</MenuItem>
          <MenuItem value="epic">Epic</MenuItem>
          <MenuItem value="story">Story</MenuItem>
          <MenuItem value="bug">Bug</MenuItem>
        </TextField>
      </Box>

      <Box sx={styles.section}>
        <Typography sx={styles.label}>Priority</Typography>
        <TextField
          select
          size="small"
          fullWidth
          value={task.priority || ''}
          onChange={(e) => handleFieldChange('priority', e.target.value || null)}
        >
          <MenuItem value="">None</MenuItem>
          <MenuItem value="low">Low</MenuItem>
          <MenuItem value="medium">Medium</MenuItem>
          <MenuItem value="high">High</MenuItem>
          <MenuItem value="critical">Critical</MenuItem>
        </TextField>
      </Box>

      {task.taskType !== 'epic' && epicTasks.length > 0 && (
        <Box sx={styles.section}>
          <Typography sx={styles.label}>Parent Epic</Typography>
          <TextField
            select
            size="small"
            fullWidth
            value={task.parentTaskId ?? ''}
            onChange={(e) => handleFieldChange('parentTaskId', e.target.value ? Number(e.target.value) : null)}
          >
            <MenuItem value="">None</MenuItem>
            {epicTasks.map((epic) => (
              <MenuItem key={epic.id} value={epic.id}>
                {epic.title}
              </MenuItem>
            ))}
          </TextField>
        </Box>
      )}

      <Box sx={styles.section}>
        <Typography sx={styles.label}>Tags</Typography>
        <Autocomplete
          multiple
          freeSolo
          size="small"
          options={[]}
          value={task.tags}
          onChange={(_, newValue) => handleFieldChange('tags', newValue)}
          renderTags={(value, getTagProps) =>
            value.map((tag, index) => <Chip {...getTagProps({ index })} key={tag} label={tag} size="small" />)
          }
          renderInput={(params) => <TextField {...params} placeholder="Add tag and press Enter" />}
        />
      </Box>

      {workflowRuns.length > 0 && (
        <Box sx={styles.hierarchy}>
          <Typography sx={styles.label}>Workflow Runs ({workflowRuns.length})</Typography>
          {workflowRuns.map((run) => (
            <Box key={run.id} sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.5 }}>
              <Chip
                label={run.state}
                size="small"
                color={
                  run.state === 'completed'
                    ? 'success'
                    : run.state === 'failed'
                      ? 'error'
                      : run.state === 'running'
                        ? 'primary'
                        : 'default'
                }
                sx={{ fontSize: '10px', height: 20, fontWeight: 600 }}
              />
              <Link
                component="a"
                href={Routes.frontend.workflowRunPath(String(projectId), String(run.id))}
                target="_blank"
                rel="noopener"
                underline="hover"
                sx={{ fontSize: '13px', flex: 1, display: 'flex', alignItems: 'center', gap: 0.5 }}
              >
                {run.workflowName}
                <OpenInNewIcon sx={{ fontSize: 12 }} />
              </Link>
              <Typography sx={{ fontSize: '11px', color: 'text.disabled' }}>
                {new Date(run.createdAt).toLocaleString()}
              </Typography>
            </Box>
          ))}
        </Box>
      )}

      {task.taskType === 'epic' && (
        <Box sx={styles.hierarchy}>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
            <Typography sx={styles.label}>Child Tasks ({childTasks.length})</Typography>
            <Button
              size="small"
              startIcon={<AddIcon />}
              onClick={() => setChildDialogOpen(true)}
              sx={{ textTransform: 'none', fontSize: '12px' }}
            >
              Add
            </Button>
          </Box>
          {childTasks.map((child) => (
            <Box key={child.id} sx={styles.childItem} onClick={() => openTask(child.id)}>
              <Chip
                label={child.taskType.replace('_', ' ')}
                size="small"
                sx={{
                  backgroundColor: TASK_TYPE_COLORS[child.taskType] || '#9e9e9e',
                  color: '#fff',
                  fontWeight: 600,
                  fontSize: '10px',
                  height: 18,
                }}
              />
              <Link component="button" underline="hover" sx={{ fontSize: '13px', textAlign: 'left' }}>
                {child.title}
              </Link>
            </Box>
          ))}
          {childTasks.length === 0 && (
            <Typography sx={{ fontSize: '13px', color: 'text.disabled' }}>No child tasks yet</Typography>
          )}
          <CreateTaskDialog
            open={childDialogOpen}
            onClose={() => setChildDialogOpen(false)}
            onSubmit={async (taskData) => {
              await createTask({ projectId, boardTask: taskData });
            }}
            columnId={task.boardColumnId}
            columns={columns}
            projectId={projectId}
            defaultParentTaskId={task.id}
          />
        </Box>
      )}

      {task.taskType !== 'epic' && task.parentTaskId && (
        <Box sx={styles.hierarchy}>
          <Typography sx={styles.label}>Parent Epic</Typography>
          {(() => {
            const parent = boardData?.tasks.find((t) => t.id === task.parentTaskId);
            return parent ? (
              <Link component="button" underline="hover" onClick={() => openTask(parent.id)} sx={{ fontSize: '13px' }}>
                {parent.title}
              </Link>
            ) : null;
          })()}
        </Box>
      )}
    </Box>
  );
};
