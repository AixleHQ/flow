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

import { useDeleteCompanyToolMutation, useDeleteProjectToolMutation } from '../api/toolsApi';
import type { Tool } from '../lib/types';

interface DeleteToolDialogProps {
  open: boolean;
  onClose: () => void;
  tool: Tool | null;
  projectId?: number;
}

const DeleteToolDialog: FC<DeleteToolDialogProps> = ({ open, onClose, tool, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [deleteCompanyTool, { isLoading: isDeletingCompany }] = useDeleteCompanyToolMutation();
  const [deleteProjectTool, { isLoading: isDeletingProject }] = useDeleteProjectToolMutation();

  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!tool) return;

    try {
      if (projectId && tool.scopeType === 'Project') {
        await deleteProjectTool({ projectId, id: tool.id }).unwrap();
      } else {
        await deleteCompanyTool(tool.id).unwrap();
      }
      enqueueSnackbar('Tool deleted successfully', { variant: 'success' });
      onClose();
    } catch {
      enqueueSnackbar('Failed to delete tool', { variant: 'error' });
    }
  };

  if (!tool) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Delete Tool</DialogTitle>
      <DialogContent>
        <DialogContentText>Are you sure you want to delete this tool?</DialogContentText>
        <Box
          sx={{
            mt: 2,
            p: 1.5,
            backgroundColor: 'background.base',
            borderRadius: 1,
          }}
        >
          <Typography sx={{ fontWeight: 500 }}>{tool.displayName}</Typography>
          <Typography sx={{ fontSize: 12, fontFamily: '"JetBrains Mono", monospace', color: 'text.secondary' }}>
            {tool.name}
          </Typography>
        </Box>
        <DialogContentText sx={{ mt: 2, color: 'warning.main', fontSize: 13 }}>
          This action cannot be undone. Any workflows using this tool may be affected.
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

export { DeleteToolDialog };
