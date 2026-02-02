import { zodResolver } from '@hookform/resolvers/zod';
import Visibility from '@mui/icons-material/Visibility';
import VisibilityOff from '@mui/icons-material/VisibilityOff';
import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  FormHelperText,
  IconButton,
  InputAdornment,
  Stack,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { useState, type FC, useEffect } from 'react';
import { FormProvider, useForm, Controller } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import {
  useCreateCompanyConfigItemMutation,
  useCreateProjectConfigItemMutation,
  useUpdateCompanyConfigItemMutation,
  useUpdateProjectConfigItemMutation,
} from '../api/configItemsApi';
import { configItemSchema, type ConfigItemFormData } from '../lib/configItemSchema';
import type { ConfigItem, ConfigItemType } from '../lib/types';

interface ConfigItemFormDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number; // If provided, will create/update project-level items
  editItem?: ConfigItem | null; // If provided, dialog is in edit mode
}

const ConfigItemFormDialog: FC<ConfigItemFormDialogProps> = ({ open, onClose, projectId, editItem }) => {
  const [showValue, setShowValue] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanyItem, { isLoading: isCreatingCompany }] = useCreateCompanyConfigItemMutation();
  const [createProjectItem, { isLoading: isCreatingProject }] = useCreateProjectConfigItemMutation();
  const [updateCompanyItem, { isLoading: isUpdatingCompany }] = useUpdateCompanyConfigItemMutation();
  const [updateProjectItem, { isLoading: isUpdatingProject }] = useUpdateProjectConfigItemMutation();

  const isLoading = isCreatingCompany || isCreatingProject || isUpdatingCompany || isUpdatingProject;
  const isEditMode = !!editItem;

  const methods = useForm<ConfigItemFormData>({
    resolver: zodResolver(configItemSchema),
    defaultValues: {
      name: '',
      value: '',
      description: '',
      itemType: 'variable',
    },
  });

  const itemType = methods.watch('itemType');

  // Reset form when dialog opens/closes or editItem changes
  useEffect(() => {
    if (open) {
      if (editItem) {
        methods.reset({
          name: editItem.name,
          value: editItem.valueEditable ? '' : '', // Don't show masked value for secrets
          description: editItem.description || '',
          itemType: editItem.itemType,
        });
      } else {
        methods.reset({
          name: '',
          value: '',
          description: '',
          itemType: 'variable',
        });
      }
      setShowValue(false);
    }
  }, [open, editItem, methods]);

  const handleClose = () => {
    methods.reset();
    setShowValue(false);
    onClose();
  };

  const onSubmit = async (data: ConfigItemFormData) => {
    try {
      if (isEditMode && editItem) {
        // Update existing item
        const updateData = {
          id: editItem.id,
          name: data.name,
          description: data.description,
          ...(data.value && { value: data.value }), // Only include value if changed
        };

        if (projectId && editItem.scopeType === 'Project') {
          await updateProjectItem({ projectId, ...updateData }).unwrap();
        } else {
          await updateCompanyItem(updateData).unwrap();
        }
        enqueueSnackbar('Config item updated successfully', { variant: 'success' });
      } else {
        // Create new item
        if (projectId) {
          await createProjectItem({ projectId, ...data }).unwrap();
        } else {
          await createCompanyItem(data).unwrap();
        }
        enqueueSnackbar('Config item created successfully', { variant: 'success' });
      }
      handleClose();
    } catch (error: unknown) {
      const message =
        setErrorsToForm(error, methods.setError) || `Failed to ${isEditMode ? 'update' : 'create'} config item`;
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  const handleTypeChange = (_: React.MouseEvent<HTMLElement>, newType: ConfigItemType | null) => {
    if (newType) {
      methods.setValue('itemType', newType);
      // Clear value when switching to secret in edit mode
      if (newType === 'secret' && isEditMode) {
        methods.setValue('value', '');
      }
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>{isEditMode ? 'Edit Config Item' : 'Create Config Item'}</DialogTitle>
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(onSubmit)}>
          <DialogContent>
            <Stack spacing={3}>
              {/* Type Toggle (only for create mode) */}
              {!isEditMode && (
                <FormControl>
                  <Typography sx={{ mb: 1, fontSize: 14, fontWeight: 500 }}>Type</Typography>
                  <Controller
                    name="itemType"
                    control={methods.control}
                    render={({ field }) => (
                      <ToggleButtonGroup
                        value={field.value}
                        exclusive
                        onChange={handleTypeChange}
                        fullWidth
                        size="small"
                      >
                        <ToggleButton value="variable" sx={{ textTransform: 'none' }}>
                          Variable
                        </ToggleButton>
                        <ToggleButton value="secret" sx={{ textTransform: 'none' }}>
                          Secret
                        </ToggleButton>
                      </ToggleButtonGroup>
                    )}
                  />
                  <FormHelperText>
                    {itemType === 'secret'
                      ? 'Secrets are encrypted and masked in the UI'
                      : 'Variables are stored as plain text'}
                  </FormHelperText>
                </FormControl>
              )}

              {/* Name field */}
              <Controller
                name="name"
                control={methods.control}
                render={({ field, fieldState }) => (
                  <TextField
                    {...field}
                    onChange={(e) => field.onChange(e.target.value.toUpperCase())}
                    label="Name"
                    placeholder="MY_CONFIG_VARIABLE"
                    fullWidth
                    error={!!fieldState.error}
                    helperText={
                      fieldState.error?.message ||
                      'Use uppercase letters, numbers, and underscores (e.g., API_KEY, DATABASE_URL)'
                    }
                    autoFocus
                    disabled={isEditMode}
                    InputProps={{
                      sx: { fontFamily: '"JetBrains Mono", monospace' },
                    }}
                  />
                )}
              />

              {/* Value field */}
              <TextField
                {...methods.register('value')}
                label={isEditMode && itemType === 'secret' ? 'New Value (leave empty to keep current)' : 'Value'}
                placeholder={itemType === 'secret' ? 'Enter secret value' : 'Enter value'}
                fullWidth
                type={itemType === 'secret' && !showValue ? 'password' : 'text'}
                error={!!methods.formState.errors.value}
                helperText={methods.formState.errors.value?.message}
                required={!isEditMode || itemType === 'variable'}
                InputProps={{
                  sx: { fontFamily: '"JetBrains Mono", monospace' },
                  endAdornment: itemType === 'secret' && (
                    <InputAdornment position="end">
                      <IconButton onClick={() => setShowValue(!showValue)} edge="end" size="small">
                        {showValue ? <VisibilityOff /> : <Visibility />}
                      </IconButton>
                    </InputAdornment>
                  ),
                }}
              />

              {/* Description field */}
              <TextField
                {...methods.register('description')}
                label="Description"
                placeholder="Optional description for this config item"
                fullWidth
                multiline
                rows={2}
                error={!!methods.formState.errors.description}
                helperText={methods.formState.errors.description?.message}
              />

              {/* Scope info for project context */}
              {projectId && !isEditMode && (
                <Typography sx={{ fontSize: 12, color: 'text.secondary' }}>
                  This config item will be created at the project level and will override any company-level item with
                  the same name.
                </Typography>
              )}
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

export { ConfigItemFormDialog };
