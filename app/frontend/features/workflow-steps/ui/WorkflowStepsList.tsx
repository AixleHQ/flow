import AddIcon from '@mui/icons-material/Add';
import { Box, Button, CircularProgress, Typography } from '@mui/material';
import { type FC, useState } from 'react';

import { useGetStepsQuery, useDeleteStepMutation } from '../api/stepsApi';
import type { Step } from '../lib/types';

import { AddStepDialog } from './AddStepDialog';
import { StepCard } from './StepCard';

interface WorkflowStepsListProps {
  projectId: number;
  workflowId: number;
}

const WorkflowStepsList: FC<WorkflowStepsListProps> = ({ projectId, workflowId }) => {
  const { data: steps, isLoading } = useGetStepsQuery({ projectId, workflowId });
  const [deleteStep] = useDeleteStepMutation();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingStep, setEditingStep] = useState<Step | null>(null);

  const handleDelete = async (id: number) => {
    await deleteStep({ projectId, workflowId, id });
  };

  const handleEdit = (step: Step) => {
    setEditingStep(step);
    setDialogOpen(true);
  };

  const handleCloseDialog = () => {
    setDialogOpen(false);
    setEditingStep(null);
  };

  if (isLoading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  const nextPosition = (steps?.length ?? 0) + 1;

  return (
    <Box>
      {steps && steps.length > 0 ? (
        steps.map((step) => (
          <StepCard key={step.id} step={step} allSteps={steps} onDelete={handleDelete} onEdit={handleEdit} />
        ))
      ) : (
        <Typography variant="body2" color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
          No steps yet. Add your first step to get started.
        </Typography>
      )}

      <Button startIcon={<AddIcon />} onClick={() => setDialogOpen(true)} variant="outlined" fullWidth sx={{ mt: 1 }}>
        Add Step
      </Button>

      <AddStepDialog
        open={dialogOpen}
        onClose={handleCloseDialog}
        projectId={projectId}
        workflowId={workflowId}
        nextPosition={nextPosition}
        editStep={editingStep}
      />
    </Box>
  );
};

export { WorkflowStepsList };
