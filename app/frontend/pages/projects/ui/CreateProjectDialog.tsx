import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  TextField,
  Alert,
  CircularProgress,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useEffect, useState } from 'react';

import type { IProject } from 'entities/project';

import { useCreateProjectMutation } from '../api/projectsApi';

const styles = {
  dialogContent: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
    minWidth: '400px',
    paddingTop: '24px',
    overflow: 'visible',
  },
  actions: {
    padding: '16px 24px',
  },
} satisfies Record<string, SxProps<Theme>>;

interface CreateProjectDialogProps {
  open: boolean;
  onClose: () => void;
  onSuccess: (project: IProject) => void;
}

const CreateProjectDialog = ({ open, onClose, onSuccess }: CreateProjectDialogProps) => {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState<string | null>(null);

  const [createProject, { isLoading }] = useCreateProjectMutation();

  useEffect(() => {
    if (open) {
      setName('');
      setDescription('');
      setError(null);
    }
  }, [open]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!name.trim()) {
      setError('Project name is required');
      return;
    }

    try {
      const result = await createProject({
        name: name.trim(),
        description: description.trim() || undefined,
      }).unwrap();

      onSuccess(result.data);
      onClose();
    } catch (err: unknown) {
      const apiError = err as { data?: { errors?: { name?: string[] } } };
      if (apiError.data?.errors?.name) {
        setError(apiError.data.errors.name[0]);
      } else {
        setError('Failed to create project. Please try again.');
      }
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <form onSubmit={handleSubmit}>
        <DialogTitle>Create New Project</DialogTitle>
        <DialogContent sx={styles.dialogContent}>
          {error && (
            <Alert severity="error" onClose={() => setError(null)}>
              {error}
            </Alert>
          )}
          <TextField
            autoFocus
            label="Project Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            fullWidth
            required
            disabled={isLoading}
            inputProps={{ maxLength: 100 }}
          />
          <TextField
            label="Description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            fullWidth
            multiline
            minRows={3}
            disabled={isLoading}
            inputProps={{ maxLength: 500 }}
          />
        </DialogContent>
        <DialogActions sx={styles.actions}>
          <Button onClick={onClose} disabled={isLoading}>
            Cancel
          </Button>
          <Button type="submit" variant="contained" disabled={isLoading || !name.trim()}>
            {isLoading ? <CircularProgress size={20} /> : 'Create'}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export default CreateProjectDialog;
