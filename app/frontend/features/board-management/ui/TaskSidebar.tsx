import CloseIcon from '@mui/icons-material/Close';
import DeleteIcon from '@mui/icons-material/Delete';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import {
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Drawer,
  IconButton,
  Tab,
  Tabs,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useCallback, useEffect, useState } from 'react';

import { TASK_TYPE_COLORS } from 'entities/board-task';

import {
  useDeleteTaskMutation,
  useGetBoardQuery,
  useGetTaskDetailsQuery,
  useUpdateTaskMutation,
  useTriggerWorkflowMutation,
} from '../api/boardApi';
import { useBoardSidebarStore } from '../model/useBoardSidebarStore';

import { ActivityTab } from './ActivityTab';
import { AssetsTab } from './AssetsTab';
import { CommentsTab } from './CommentsTab';
import { TaskDetailsTab } from './TaskDetailsTab';

interface TaskSidebarProps {
  projectId: number;
}

const DRAWER_WIDTH = 480;
const HEADER_HEIGHT = 48;

const styles = {
  drawer: {
    width: DRAWER_WIDTH,
    flexShrink: 0,
    '& .MuiDrawer-paper': {
      width: DRAWER_WIDTH,
      top: HEADER_HEIGHT,
      height: `calc(100% - ${HEADER_HEIGHT}px)`,
    },
  },
  header: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    p: 2,
    borderBottom: '1px solid',
    borderColor: 'divider',
  },
  headerLeft: {
    flex: 1,
  },
  title: {
    fontSize: '18px',
    fontWeight: 600,
    mb: 0.5,
  },
  tabs: {
    borderBottom: '1px solid',
    borderColor: 'divider',
  },
  tab: {
    textTransform: 'none',
    fontSize: '13px',
    minHeight: 40,
  },
  content: {
    flex: 1,
    overflow: 'auto',
    p: 2,
  },
} satisfies Record<string, SxProps<Theme>>;

export const TaskSidebar = ({ projectId }: TaskSidebarProps) => {
  const { isOpen, activeTaskId, activeTab, close, setTab } = useBoardSidebarStore();
  const { data: boardData } = useGetBoardQuery(projectId);
  const { data: taskDetails } = useGetTaskDetailsQuery({ projectId, taskId: activeTaskId! }, { skip: !activeTaskId });
  const [triggerWorkflow, { isLoading: isTriggering }] = useTriggerWorkflowMutation();
  const [updateTask] = useUpdateTaskMutation();
  const [deleteTask] = useDeleteTaskMutation();

  const task = taskDetails ?? boardData?.tasks.find((t) => t.id === activeTaskId);
  const column = boardData?.board.boardColumns.find((c) => c.id === task?.boardColumnId);
  const hasActiveRun = task?.recentWorkflowRuns.some((r) => ['pending', 'running', 'paused'].includes(r.state));
  const canTriggerWorkflow = column?.workflowBinding?.triggerMode === 'manual' && !hasActiveRun;

  const [editingTitle, setEditingTitle] = useState(false);
  const [titleValue, setTitleValue] = useState('');
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

  useEffect(() => {
    if (task) setTitleValue(task.title);
  }, [task]);

  const handleTitleBlur = useCallback(() => {
    setEditingTitle(false);
    if (task && titleValue.trim() && titleValue !== task.title) {
      updateTask({ projectId, taskId: task.id, boardTask: { title: titleValue.trim() } });
    }
  }, [titleValue, task, projectId, updateTask]);

  const handleDelete = useCallback(() => {
    if (!task) return;
    deleteTask({ projectId, taskId: task.id });
    setDeleteDialogOpen(false);
    close();
  }, [task, projectId, deleteTask, close]);

  if (!isOpen || !task) return null;

  return (
    <Drawer variant="temporary" anchor="right" open={isOpen} onClose={close} sx={styles.drawer}>
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          {editingTitle ? (
            <TextField
              value={titleValue}
              onChange={(e) => setTitleValue(e.target.value)}
              onBlur={handleTitleBlur}
              onKeyDown={(e) => e.key === 'Enter' && handleTitleBlur()}
              autoFocus
              size="small"
              fullWidth
              sx={{ '& .MuiInputBase-input': { fontSize: '18px', fontWeight: 600 } }}
            />
          ) : (
            <Typography
              sx={{ ...styles.title, cursor: 'pointer', '&:hover': { color: 'primary.main' } }}
              onClick={() => setEditingTitle(true)}
            >
              {task.title}
            </Typography>
          )}
          <Chip
            label={task.taskType.replace('_', ' ')}
            size="small"
            sx={{
              backgroundColor: TASK_TYPE_COLORS[task.taskType] || '#9e9e9e',
              color: '#fff',
              fontWeight: 600,
              fontSize: '11px',
            }}
          />
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          {canTriggerWorkflow && (
            <Button
              variant="contained"
              size="small"
              startIcon={<PlayArrowIcon />}
              onClick={() => triggerWorkflow({ projectId, taskId: task.id })}
              disabled={isTriggering}
            >
              Start Workflow
            </Button>
          )}
          <Tooltip title="Delete task">
            <IconButton onClick={() => setDeleteDialogOpen(true)} size="small" color="error">
              <DeleteIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          <IconButton onClick={close} size="small">
            <CloseIcon />
          </IconButton>
        </Box>
      </Box>

      <Tabs value={activeTab} onChange={(_, val) => setTab(val)} sx={styles.tabs}>
        <Tab value="details" label="Details" sx={styles.tab} />
        <Tab value="comments" label={`Comments (${task.commentsCount})`} sx={styles.tab} />
        <Tab value="assets" label={`Assets (${task.assetsCount})`} sx={styles.tab} />
        <Tab value="activity" label="Activity" sx={styles.tab} />
      </Tabs>

      <Box sx={styles.content}>
        {activeTab === 'details' && <TaskDetailsTab task={task} projectId={projectId} />}
        {activeTab === 'comments' && <CommentsTab taskId={task.id} projectId={projectId} />}
        {activeTab === 'assets' && <AssetsTab taskId={task.id} projectId={projectId} />}
        {activeTab === 'activity' && <ActivityTab taskId={task.id} projectId={projectId} />}
      </Box>

      <Dialog open={deleteDialogOpen} onClose={() => setDeleteDialogOpen(false)}>
        <DialogTitle>Delete Task</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Are you sure you want to delete &quot;{task.title}&quot;? This action cannot be undone.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteDialogOpen(false)}>Cancel</Button>
          <Button onClick={handleDelete} color="error" variant="contained">
            Delete
          </Button>
        </DialogActions>
      </Dialog>
    </Drawer>
  );
};
