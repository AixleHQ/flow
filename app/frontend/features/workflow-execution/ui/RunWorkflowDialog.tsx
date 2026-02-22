import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  FormControlLabel,
  FormLabel,
  Radio,
  RadioGroup,
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { useState, type FC } from 'react';

import { useCreateWorkflowRunMutation } from '../api/workflowRunsApi';

interface RunWorkflowDialogProps {
  open: boolean;
  onClose: () => void;
  workflowId: number;
  projectId: number;
  canRunNonInteractive: boolean;
  onSuccess?: (runId: number) => void;
}

export const RunWorkflowDialog: FC<RunWorkflowDialogProps> = ({
  open,
  onClose,
  workflowId,
  projectId,
  canRunNonInteractive,
  onSuccess,
}) => {
  const { enqueueSnackbar } = useSnackbar();
  const [mode, setMode] = useState<'interactive' | 'non_interactive' | 'mixed'>('interactive');
  const [createRun, { isLoading }] = useCreateWorkflowRunMutation();

  const handleSubmit = async () => {
    try {
      const result = await createRun({
        projectId,
        workflowId,
        mode,
      }).unwrap();
      enqueueSnackbar('Workflow run started', { variant: 'success' });
      onClose();
      onSuccess?.(result.id);
    } catch {
      enqueueSnackbar('Failed to start workflow run', { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Run Workflow</DialogTitle>
      <DialogContent>
        <FormControl component="fieldset" sx={{ mt: 1 }}>
          <FormLabel component="legend">Execution Mode</FormLabel>
          <RadioGroup
            value={mode}
            onChange={(e) =>
              setMode(e.target.value as 'interactive' | 'non_interactive' | 'mixed')
            }
          >
            <FormControlLabel
              value="interactive"
              control={<Radio />}
              label={
                <>
                  <Typography variant="body2" fontWeight={500}>
                    Interactive
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    Approve each step before proceeding
                  </Typography>
                </>
              }
            />
            <FormControlLabel
              value="mixed"
              control={<Radio />}
              label={
                <>
                  <Typography variant="body2" fontWeight={500}>
                    Mixed
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    Non-interactive steps auto-advance, others wait for approval
                  </Typography>
                </>
              }
            />
            <FormControlLabel
              value="non_interactive"
              control={<Radio />}
              disabled={!canRunNonInteractive}
              label={
                <>
                  <Typography variant="body2" fontWeight={500}>
                    Non-Interactive
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    {canRunNonInteractive
                      ? 'All steps run automatically without approval'
                      : 'Not all steps support non-interactive mode'}
                  </Typography>
                </>
              }
            />
          </RadioGroup>
        </FormControl>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" onClick={handleSubmit} disabled={isLoading}>
          {isLoading ? 'Starting...' : 'Start Workflow'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
