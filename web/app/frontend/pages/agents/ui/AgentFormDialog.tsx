import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, Stack, TextField } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect } from 'react';
import { FormProvider, useForm, Controller } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';
import { EmojiPicker } from 'shared/ui';

import {
  useCreateCompanyAgentMutation,
  useCreateProjectAgentMutation,
  useUpdateCompanyAgentMutation,
  useUpdateProjectAgentMutation,
} from '../api/agentsApi';
import { agentSchema, type AgentFormData } from '../lib/agentSchema';
import type { Agent } from '../lib/types';

interface AgentFormDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
  editAgent?: Agent | null;
}

const AgentFormDialog: FC<AgentFormDialogProps> = ({ open, onClose, projectId, editAgent }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanyAgent, { isLoading: isCreatingCompany }] = useCreateCompanyAgentMutation();
  const [createProjectAgent, { isLoading: isCreatingProject }] = useCreateProjectAgentMutation();
  const [updateCompanyAgent, { isLoading: isUpdatingCompany }] = useUpdateCompanyAgentMutation();
  const [updateProjectAgent, { isLoading: isUpdatingProject }] = useUpdateProjectAgentMutation();

  const isLoading = isCreatingCompany || isCreatingProject || isUpdatingCompany || isUpdatingProject;
  const isEditMode = !!editAgent;

  const methods = useForm<AgentFormData>({
    resolver: zodResolver(agentSchema),
    defaultValues: {
      name: '',
      title: '',
      icon: '',
      persona: '',
      communicationStyle: '',
      principles: '',
    },
  });

  // Reset form when dialog opens/closes or editAgent changes
  useEffect(() => {
    if (open) {
      if (editAgent) {
        methods.reset({
          name: editAgent.name,
          title: editAgent.title,
          icon: editAgent.icon || '',
          persona: editAgent.persona,
          communicationStyle: editAgent.communicationStyle || '',
          principles: editAgent.principles || '',
        });
      } else {
        methods.reset({
          name: '',
          title: '',
          icon: '',
          persona: '',
          communicationStyle: '',
          principles: '',
        });
      }
    }
  }, [open, editAgent, methods]);

  const handleClose = () => {
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: AgentFormData) => {
    try {
      if (isEditMode && editAgent) {
        const updateData = {
          id: editAgent.id,
          ...data,
        };

        if (projectId && editAgent.scopeType === 'Project') {
          await updateProjectAgent({ projectId, ...updateData }).unwrap();
        } else {
          await updateCompanyAgent(updateData).unwrap();
        }
        enqueueSnackbar('Agent updated successfully', { variant: 'success' });
      } else {
        if (projectId) {
          await createProjectAgent({ projectId, ...data }).unwrap();
        } else {
          await createCompanyAgent(data).unwrap();
        }
        enqueueSnackbar('Agent created successfully', { variant: 'success' });
      }
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || `Failed to ${isEditMode ? 'update' : 'create'} agent`;
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>{isEditMode ? 'Edit Agent' : 'Create Agent'}</DialogTitle>
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(onSubmit)}>
          <DialogContent>
            <Stack spacing={3}>
              {/* Name and Icon row */}
              <Stack direction="row" spacing={2} alignItems="flex-start">
                <Controller
                  name="name"
                  control={methods.control}
                  render={({ field, fieldState }) => (
                    <TextField
                      {...field}
                      onChange={(e) => field.onChange(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_'))}
                      label="Name"
                      placeholder="my_agent"
                      fullWidth
                      error={!!fieldState.error}
                      helperText={fieldState.error?.message || 'Unique identifier (lowercase, underscores)'}
                      autoFocus
                      disabled={isEditMode}
                      InputProps={{
                        sx: { fontFamily: '"JetBrains Mono", monospace' },
                      }}
                    />
                  )}
                />
                <Controller
                  name="icon"
                  control={methods.control}
                  render={({ field }) => (
                    <EmojiPicker value={field.value || ''} onChange={field.onChange} disabled={isLoading} />
                  )}
                />
              </Stack>

              {/* Title */}
              <TextField
                {...methods.register('title')}
                label="Title"
                placeholder="Business Analyst"
                fullWidth
                error={!!methods.formState.errors.title}
                helperText={methods.formState.errors.title?.message || 'Display name for the agent'}
              />

              {/* Persona */}
              <TextField
                {...methods.register('persona')}
                label="Persona"
                placeholder="Senior analyst with deep expertise in market research..."
                fullWidth
                multiline
                rows={4}
                error={!!methods.formState.errors.persona}
                helperText={methods.formState.errors.persona?.message || 'Who the agent is, their role and identity'}
              />

              {/* Communication Style */}
              <TextField
                {...methods.register('communicationStyle')}
                label="Communication Style"
                placeholder="Speaks with precision and clarity..."
                fullWidth
                multiline
                rows={2}
                error={!!methods.formState.errors.communicationStyle}
                helperText={
                  methods.formState.errors.communicationStyle?.message || 'How the agent communicates (optional)'
                }
              />

              {/* Principles */}
              <TextField
                {...methods.register('principles')}
                label="Principles"
                placeholder="Ground findings in verifiable evidence..."
                fullWidth
                multiline
                rows={2}
                error={!!methods.formState.errors.principles}
                helperText={methods.formState.errors.principles?.message || 'Operating principles (optional)'}
              />
            </Stack>
          </DialogContent>
          <DialogActions>
            <Button onClick={handleClose} disabled={isLoading}>
              Cancel
            </Button>
            <Button type="submit" variant="contained" disabled={isLoading}>
              {isLoading ? (isEditMode ? 'Saving...' : 'Creating...') : isEditMode ? 'Save' : 'Create'}
            </Button>
          </DialogActions>
        </form>
      </FormProvider>
    </Dialog>
  );
};

export { AgentFormDialog };
