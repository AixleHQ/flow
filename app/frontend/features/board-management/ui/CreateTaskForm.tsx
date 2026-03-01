import { Box, Button, MenuItem, TextField } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

interface CreateTaskFormProps {
  onSubmit: (data: { title: string; taskType: string; boardColumnId: number }) => void;
  onCancel: () => void;
  columnId: number;
}

const styles = {
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: 1,
    p: 1.5,
    backgroundColor: 'background.paper',
    borderRadius: '8px',
  },
} satisfies Record<string, SxProps<Theme>>;

export const CreateTaskForm = ({ onSubmit, onCancel, columnId }: CreateTaskFormProps) => {
  const [title, setTitle] = useState('');
  const [taskType, setTaskType] = useState('not_specified');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    onSubmit({ title: title.trim(), taskType, boardColumnId: columnId });
    setTitle('');
  };

  return (
    <Box component="form" onSubmit={handleSubmit} sx={styles.form}>
      <TextField
        autoFocus
        size="small"
        placeholder="Task title..."
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => e.key === 'Escape' && onCancel()}
      />
      <TextField select size="small" value={taskType} onChange={(e) => setTaskType(e.target.value)} label="Type">
        <MenuItem value="not_specified">Not specified</MenuItem>
        <MenuItem value="epic">Epic</MenuItem>
        <MenuItem value="story">Story</MenuItem>
        <MenuItem value="bug">Bug</MenuItem>
      </TextField>
      <Box sx={{ display: 'flex', gap: 1 }}>
        <Button type="submit" variant="contained" size="small" disabled={!title.trim()}>
          Add
        </Button>
        <Button size="small" onClick={onCancel}>
          Cancel
        </Button>
      </Box>
    </Box>
  );
};
