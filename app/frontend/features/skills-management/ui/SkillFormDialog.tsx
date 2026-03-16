import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, Stack, TextField } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect } from 'react';
import { FormProvider, useForm, Controller } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import {
  useCreateCompanySkillMutation,
  useCreateProjectSkillMutation,
  useUpdateCompanySkillMutation,
  useUpdateProjectSkillMutation,
} from '../api/skillsApi';
import { skillSchema, type SkillFormData } from '../lib/skillSchema';
import type { Skill } from '../lib/types';

interface SkillFormDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
  editSkill?: Skill | null;
}

const SkillFormDialog: FC<SkillFormDialogProps> = ({ open, onClose, projectId, editSkill }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanySkill, { isLoading: isCreatingCompany }] = useCreateCompanySkillMutation();
  const [createProjectSkill, { isLoading: isCreatingProject }] = useCreateProjectSkillMutation();
  const [updateCompanySkill, { isLoading: isUpdatingCompany }] = useUpdateCompanySkillMutation();
  const [updateProjectSkill, { isLoading: isUpdatingProject }] = useUpdateProjectSkillMutation();

  const isLoading = isCreatingCompany || isCreatingProject || isUpdatingCompany || isUpdatingProject;
  const isEditMode = !!editSkill;

  const methods = useForm<SkillFormData>({
    resolver: zodResolver(skillSchema),
    defaultValues: {
      name: '',
      title: '',
      content: '',
      description: '',
    },
  });

  // Reset form when dialog opens/closes or editSkill changes
  useEffect(() => {
    if (open) {
      if (editSkill) {
        methods.reset({
          name: editSkill.name,
          title: editSkill.title || '',
          content: editSkill.content || '',
          description: editSkill.description || '',
        });
      } else {
        methods.reset({
          name: '',
          title: '',
          content: '',
          description: '',
        });
      }
    }
  }, [open, editSkill, methods]);

  const handleClose = () => {
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: SkillFormData) => {
    try {
      if (isEditMode && editSkill) {
        const updateData = {
          id: editSkill.id,
          ...data,
        };

        if (projectId && editSkill.scopeType === 'Project') {
          await updateProjectSkill({ projectId, ...updateData }).unwrap();
        } else {
          await updateCompanySkill(updateData).unwrap();
        }
        enqueueSnackbar('Skill updated successfully', { variant: 'success' });
      } else {
        if (projectId) {
          await createProjectSkill({ projectId, ...data }).unwrap();
        } else {
          await createCompanySkill(data).unwrap();
        }
        enqueueSnackbar('Skill created successfully', { variant: 'success' });
      }
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || `Failed to ${isEditMode ? 'update' : 'create'} skill`;
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>{isEditMode ? 'Edit Skill' : 'Create Skill'}</DialogTitle>
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(onSubmit)}>
          <DialogContent>
            <Stack spacing={3}>
              {/* Name */}
              <Controller
                name="name"
                control={methods.control}
                render={({ field, fieldState }) => (
                  <TextField
                    {...field}
                    onChange={(e) => field.onChange(e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, '_'))}
                    label="Name"
                    placeholder="my-skill"
                    fullWidth
                    error={!!fieldState.error}
                    helperText={fieldState.error?.message || 'Unique identifier (lowercase, underscores, hyphens)'}
                    autoFocus
                    disabled={isEditMode}
                    InputProps={{
                      sx: { fontFamily: '"JetBrains Mono", monospace' },
                    }}
                  />
                )}
              />

              {/* Title */}
              <TextField
                {...methods.register('title')}
                label="Title"
                placeholder="Coding Standards"
                fullWidth
                error={!!methods.formState.errors.title}
                helperText={methods.formState.errors.title?.message || 'Display name for the skill'}
              />

              {/* Content */}
              <TextField
                {...methods.register('content')}
                label="Content"
                placeholder="# Skill Instructions&#10;&#10;Write markdown instructions that will be injected into agent sessions..."
                fullWidth
                multiline
                minRows={10}
                error={!!methods.formState.errors.content}
                helperText={
                  methods.formState.errors.content?.message || 'Markdown instructions injected into agent containers'
                }
                InputProps={{
                  sx: { fontFamily: '"JetBrains Mono", monospace', fontSize: 13 },
                }}
              />

              {/* Description */}
              <TextField
                {...methods.register('description')}
                label="Description"
                placeholder="Brief description of what this skill does..."
                fullWidth
                multiline
                minRows={2}
                error={!!methods.formState.errors.description}
                helperText={methods.formState.errors.description?.message || 'Optional description (optional)'}
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

export { SkillFormDialog };
