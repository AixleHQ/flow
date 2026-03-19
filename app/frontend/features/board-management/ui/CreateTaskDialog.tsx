import {
  Autocomplete,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  MenuItem,
  Stack,
  TextField,
} from '@mui/material';
import { type FC, useMemo, useState } from 'react';

import type { BoardColumn, BoardTask } from 'entities/board-task';

import { useGetBoardQuery, useGetProjectMembersQuery } from '../api/boardApi';

interface CreateTaskDialogProps {
  open: boolean;
  onClose: () => void;
  onSubmit: (data: Partial<BoardTask>) => Promise<void>;
  columnId: number;
  columns: BoardColumn[];
  projectId: number;
  defaultParentTaskId?: number;
}

const TASK_TYPES = [
  { value: 'not_specified', label: 'Not specified' },
  { value: 'epic', label: 'Epic' },
  { value: 'story', label: 'Story' },
  { value: 'bug', label: 'Bug' },
];

const PRIORITIES = [
  { value: '', label: 'None' },
  { value: 'low', label: 'Low' },
  { value: 'medium', label: 'Medium' },
  { value: 'high', label: 'High' },
  { value: 'critical', label: 'Critical' },
];

export const CreateTaskDialog: FC<CreateTaskDialogProps> = ({
  open,
  onClose,
  onSubmit,
  columnId,
  columns,
  projectId,
  defaultParentTaskId,
}) => {
  const hasDefaultParent = Boolean(defaultParentTaskId);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [taskType, setTaskType] = useState('not_specified');
  const [priority, setPriority] = useState('');
  const [selectedColumnId, setSelectedColumnId] = useState(columnId);
  const [tags, setTags] = useState<string[]>([]);
  const [assigneeId, setAssigneeId] = useState<number | ''>('');
  const [parentTaskId, setParentTaskId] = useState<number | ''>(defaultParentTaskId ?? '');
  const [saving, setSaving] = useState(false);

  const { data: collaborators } = useGetProjectMembersQuery(projectId);
  const { data: boardData } = useGetBoardQuery(projectId);

  const epicTasks = useMemo(() => boardData?.tasks.filter((t) => t.taskType === 'epic') || [], [boardData]);

  const members = collaborators?.items || [];

  const handleSubmit = async () => {
    if (!title.trim()) return;
    setSaving(true);
    try {
      await onSubmit({
        title: title.trim(),
        description: description.trim() || null,
        taskType,
        priority: priority || null,
        boardColumnId: selectedColumnId,
        tags,
        assigneeId: assigneeId || null,
        parentTaskId: parentTaskId || null,
      });
      handleClose();
    } finally {
      setSaving(false);
    }
  };

  const handleClose = () => {
    setTitle('');
    setDescription('');
    setTaskType('not_specified');
    setPriority('');
    setSelectedColumnId(columnId);
    setTags([]);
    setAssigneeId('');
    setParentTaskId(defaultParentTaskId ?? '');
    onClose();
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Create Task</DialogTitle>
      <DialogContent>
        <Stack spacing={2.5} sx={{ mt: 1 }}>
          <TextField
            autoFocus
            label="Title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            fullWidth
            required
          />

          <TextField
            label="Description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            fullWidth
            multiline
            minRows={3}
          />

          <Stack direction="row" spacing={2}>
            <TextField
              select
              label="Type"
              value={taskType}
              onChange={(e) => {
                const val = e.target.value;
                setTaskType(val);
                if (val === 'epic') setParentTaskId('');
              }}
              sx={{ flex: 1 }}
            >
              {TASK_TYPES.filter((t) => !hasDefaultParent || t.value !== 'epic').map((t) => (
                <MenuItem key={t.value} value={t.value}>
                  {t.label}
                </MenuItem>
              ))}
            </TextField>

            <TextField
              select
              label="Priority"
              value={priority}
              onChange={(e) => setPriority(e.target.value)}
              sx={{ flex: 1 }}
            >
              {PRIORITIES.map((p) => (
                <MenuItem key={p.value} value={p.value}>
                  {p.label}
                </MenuItem>
              ))}
            </TextField>
          </Stack>

          <Stack direction="row" spacing={2}>
            <TextField
              select
              label="Column"
              value={selectedColumnId}
              onChange={(e) => setSelectedColumnId(Number(e.target.value))}
              sx={{ flex: 1 }}
            >
              {columns.map((col) => (
                <MenuItem key={col.id} value={col.id}>
                  {col.name}
                </MenuItem>
              ))}
            </TextField>

            <TextField
              select
              label="Assignee"
              value={assigneeId}
              onChange={(e) => setAssigneeId(e.target.value ? Number(e.target.value) : '')}
              sx={{ flex: 1 }}
            >
              <MenuItem value="">Unassigned</MenuItem>
              {members.map((m) => (
                <MenuItem key={m.id} value={m.id}>
                  {m.name || m.email}
                </MenuItem>
              ))}
            </TextField>
          </Stack>

          {taskType !== 'epic' && epicTasks.length > 0 && (
            <TextField
              select
              label="Parent Epic"
              value={parentTaskId}
              onChange={(e) => setParentTaskId(e.target.value ? Number(e.target.value) : '')}
              fullWidth
            >
              <MenuItem value="">None</MenuItem>
              {epicTasks.map((epic) => (
                <MenuItem key={epic.id} value={epic.id}>
                  {epic.title}
                </MenuItem>
              ))}
            </TextField>
          )}

          <Autocomplete
            multiple
            freeSolo
            options={[]}
            value={tags}
            onChange={(_, newValue) => setTags(newValue)}
            renderTags={(value, getTagProps) =>
              value.map((tag, index) => <Chip {...getTagProps({ index })} key={tag} label={tag} size="small" />)
            }
            renderInput={(params) => <TextField {...params} label="Tags" placeholder="Type and press Enter" />}
          />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose} disabled={saving}>
          Cancel
        </Button>
        <Button variant="contained" onClick={handleSubmit} disabled={!title.trim() || saving}>
          {saving ? 'Creating...' : 'Create'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
