import { Button, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle } from '@mui/material';
import type { FC } from 'react';

import { useDeleteMcpServerMutation, useDeleteProjectMcpServerMutation, type McpServer } from 'entities/mcp-server';

interface DeleteMcpServerDialogProps {
  open: boolean;
  onClose: () => void;
  server: McpServer | null;
  projectId?: number;
}

export const DeleteMcpServerDialog: FC<DeleteMcpServerDialogProps> = ({ open, onClose, server, projectId }) => {
  const isProjectContext = !!projectId;

  const [deleteCompany, { isLoading: isDeletingCompany }] = useDeleteMcpServerMutation();
  const [deleteProject, { isLoading: isDeletingProject }] = useDeleteProjectMcpServerMutation();

  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!server) return;

    try {
      if (isProjectContext) {
        await deleteProject({ projectId: String(projectId), id: server.id }).unwrap();
      } else {
        await deleteCompany(server.id).unwrap();
      }
      onClose();
    } catch (error) {
      console.error('Failed to delete MCP server:', error);
    }
  };

  if (!server) return null;

  return (
    <Dialog open={open} onClose={onClose}>
      <DialogTitle>Delete MCP Server</DialogTitle>
      <DialogContent>
        <DialogContentText>
          Are you sure you want to delete <strong>{server.displayName}</strong>? This action cannot be undone.
        </DialogContentText>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button onClick={handleDelete} color="error" variant="contained" disabled={isLoading}>
          Delete
        </Button>
      </DialogActions>
    </Dialog>
  );
};
