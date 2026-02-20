import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import type { FC } from 'react';

import { useDeleteCompanyConfigItemMutation, useDeleteProjectConfigItemMutation } from '../api/configItemsApi';
import type { ConfigItem } from '../lib/types';

interface DeleteConfigItemDialogProps {
  open: boolean;
  onClose: () => void;
  item: ConfigItem | null;
  projectId?: number;
}

const DeleteConfigItemDialog: FC<DeleteConfigItemDialogProps> = ({ open, onClose, item, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [deleteCompanyItem, { isLoading: isDeletingCompany }] = useDeleteCompanyConfigItemMutation();
  const [deleteProjectItem, { isLoading: isDeletingProject }] = useDeleteProjectConfigItemMutation();

  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!item) return;

    try {
      if (projectId && item.scopeType === 'Project') {
        await deleteProjectItem({ projectId, id: item.id }).unwrap();
      } else {
        await deleteCompanyItem(item.id).unwrap();
      }
      enqueueSnackbar('Config item deleted successfully', { variant: 'success' });
      onClose();
    } catch {
      enqueueSnackbar('Failed to delete config item', { variant: 'error' });
    }
  };

  if (!item) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Delete Config Item</DialogTitle>
      <DialogContent>
        <DialogContentText>Are you sure you want to delete this config item?</DialogContentText>
        <Typography
          sx={{
            mt: 2,
            p: 1.5,
            backgroundColor: 'background.base',
            borderRadius: 1,
            fontFamily: '"JetBrains Mono", monospace',
            fontWeight: 500,
          }}
        >
          {item.name}
        </Typography>
        <DialogContentText sx={{ mt: 2, color: 'warning.main', fontSize: 13 }}>
          This action cannot be undone. Any workflows or services using this config item may stop working.
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

export { DeleteConfigItemDialog };
