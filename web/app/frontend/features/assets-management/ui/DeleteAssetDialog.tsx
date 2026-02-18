import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Typography,
  Box,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import type { FC } from 'react';

import { useDeleteCompanyAssetMutation, useDeleteProjectAssetMutation } from '../api/assetsApi';
import type { Asset } from '../lib/types';

interface DeleteAssetDialogProps {
  open: boolean;
  onClose: () => void;
  asset: Asset | null;
  projectId?: number;
}

const DeleteAssetDialog: FC<DeleteAssetDialogProps> = ({ open, onClose, asset, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [deleteCompanyAsset, { isLoading: isDeletingCompany }] = useDeleteCompanyAssetMutation();
  const [deleteProjectAsset, { isLoading: isDeletingProject }] = useDeleteProjectAssetMutation();
  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!asset) return;

    try {
      if (projectId && asset.scopeType === 'Project') {
        await deleteProjectAsset({ projectId, id: asset.id }).unwrap();
      } else {
        await deleteCompanyAsset(asset.id).unwrap();
      }
      enqueueSnackbar('Asset deleted successfully', { variant: 'success' });
      onClose();
    } catch {
      enqueueSnackbar('Failed to delete asset', { variant: 'error' });
    }
  };

  if (!asset) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Delete Asset</DialogTitle>
      <DialogContent>
        <DialogContentText>Are you sure you want to delete this asset?</DialogContentText>
        <Box sx={{ mt: 2, p: 1.5, backgroundColor: 'background.base', borderRadius: 1 }}>
          <Typography sx={{ fontWeight: 500 }}>{asset.name}</Typography>
          {asset.folder && (
            <Typography sx={{ fontSize: 12, color: 'text.secondary' }}>Folder: {asset.folder}</Typography>
          )}
          <Typography sx={{ fontSize: 12, color: 'text.secondary' }}>
            {asset.versionsCount} version{asset.versionsCount !== 1 ? 's' : ''}
          </Typography>
        </Box>
        {asset.versionsCount > 1 && (
          <DialogContentText sx={{ mt: 2, color: 'warning.main', fontSize: 13 }}>
            This asset has {asset.versionsCount} versions that will also be hidden.
          </DialogContentText>
        )}
        <DialogContentText sx={{ mt: 1.5, fontSize: 13, color: 'text.secondary' }}>
          The asset will be moved to trash. You can restore it within 30 days.
        </DialogContentText>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button onClick={handleDelete} color="error" variant="contained" disabled={isLoading}>
          {isLoading ? 'Deleting...' : 'Delete'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export { DeleteAssetDialog };
