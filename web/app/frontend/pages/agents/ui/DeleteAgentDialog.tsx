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

import { useDeleteCompanyAgentMutation, useDeleteProjectAgentMutation } from '../api/agentsApi';
import type { Agent } from '../lib/types';

interface DeleteAgentDialogProps {
  open: boolean;
  onClose: () => void;
  agent: Agent | null;
  projectId?: number;
}

const DeleteAgentDialog: FC<DeleteAgentDialogProps> = ({ open, onClose, agent, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [deleteCompanyAgent, { isLoading: isDeletingCompany }] = useDeleteCompanyAgentMutation();
  const [deleteProjectAgent, { isLoading: isDeletingProject }] = useDeleteProjectAgentMutation();

  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!agent) return;

    try {
      if (projectId && agent.scopeType === 'Project') {
        await deleteProjectAgent({ projectId, id: agent.id }).unwrap();
      } else {
        await deleteCompanyAgent(agent.id).unwrap();
      }
      enqueueSnackbar('Agent deleted successfully', { variant: 'success' });
      onClose();
    } catch {
      enqueueSnackbar('Failed to delete agent', { variant: 'error' });
    }
  };

  if (!agent) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Delete Agent</DialogTitle>
      <DialogContent>
        <DialogContentText>Are you sure you want to delete this agent?</DialogContentText>
        <Box
          sx={{
            mt: 2,
            p: 1.5,
            backgroundColor: 'background.base',
            borderRadius: 1,
            display: 'flex',
            alignItems: 'center',
            gap: 1.5,
          }}
        >
          <Typography sx={{ fontSize: 24 }}>{agent.icon || '🤖'}</Typography>
          <Box>
            <Typography sx={{ fontWeight: 500 }}>{agent.title}</Typography>
            <Typography sx={{ fontSize: 12, fontFamily: '"JetBrains Mono", monospace', color: 'text.secondary' }}>
              {agent.name}
            </Typography>
          </Box>
        </Box>
        <DialogContentText sx={{ mt: 2, color: 'warning.main', fontSize: 13 }}>
          This action cannot be undone. Any sessions or workflows using this agent may be affected.
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

export { DeleteAgentDialog };
