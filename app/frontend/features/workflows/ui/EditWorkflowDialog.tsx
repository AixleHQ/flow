import { zodResolver } from '@hookform/resolvers/zod';
import { Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle, Stack, TextField } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect } from 'react';
import { useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import { useUpdateCompanyWorkflowMutation, useUpdateProjectWorkflowMutation } from '../api/workflowsApi';
import { workflowSchema, type WorkflowFormData } from '../lib/workflowSchema';
import type { Workflow } from '../lib/types';

interface EditWorkflowDialogProps {
  open: boolean;
  onClose: () => void;
  workflow: Workflow;
  projectId?: number;
}

const EditWorkflowDialog: FC<EditWorkflowDialogProps> = ({ open, onClose, workflow, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [updateCompanyWorkflow, { isLoading: isUpdatingCompany }] = useUpdateCompanyWorkflowMutation();
  const [updateProjectWorkflow, { isLoading: isUpdatingProject }] = useUpdateProjectWorkflowMutation();
  const isLoading = isUpdatingCompany || isUpdatingProject;

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<WorkflowFormData>({
    resolver: zodResolver(workflowSchema),
  });

  useEffect(() => {
    if (open) {
      reset({ name: workflow.name, description: workflow.description || '' });
    }
  }, [open, workflow, reset]);

  const handleClose = () => {
    reset();
    onClose();
  };

  const onSubmit = async (data: WorkflowFormData) => {
    try {
      if (projectId && workflow.scopeType === 'Project') {
        await updateProjectWorkflow({ projectId, id: workflow.id, ...data }).unwrap();
      } else {
        await updateCompanyWorkflow({ id: workflow.id, ...data }).unwrap();
      }
      enqueueSnackbar('Workflow updated', { variant: 'success' });
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, setError) || 'Failed to update workflow';
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Edit Workflow</DialogTitle>
      <form onSubmit={handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
            {workflow.hasActiveRuns && (
              <Alert severity="warning">
                Workflow has active runs. Changes will not affect them.
              </Alert>
            )}

            <TextField
              {...register('name')}
              label="Name"
              fullWidth
              autoFocus
              error={!!errors.name}
              helperText={errors.name?.message}
            />

            <TextField
              {...register('description')}
              label="Description"
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
            {isLoading ? 'Saving...' : 'Save'}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export { EditWorkflowDialog };
