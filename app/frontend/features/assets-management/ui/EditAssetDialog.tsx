import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, MenuItem, Stack, TextField } from '@mui/material';
import { useSnackbar } from 'notistack';
import { type FC, useEffect } from 'react';
import { Controller, useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import { useUpdateCompanyAssetMutation, useUpdateProjectAssetMutation } from '../api/assetsApi';
import { editAssetSchema, type EditAssetFormData } from '../lib/assetSchema';
import type { Asset } from '../lib/types';

interface EditAssetDialogProps {
  open: boolean;
  onClose: () => void;
  asset: Asset | null;
  projectId?: number;
}

const EditAssetDialog: FC<EditAssetDialogProps> = ({ open, onClose, asset, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [updateCompanyAsset, { isLoading: isUpdatingCompany }] = useUpdateCompanyAssetMutation();
  const [updateProjectAsset, { isLoading: isUpdatingProject }] = useUpdateProjectAssetMutation();
  const isLoading = isUpdatingCompany || isUpdatingProject;

  const methods = useForm<EditAssetFormData>({
    resolver: zodResolver(editAssetSchema),
    defaultValues: { folder: '', tags: '', public: false },
  });

  useEffect(() => {
    if (open && asset) {
      methods.reset({
        folder: asset.folder || '',
        tags: asset.tags?.join(', ') || '',
        public: asset.public,
      });
    }
  }, [open, asset, methods]);

  const handleClose = () => {
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: EditAssetFormData) => {
    if (!asset) return;

    const tags = data.tags
      ? data.tags
          .split(',')
          .map((t) => t.trim())
          .filter(Boolean)
      : [];

    const updateData = {
      id: asset.id,
      folder: data.folder || null,
      tags,
      public: data.public,
    };

    try {
      if (projectId && asset.scopeType === 'Project') {
        await updateProjectAsset({ projectId, ...updateData }).unwrap();
      } else {
        await updateCompanyAsset(updateData).unwrap();
      }
      enqueueSnackbar('Asset updated successfully', { variant: 'success' });
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || 'Failed to update asset';
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  if (!asset) return null;

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Edit Asset: {asset.name}</DialogTitle>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
            <TextField
              {...methods.register('folder')}
              label="Folder"
              placeholder="e.g. reports, images"
              fullWidth
              error={!!methods.formState.errors.folder}
              helperText={methods.formState.errors.folder?.message || 'Lowercase, hyphens, underscores'}
            />

            <TextField
              {...methods.register('tags')}
              label="Tags"
              placeholder="e.g. report, weekly, q1"
              fullWidth
              helperText="Comma-separated tags"
            />

            <Controller
              name="public"
              control={methods.control}
              render={({ field }) => (
                <TextField
                  select
                  label="Visibility"
                  fullWidth
                  value={field.value ? 'public' : 'private'}
                  onChange={(e) => field.onChange(e.target.value === 'public')}
                >
                  <MenuItem value="private">Private</MenuItem>
                  <MenuItem value="public">Public (shareable link)</MenuItem>
                </TextField>
              )}
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

export { EditAssetDialog };
