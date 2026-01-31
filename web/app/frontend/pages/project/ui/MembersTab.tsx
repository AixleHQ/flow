import {
  Avatar,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  List,
  ListItem,
  ListItemAvatar,
  ListItemSecondaryAction,
  ListItemText,
  MenuItem,
  TextField,
  Typography,
  Alert,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';

import {
  useGetProjectCollaboratorsQuery,
  useAddCollaboratorMutation,
  useRemoveCollaboratorMutation,
  useGetCompanyUsersForProjectQuery,
  type ProjectMember,
} from '../api/collaboratorsApi';

const styles = {
  root: {
    maxWidth: '800px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '24px',
  },
  title: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
  },
  list: {
    backgroundColor: 'background.paper',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
  },
  listItem: {
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': {
      borderBottom: 'none',
    },
  },
  avatar: {
    backgroundColor: 'primary.main',
  },
  ownerChip: {
    marginLeft: '8px',
  },
  dialogContent: {
    minWidth: '400px',
    paddingTop: '16px',
  },
  userSelect: {
    marginTop: '8px',
  },
} satisfies Record<string, SxProps<Theme>>;

interface MembersTabProps {
  projectId: number;
  ownerId: number;
}

const MembersTab = ({ projectId, ownerId: ownerIdProp }: MembersTabProps) => {
  const { data: currentUser } = useGetCurrentUserQuery();
  const { data: membersData, isLoading } = useGetProjectCollaboratorsQuery(projectId);
  const { data: companyUsersData } = useGetCompanyUsersForProjectQuery();
  const [addCollaborator] = useAddCollaboratorMutation();
  const [removeCollaborator] = useRemoveCollaboratorMutation();

  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | ''>('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const members = membersData?.items ?? [];
  // Owner is first in the list (from API), fallback to prop
  const ownerId = members[0]?.id ?? ownerIdProp;
  const isOwner = currentUser?.id === ownerId;

  // Filter out users who are already members
  const existingUserIds = new Set(members.map((m) => m.id));
  const availableUsers = (companyUsersData?.items ?? []).filter((u) => !existingUserIds.has(u.id));

  const handleAddCollaborator = async () => {
    if (!selectedUserId) return;

    setIsSubmitting(true);
    setError(null);

    try {
      await addCollaborator({ projectId, userId: selectedUserId as number }).unwrap();
      setIsAddDialogOpen(false);
      setSelectedUserId('');
    } catch (err: unknown) {
      const apiError = err as { data?: { errors?: Record<string, string[]> } };
      if (apiError.data?.errors) {
        const firstError = Object.values(apiError.data.errors)[0];
        setError(firstError?.[0] || 'Failed to add collaborator');
      } else {
        setError('Failed to add collaborator');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRemoveCollaborator = async (userId: number) => {
    if (!confirm('Are you sure you want to remove this collaborator?')) return;

    try {
      await removeCollaborator({ projectId, userId }).unwrap();
    } catch {
      alert('Failed to remove collaborator');
    }
  };

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map((n) => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  if (isLoading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Project Members ({members.length})</Typography>
        {isOwner && (
          <Button variant="contained" onClick={() => setIsAddDialogOpen(true)}>
            Add Collaborator
          </Button>
        )}
      </Box>

      <List sx={styles.list}>
        {members.map((member: ProjectMember) => {
          const isMemberOwner = member.id === ownerId;
          return (
            <ListItem key={member.id} sx={styles.listItem}>
              <ListItemAvatar>
                <Avatar sx={styles.avatar}>{getInitials(member.name || member.email)}</Avatar>
              </ListItemAvatar>
              <ListItemText
                primary={
                  <Box sx={{ display: 'flex', alignItems: 'center' }}>
                    {member.name || member.email}
                    {isMemberOwner && <Chip label="Owner" size="small" color="primary" sx={styles.ownerChip} />}
                  </Box>
                }
                secondary={member.email}
              />
              {isOwner && !isMemberOwner && (
                <ListItemSecondaryAction>
                  <IconButton
                    edge="end"
                    onClick={() => handleRemoveCollaborator(member.id)}
                    title="Remove collaborator"
                  >
                    <span style={{ fontSize: '16px' }}>✕</span>
                  </IconButton>
                </ListItemSecondaryAction>
              )}
            </ListItem>
          );
        })}
      </List>

      {/* Add Collaborator Dialog */}
      <Dialog open={isAddDialogOpen} onClose={() => setIsAddDialogOpen(false)}>
        <DialogTitle>Add Collaborator</DialogTitle>
        <DialogContent sx={styles.dialogContent}>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
              {error}
            </Alert>
          )}
          <TextField
            select
            fullWidth
            label="Select User"
            value={selectedUserId}
            onChange={(e) => setSelectedUserId(Number(e.target.value))}
            sx={styles.userSelect}
            disabled={isSubmitting}
          >
            {availableUsers.length === 0 ? (
              <MenuItem disabled>No users available</MenuItem>
            ) : (
              availableUsers.map((user) => (
                <MenuItem key={user.id} value={user.id}>
                  {user.name || user.email} ({user.email})
                </MenuItem>
              ))
            )}
          </TextField>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setIsAddDialogOpen(false)} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button variant="contained" onClick={handleAddCollaborator} disabled={!selectedUserId || isSubmitting}>
            {isSubmitting ? <CircularProgress size={20} /> : 'Add'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default MembersTab;
