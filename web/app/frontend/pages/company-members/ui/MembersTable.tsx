import ArchiveIcon from '@mui/icons-material/Archive';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import DeleteIcon from '@mui/icons-material/Delete';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import {
  Box,
  Chip,
  Divider,
  IconButton,
  Menu,
  MenuItem,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TablePagination,
  Tooltip,
  Typography,
  SxProps,
} from '@mui/material';
import { format } from 'date-fns';
import { useSnackbar } from 'notistack';
import { useState, type FC, type MouseEvent } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';

import { useDeleteCompanyUserMutation, useUpdateCompanyUserMutation } from '../api/companyUsersApi';
import type { CompanyUser, UserRole, UserState } from '../lib/types';

interface MembersTableProps {
  users: CompanyUser[];
  page: number;
  perPage: number;
  totalCount: number;
  onPageChange: (page: number) => void;
  onPerPageChange: (perPage: number) => void;
}

// Soft color variants for badges
const roleStyles: Record<UserRole, SxProps> = {
  admin: {
    backgroundColor: 'rgba(59, 130, 246, 0.15)',
    color: '#60A5FA',
    border: '1px solid rgba(59, 130, 246, 0.3)',
  },
  employee: {
    backgroundColor: 'rgba(34, 197, 94, 0.15)',
    color: '#4ADE80',
    border: '1px solid rgba(34, 197, 94, 0.3)',
  },
};

const stateStyles: Record<UserState, SxProps> = {
  active: {
    backgroundColor: 'rgba(34, 197, 94, 0.15)',
    color: '#4ADE80',
    border: '1px solid rgba(34, 197, 94, 0.3)',
  },
  pending: {
    backgroundColor: 'rgba(245, 158, 11, 0.15)',
    color: '#FBBF24',
    border: '1px solid rgba(245, 158, 11, 0.3)',
  },
  archived: {
    backgroundColor: 'rgba(161, 161, 170, 0.15)',
    color: '#A1A1AA',
    border: '1px solid rgba(161, 161, 170, 0.3)',
  },
  suspended: {
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    color: '#F87171',
    border: '1px solid rgba(239, 68, 68, 0.3)',
  },
};

