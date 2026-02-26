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
            content: f.content || '',
            existingFileUrl: f.fileUrl || undefined,
            existingFileName: f.fileName || undefined,
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

  const buildFormData = (data: ToolFormData): FormData => {
    const formData = new FormData();
    formData.append('tool[name]', data.name);
    formData.append('tool[display_name]', data.displayName);
    if (data.description) formData.append('tool[description]', data.description);
    formData.append('tool[docker_image]', data.dockerImage);
    if (data.command) formData.append('tool[command]', data.command);

    data.requiredConfigItems?.forEach((item) => {
      formData.append('tool[required_config_items][]', item);
    });

    if (data.inputSchema && Object.keys(data.inputSchema).length > 0) {
      formData.append('tool[input_schema]', JSON.stringify(data.inputSchema));
    }

    data.toolFilesAttributes?.forEach((tf, i) => {
      const prefix = `tool[tool_files_attributes][${i}]`;
      if (tf.id) formData.append(`${prefix}[id]`, String(tf.id));
      formData.append(`${prefix}[path]`, tf.path);
      if (tf._destroy) {
        formData.append(`${prefix}[_destroy]`, '1');
      } else if (tf.file) {
        formData.append(`${prefix}[file]`, tf.file);
      } else if (tf.content) {
        formData.append(`${prefix}[content]`, tf.content);
      }
    });

    return formData;
  };

  const hasFileUploads = (data: ToolFormData): boolean => {
    return !!data.toolFilesAttributes?.some((tf) => tf.file instanceof File);
  };

  const toJsonPayload = (data: ToolFormData) => ({
    name: data.name,
    displayName: data.displayName,
    description: data.description,
    dockerImage: data.dockerImage,
    command: data.command,
    requiredConfigItems: data.requiredConfigItems,
    inputSchema: data.inputSchema,
    toolFilesAttributes: data.toolFilesAttributes?.map(({ id, path, content, _destroy }) => ({
      id,
      path,
      content: content || '',
      _destroy,
    })),
  });

  const onSubmit = async (data: ToolFormData) => {
    try {
      const useMultipart = hasFileUploads(data);

      if (isEditMode && editTool) {
        if (useMultipart) {
          const formData = buildFormData(data);
          if (projectId && editTool.scopeType === 'Project') {
            await updateProjectTool({ projectId, id: editTool.id, formData }).unwrap();
          } else {
            await updateCompanyTool({ id: editTool.id, formData }).unwrap();
          }
        } else {
          const payload = toJsonPayload(data);
          if (projectId && editTool.scopeType === 'Project') {
            await updateProjectTool({ projectId, id: editTool.id, ...payload }).unwrap();
          } else {
            await updateCompanyTool({ id: editTool.id, ...payload }).unwrap();
          }
        }
        enqueueSnackbar('Tool updated successfully', { variant: 'success' });
      } else {
        if (useMultipart) {
          const formData = buildFormData(data);
          if (projectId) {
            await createProjectTool({ projectId, formData }).unwrap();
          } else {
            await createCompanyTool({ formData }).unwrap();
          }
        } else {
          const payload = toJsonPayload(data);
          if (projectId) {
            await createProjectTool({ projectId, ...payload }).unwrap();
          } else {
            await createCompanyTool(payload).unwrap();
          }
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
