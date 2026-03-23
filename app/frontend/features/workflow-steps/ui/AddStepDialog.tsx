import { zodResolver } from '@hookform/resolvers/zod';
import {
  Autocomplete,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  MenuItem,
  Stack,
  Switch,
  TextField,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect, useState } from 'react';
import { Controller, type Resolver, useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';
import type { AgentModel } from 'shared/api/agentModelsApi';
import { useGetAgentModelsQuery } from 'shared/api/agentModelsApi';
import { useGetCurrentUserQuery } from 'entities/user';

import { useCreateStepMutation, useUpdateStepMutation } from '../api/stepsApi';
import { stepSchema, type StepFormData } from '../lib/stepSchema';
import type { Step } from '../lib/types';

interface AddStepDialogProps {
  open: boolean;
  onClose: () => void;
  projectId: number;
  workflowId: number;
  nextPosition: number;
  editStep?: Step | null;
}

const AddStepDialog: FC<AddStepDialogProps> = ({ open, onClose, projectId, workflowId, nextPosition, editStep }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [createStep, { isLoading: isCreating }] = useCreateStepMutation();
  const [updateStep, { isLoading: isUpdating }] = useUpdateStepMutation();
  const isLoading = isCreating || isUpdating;
  const isEditMode = !!editStep;

  const {
    register,
    handleSubmit,
    reset,
    setError,
    control,
    formState: { errors },
  } = useForm<StepFormData>({
    resolver: zodResolver(stepSchema) as Resolver<StepFormData>,
    defaultValues: {
      name: '',
      description: '',
      instructions: '',
      allowNonInteractive: false,
      skipPolicy: 'never',
      onFailure: 'fail',
      maxRetries: 0,
    },
  });

  useEffect(() => {
    if (open) {
      if (editStep) {
        reset({
          name: editStep.name,
          description: editStep.description || '',
          instructions: editStep.instructions || '',
          allowNonInteractive: editStep.allowNonInteractive,
          skipPolicy: editStep.skipPolicy,
          onFailure: editStep.onFailure,
          maxRetries: editStep.maxRetries,
          preferredModel: editStep.preferredModel,
        });
        setStepModel(editStep.preferredModel ? { modelId: editStep.preferredModel, displayName: editStep.preferredModel, description: '' } : null);
      } else {
        reset({
          name: '',
          description: '',
          instructions: '',
          allowNonInteractive: false,
          skipPolicy: 'never',
          onFailure: 'fail',
          maxRetries: 0,
          preferredModel: null,
        });
        setStepModel(null);
      }
    }
  }, [open, editStep, reset]);

  const [stepModel, setStepModel] = useState<AgentModel | null>(null);
  const { data: currentUser } = useGetCurrentUserQuery();
  const modelRuntime = editStep?.requiredAgentRuntime || currentUser?.defaultAgentRuntime || '';
  const { data: agentModels } = useGetAgentModelsQuery(modelRuntime, { skip: !modelRuntime });

  const handleClose = () => {
    reset();
    onClose();
  };

  const onSubmit = async (data: StepFormData) => {
    try {
      if (isEditMode && editStep) {
        await updateStep({ projectId, workflowId, id: editStep.id, ...data }).unwrap();
        enqueueSnackbar('Step updated', { variant: 'success' });
      } else {
        await createStep({ projectId, workflowId, position: nextPosition, ...data }).unwrap();
        enqueueSnackbar('Step created', { variant: 'success' });
      }
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, setError) || `Failed to ${isEditMode ? 'update' : 'create'} step`;
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>{isEditMode ? 'Edit Step' : 'Add Step'}</DialogTitle>
      <form onSubmit={handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
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
              minRows={2}
              error={!!errors.description}
              helperText={errors.description?.message}
            />

            <TextField
              {...register('instructions')}
              label="Instructions"
              fullWidth
              multiline
              minRows={6}
              placeholder="Step instructions for the agent... Use {{artifact_name}} for variable references."
              InputProps={{ sx: { fontFamily: '"JetBrains Mono", monospace', fontSize: '0.85rem' } }}
            />

            <Stack direction="row" spacing={2}>
              <Controller
                name="skipPolicy"
                control={control}
                render={({ field }) => (
                  <TextField {...field} select label="Skip Policy" sx={{ minWidth: 180 }}>
                    <MenuItem value="never">Never</MenuItem>
                    <MenuItem value="if_outputs_exist">If outputs exist</MenuItem>
                    <MenuItem value="manual">Manual</MenuItem>
                  </TextField>
                )}
              />

              <Controller
                name="onFailure"
                control={control}
                render={({ field }) => (
                  <TextField {...field} select label="On Failure" sx={{ minWidth: 150 }}>
                    <MenuItem value="fail">Fail</MenuItem>
                    <MenuItem value="retry">Retry</MenuItem>
                    <MenuItem value="skip">Skip</MenuItem>
                  </TextField>
                )}
              />

              <TextField
                {...register('maxRetries', { valueAsNumber: true })}
                label="Max Retries"
                type="number"
                sx={{ width: 120 }}
                inputProps={{ min: 0, max: 10 }}
              />
            </Stack>

            {modelRuntime && (
              <Controller
                name="preferredModel"
                control={control}
                render={({ field }) => (
                  <Autocomplete
                    options={agentModels ?? []}
                    getOptionLabel={(option) => (typeof option === 'string' ? option : option.displayName)}
                    value={stepModel}
                    onChange={(_, newValue) => {
                      const model = newValue as AgentModel | null;
                      setStepModel(model);
                      field.onChange(model?.modelId ?? null);
                    }}
                    renderInput={(params) => (
                      <TextField {...params} label="Preferred Model (optional)" placeholder="Default (runtime selects)" />
                    )}
                    isOptionEqualToValue={(option, value) => option.modelId === value.modelId}
                  />
                )}
              />
            )}

            <Controller
              name="allowNonInteractive"
              control={control}
              render={({ field }) => (
                <FormControlLabel
                  control={<Switch checked={field.value} onChange={field.onChange} />}
                  label="Auto-run available (skip user approval in non-interactive/mixed modes)"
                />
              )}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={isLoading}>
            Cancel
          </Button>
          <Button type="submit" variant="contained" disabled={isLoading}>
            {isLoading ? 'Saving...' : isEditMode ? 'Save' : 'Add Step'}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export { AddStepDialog };
