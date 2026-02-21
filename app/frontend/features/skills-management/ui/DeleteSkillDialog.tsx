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

import { useDeleteCompanySkillMutation, useDeleteProjectSkillMutation } from '../api/skillsApi';
import type { Skill } from '../lib/types';

interface DeleteSkillDialogProps {
  open: boolean;
  onClose: () => void;
  skill: Skill | null;
  projectId?: number;
}

const DeleteSkillDialog: FC<DeleteSkillDialogProps> = ({ open, onClose, skill, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();
  const [deleteCompanySkill, { isLoading: isDeletingCompany }] = useDeleteCompanySkillMutation();
  const [deleteProjectSkill, { isLoading: isDeletingProject }] = useDeleteProjectSkillMutation();

  const isLoading = isDeletingCompany || isDeletingProject;

  const handleDelete = async () => {
    if (!skill) return;

    try {
      if (projectId && skill.scopeType === 'Project') {
        await deleteProjectSkill({ projectId, id: skill.id }).unwrap();
      } else {
        await deleteCompanySkill(skill.id).unwrap();
      }
      enqueueSnackbar('Skill deleted successfully', { variant: 'success' });
      onClose();
    } catch {
      enqueueSnackbar('Failed to delete skill', { variant: 'error' });
    }
  };

  if (!skill) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Delete Skill</DialogTitle>
      <DialogContent>
        <DialogContentText>Are you sure you want to delete this skill?</DialogContentText>
        <Box
          sx={{
            mt: 2,
            p: 1.5,
            backgroundColor: 'background.base',
            borderRadius: 1,
          }}
        >
          <Typography sx={{ fontWeight: 500 }}>{skill.title || skill.name}</Typography>
          <Typography sx={{ fontSize: 12, fontFamily: '"JetBrains Mono", monospace', color: 'text.secondary' }}>
            {skill.name}
          </Typography>
        </Box>
        <DialogContentText sx={{ mt: 2, color: 'warning.main', fontSize: 13 }}>
          This action cannot be undone. Any sessions using this skill may be affected.
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

export { DeleteSkillDialog };
