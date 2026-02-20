import { zodResolver } from '@hookform/resolvers/zod';
import {
  Autocomplete,
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  Tab,
  Tabs,
  TextField,
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect, useState, useMemo } from 'react';
import { FormProvider, useForm, Controller } from 'react-hook-form';

import {
  setErrorsToForm,
  useGetCompanyConfigItemsForSelectQuery,
  useGetProjectConfigItemsForSelectQuery,
} from 'shared/api';

import {
  useCreateCompanyToolMutation,
  useCreateProjectToolMutation,
  useUpdateCompanyToolMutation,
  useUpdateProjectToolMutation,
} from '../api/toolsApi';
import { toolSchema, type ToolFormData } from '../lib/toolSchema';
import type { Tool } from '../lib/types';

import { ToolFilesEditor } from './ToolFilesEditor';

interface ToolFormDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
  editTool?: Tool | null;
}

const ToolFormDialog: FC<ToolFormDialogProps> = ({ open, onClose, projectId, editTool }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [activeTab, setActiveTab] = useState(0);

  const [createCompanyTool, { isLoading: isCreatingCompany }] = useCreateCompanyToolMutation();
  const [createProjectTool, { isLoading: isCreatingProject }] = useCreateProjectToolMutation();
  const [updateCompanyTool, { isLoading: isUpdatingCompany }] = useUpdateCompanyToolMutation();
  const [updateProjectTool, { isLoading: isUpdatingProject }] = useUpdateProjectToolMutation();

  // Fetch config items for multiselect
  const { data: companyConfigItems } = useGetCompanyConfigItemsForSelectQuery(undefined, { skip: !!projectId });
  const { data: projectConfigItems } = useGetProjectConfigItemsForSelectQuery(projectId!, { skip: !projectId });

  const availableConfigItems = useMemo(() => {
    const items = projectId ? projectConfigItems : companyConfigItems;
    if (!items) return [];
    return items.map((item) => item.name);
  }, [projectId, companyConfigItems, projectConfigItems]);

  const isLoading = isCreatingCompany || isCreatingProject || isUpdatingCompany || isUpdatingProject;
  const isEditMode = !!editTool;

  const methods = useForm<ToolFormData>({
    resolver: zodResolver(toolSchema),
    defaultValues: {
      name: '',
      displayName: '',
      description: '',
      dockerImage: '',
      command: '',
      requiredConfigItems: [],
      inputSchema: {},
      toolFilesAttributes: [],
    },
  });

  useEffect(() => {
    if (open) {
      setActiveTab(0);
      if (editTool) {
        methods.reset({
          name: editTool.name,
          displayName: editTool.displayName,
          description: editTool.description || '',
          dockerImage: editTool.dockerImage || '',
          command: editTool.command || '',
          requiredConfigItems: editTool.requiredConfigItems || [],
          inputSchema: editTool.inputSchema || {},
          toolFilesAttributes: editTool.toolFiles.map((f) => ({
            id: f.id,
            path: f.path,
            content: f.content,
          })),
        });
      } else {
        methods.reset({
          name: '',
          displayName: '',
          description: '',
          dockerImage: '',
          command: '',
          requiredConfigItems: [],
          inputSchema: {},
          toolFilesAttributes: [],
        });
      }
    }
  }, [open, editTool, methods]);

  const handleClose = () => {
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: ToolFormData) => {
    try {
      if (isEditMode && editTool) {
        const updateData = {
          id: editTool.id,
          ...data,
        };

        if (projectId && editTool.scopeType === 'Project') {
          await updateProjectTool({ projectId, ...updateData }).unwrap();
        } else {
          await updateCompanyTool(updateData).unwrap();
        }
        enqueueSnackbar('Tool updated successfully', { variant: 'success' });
      } else {
        if (projectId) {
          await createProjectTool({ projectId, ...data }).unwrap();
        } else {
          await createCompanyTool(data).unwrap();
        }
        enqueueSnackbar('Tool created successfully', { variant: 'success' });
      }
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || `Failed to ${isEditMode ? 'update' : 'create'} tool`;
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>{isEditMode ? 'Edit Tool' : 'Create Tool'}</DialogTitle>
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(onSubmit)}>
          <DialogContent>
            <Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)} sx={{ mb: 2 }}>
              <Tab label="Basic Info" />
              <Tab label="Files" />
              <Tab label="Config Items" />
            </Tabs>

            {activeTab === 0 && (
              <Stack spacing={3}>
                <Controller
                  name="name"
                  control={methods.control}
                  render={({ field, fieldState }) => (
                    <TextField
                      {...field}
                      onChange={(e) => field.onChange(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_'))}
                      label="Name"
                      placeholder="my_tool"
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

                <TextField
                  {...methods.register('displayName')}
                  label="Display Name"
                  placeholder="My Custom Tool"
                  fullWidth
                  error={!!methods.formState.errors.displayName}
                  helperText={methods.formState.errors.displayName?.message || 'Human-readable name'}
                />

                <TextField
                  {...methods.register('description')}
                  label="Description"
                  placeholder="What this tool does..."
                  fullWidth
                  multiline
                  rows={2}
                  error={!!methods.formState.errors.description}
                  helperText={methods.formState.errors.description?.message}
                />

                <TextField
                  {...methods.register('dockerImage')}
                  label="Docker Image"
                  placeholder="python:3.11-slim"
                  fullWidth
                  error={!!methods.formState.errors.dockerImage}
                  helperText={methods.formState.errors.dockerImage?.message || 'Docker image to run'}
                  InputProps={{
                    sx: { fontFamily: '"JetBrains Mono", monospace' },
                  }}
                />

                <TextField
                  {...methods.register('command')}
                  label="Command"
                  placeholder="python /app/script.py --query {{query}}"
                  fullWidth
                  multiline
                  rows={2}
                  error={!!methods.formState.errors.command}
                  helperText={
                    methods.formState.errors.command?.message || 'Command template with {{param}} placeholders'
                  }
                  InputProps={{
                    sx: { fontFamily: '"JetBrains Mono", monospace' },
                  }}
                />
              </Stack>
            )}

            {activeTab === 1 && <ToolFilesEditor />}

            {activeTab === 2 && (
              <Box sx={{ p: 2, backgroundColor: 'background.base', borderRadius: 1 }}>
                <Typography variant="subtitle2" sx={{ color: 'text.secondary', mb: 2 }}>
                  Select config items to inject as environment variables
                </Typography>
                <Controller
                  name="requiredConfigItems"
                  control={methods.control}
                  render={({ field }) => (
                    <Autocomplete
                      multiple
                      options={availableConfigItems}
                      value={field.value || []}
                      onChange={(_, newValue) => field.onChange(newValue)}
                      renderTags={(value, getTagProps) =>
                        value.map((option, index) => (
                          <Chip
                            {...getTagProps({ index })}
                            key={option}
                            label={option}
                            size="small"
                            sx={{ fontFamily: '"JetBrains Mono", monospace' }}
                          />
                        ))
                      }
                      renderInput={(params) => (
                        <TextField
                          {...params}
                          label="Required Config Items"
                          placeholder={field.value?.length ? '' : 'Select config items...'}
                          helperText="These will be injected as environment variables into the container"
                        />
                      )}
                    />
                  )}
                />
              </Box>
            )}
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

export { ToolFormDialog };