const styles = {
  tableContainer: {
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  tableHead: {
    backgroundColor: 'background.base',
  },
  tableHeadCell: {
    color: 'text.secondaryAlt',
    fontWeight: 600,
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  tableCell: {
    color: 'text.primaryAlt',
    fontSize: 14,
  },
  userInfo: {
    display: 'flex',
    flexDirection: 'column',
  },
  userName: {
    fontWeight: 500,
  },
  userEmail: {
    color: 'text.secondaryAlt',
    fontSize: 12,
  },
  invitedBy: {
    color: 'text.secondaryAlt',
    fontSize: 12,
  },
  chip: {
    fontSize: 11,
    height: 24,
    textTransform: 'capitalize',
  },
} satisfies Record<string, SxProps | object>;

const MembersTable: FC<MembersTableProps> = ({ users, page, perPage, totalCount, onPageChange, onPerPageChange }) => {
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const [selectedUser, setSelectedUser] = useState<CompanyUser | null>(null);
  const [updateUser] = useUpdateCompanyUserMutation();
  const [deleteUser] = useDeleteCompanyUserMutation();
  const { data: currentUser } = useGetCurrentUserQuery();
  const { enqueueSnackbar } = useSnackbar();

  const handleMenuOpen = (event: MouseEvent<HTMLElement>, user: CompanyUser) => {
    setAnchorEl(event.currentTarget);
    setSelectedUser(user);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
    setSelectedUser(null);
  };

  const handleStateChange = async (stateEvent: 'activate' | 'archive') => {
    if (!selectedUser) return;

    try {
      await updateUser({ id: selectedUser.id, stateEvent }).unwrap();
      enqueueSnackbar(`User ${stateEvent === 'activate' ? 'activated' : 'archived'} successfully`, {
        variant: 'success',
      });
    } catch {
      enqueueSnackbar(`Failed to ${stateEvent} user`, { variant: 'error' });
    }
    handleMenuClose();
  };

  const handleRoleChange = async (role: UserRole) => {
    if (!selectedUser) return;

    try {
      await updateUser({ id: selectedUser.id, role }).unwrap();
      enqueueSnackbar(`User role updated to ${role}`, { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update user role', { variant: 'error' });
    }
    handleMenuClose();
  };

  const handleDelete = async () => {
    if (!selectedUser) return;

    if (!window.confirm(`Are you sure you want to delete ${selectedUser.name}? This action cannot be undone.`)) {
      handleMenuClose();
      return;
    }

    try {
      await deleteUser(selectedUser.id).unwrap();
      enqueueSnackbar('User deleted successfully', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to delete user', { variant: 'error' });
    }
    handleMenuClose();
  };

  const canDeleteUser = selectedUser && currentUser && selectedUser.id !== currentUser.id;
  const canChangeRole = selectedUser && currentUser && selectedUser.id !== currentUser.id;

  // Check if the selected user is the last admin in the company
  const adminCount = users.filter((u) => u.role === 'admin').length;
  const isLastAdmin = selectedUser?.role === 'admin' && adminCount <= 1;

  return (
    <Box>
      <TableContainer sx={styles.tableContainer}>
        <Table>
          <TableHead sx={styles.tableHead}>
            <TableRow>
              <TableCell sx={styles.tableHeadCell}>User</TableCell>
              <TableCell sx={styles.tableHeadCell}>Role</TableCell>
              <TableCell sx={styles.tableHeadCell}>Status</TableCell>
              <TableCell sx={styles.tableHeadCell}>Invited</TableCell>
              <TableCell sx={styles.tableHeadCell} align="right">
                Actions
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {users.map((user) => (
              <TableRow key={user.id} hover>
                <TableCell sx={styles.tableCell}>
                  <Box sx={styles.userInfo}>
                    <Typography sx={styles.userName}>{user.name}</Typography>
                    <Typography sx={styles.userEmail}>{user.email}</Typography>
                  </Box>
                </TableCell>
                <TableCell sx={styles.tableCell}>
                  <Chip label={user.role} size="small" sx={{ ...styles.chip, ...roleStyles[user.role] }} />
                </TableCell>
                <TableCell sx={styles.tableCell}>
                  <Chip label={user.state} size="small" sx={{ ...styles.chip, ...stateStyles[user.state] }} />
                </TableCell>
                <TableCell sx={styles.tableCell}>
                  {user.invitedAt ? (
                    <Box>
                      <Typography sx={{ fontSize: 14 }}>{format(new Date(user.invitedAt), 'MMM d, yyyy')}</Typography>
                      {user.invitedBy && <Typography sx={styles.invitedBy}>by {user.invitedBy.name}</Typography>}
                    </Box>
                  ) : (
                    <Typography sx={{ color: 'text.secondaryAlt', fontSize: 14 }}>Self-registered</Typography>
                  )}
                </TableCell>
                <TableCell sx={styles.tableCell} align="right">
                  <Tooltip title="Actions">
                    <IconButton size="small" onClick={(e) => handleMenuOpen(e, user)}>
                      <MoreVertIcon />
                    </IconButton>
                  </Tooltip>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>

      <TablePagination
        component="div"
        count={totalCount}
        page={page - 1}
        onPageChange={(_, newPage) => onPageChange(newPage + 1)}
        rowsPerPage={perPage}
        onRowsPerPageChange={(e) => onPerPageChange(parseInt(e.target.value, 10))}
        rowsPerPageOptions={[10, 25, 50]}
      />

      <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose}>
        {selectedUser?.state === 'active' && (
          <MenuItem onClick={() => handleStateChange('archive')}>
            <ArchiveIcon sx={{ mr: 1 }} fontSize="small" />
            Archive
          </MenuItem>
        )}
        {(selectedUser?.state === 'archived' || selectedUser?.state === 'pending') && (
          <MenuItem onClick={() => handleStateChange('activate')}>
            <CheckCircleIcon sx={{ mr: 1 }} fontSize="small" />
            Activate
          </MenuItem>
        )}
        {canChangeRole && selectedUser?.role === 'employee' && (
          <MenuItem onClick={() => handleRoleChange('admin')}>Make Admin</MenuItem>
        )}
        {canChangeRole && selectedUser?.role === 'admin' && !isLastAdmin && (
          <MenuItem onClick={() => handleRoleChange('employee')}>Make Employee</MenuItem>
        )}
        {canChangeRole && selectedUser?.role === 'admin' && isLastAdmin && (
          <Tooltip title="Cannot demote the last admin">
            <span>
              <MenuItem disabled>Make Employee</MenuItem>
            </span>
          </Tooltip>
        )}
        {canDeleteUser && <Divider />}
        {canDeleteUser && (
          <MenuItem onClick={handleDelete} sx={{ color: 'error.main' }}>
            <DeleteIcon sx={{ mr: 1 }} fontSize="small" />
            Delete
          </MenuItem>
        )}
      </Menu>
    </Box>
  );
};

export { MembersTable };
