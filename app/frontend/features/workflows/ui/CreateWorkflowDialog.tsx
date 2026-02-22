import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, Stack, TextField } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect } from 'react';
import { useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import { useCreateCompanyWorkflowMutation, useCreateProjectWorkflowMutation } from '../api/workflowsApi';
import { workflowSchema, type WorkflowFormData } from '../lib/workflowSchema';

interface CreateWorkflowDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
  onSuccess?: (workflowId: number) => void;
}

const CreateWorkflowDialog: FC<CreateWorkflowDialogProps> = ({ open, onClose, projectId, onSuccess }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanyWorkflow, { isLoading: isCreatingCompany }] = useCreateCompanyWorkflowMutation();
  const [createProjectWorkflow, { isLoading: isCreatingProject }] = useCreateProjectWorkflowMutation();

  const isLoading = isCreatingCompany || isCreatingProject;

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<WorkflowFormData>({
    resolver: zodResolver(workflowSchema),
    defaultValues: {
      name: '',
      description: '',
    },
  });

  useEffect(() => {
    if (open) {
      reset({ name: '', description: '' });
    }
  }, [open, reset]);

  const handleClose = () => {
    reset();
    onClose();
  };

  const onSubmit = async (data: WorkflowFormData) => {
    try {
      let result;
      if (projectId) {
        result = await createProjectWorkflow({ projectId, ...data }).unwrap();
      } else {
        result = await createCompanyWorkflow(data).unwrap();
      }
      enqueueSnackbar('Workflow created successfully', { variant: 'success' });
      handleClose();
      if (onSuccess && result?.id) {
        onSuccess(result.id);
      }
    } catch (error: unknown) {
      const message = setErrorsToForm(error, setError) || 'Failed to create workflow';
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>New Workflow</DialogTitle>
      <form onSubmit={handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
            <TextField
              {...register('name')}
              label="Name"
              placeholder="My Workflow"
              fullWidth
              autoFocus
              error={!!errors.name}
              helperText={errors.name?.message}
            />

            <TextField
              {...register('description')}
              label="Description"
              placeholder="What this workflow does..."
              fullWidth
              multiline
              rows={3}
              error={!!errors.description}
              helperText={errors.description?.message}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={isLoading}>
            Cancel
          </Button>
          <Button type="submit" variant="contained" disabled={isLoading}>
            {isLoading ? 'Creating...' : 'Create'}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export { CreateWorkflowDialog };
