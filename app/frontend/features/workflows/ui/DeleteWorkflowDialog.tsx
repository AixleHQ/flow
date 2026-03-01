import { Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle, Typography } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC } from 'react';

import { useDeleteCompanyWorkflowMutation, useDeleteProjectWorkflowMutation } from '../api/workflowsApi';
import type { Workflow } from '../lib/types';

interface DeleteWorkflowDialogProps {
  open: boolean;
  onClose: () => void;
  workflow: Workflow;
  projectId?: number;
}

const DeleteWorkflowDialog: FC<DeleteWorkflowDialogProps> = ({ open, onClose, workflow, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [deleteCompanyWorkflow, { isLoading: isDeletingCompany }] = useDeleteCompanyWorkflowMutation();
  const [deleteProjectWorkflow, { isLoading: isDeletingProject }] = useDeleteProjectWorkflowMutation();
  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    try {
      if (projectId && workflow.scopeType === 'Project') {
        await deleteProjectWorkflow({ projectId, id: workflow.id }).unwrap();
      } else {
        await deleteCompanyWorkflow(workflow.id).unwrap();
      }
      enqueueSnackbar('Workflow deleted', { variant: 'success' });
      onClose();
    } catch (error: unknown) {
      const err = error as { data?: { error?: string } };
      enqueueSnackbar(err.data?.error || 'Failed to delete workflow', { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Delete Workflow</DialogTitle>
      <DialogContent>
        {workflow.hasActiveRuns ? (
          <Alert severity="error" sx={{ mb: 2 }}>
            Cannot delete workflow with active runs. Stop all runs first.
          </Alert>
        ) : (
          <>
            <Typography>
              Delete workflow <strong>&#34;{workflow.name}&#34;</strong>? This will remove all steps. Historical runs
              will be preserved.
            </Typography>
          </>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button onClick={handleDelete} variant="contained" color="error" disabled={isLoading || workflow.hasActiveRuns}>
          {isLoading ? 'Deleting...' : 'Delete'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export { DeleteWorkflowDialog };
