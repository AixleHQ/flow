import PersonAddIcon from '@mui/icons-material/PersonAdd';
import SearchIcon from '@mui/icons-material/Search';
import {
  Box,
  Button,
  CircularProgress,
  FormControl,
  InputAdornment,
  InputLabel,
  MenuItem,
  Select,
  Stack,
  TextField,
  Typography,
  SxProps,
} from '@mui/material';
import { useState, type FC, useMemo } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanyUsersQuery } from '../api/companyUsersApi';
import type { CompanyUsersFilters, UserRole, UserState } from '../lib/types';

import { InviteUserDialog } from './InviteUserDialog';
import { MembersTable } from './MembersTable';

const styles = {
  root: {
    p: 3,
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    mb: 3,
  },
  title: {
    fontSize: 24,
    fontWeight: 600,
    color: 'text.primaryAlt',
  },
  subtitle: {
    fontSize: 14,
    color: 'text.secondaryAlt',
    mt: 0.5,
  },
  filters: {
    display: 'flex',
    gap: 2,
    mb: 3,
    flexWrap: 'wrap',
  },
  searchField: {
    width: 300,
  },
  selectField: {
    width: 150,
  },
  loadingContainer: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: 400,
  },
  emptyState: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 300,
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  emptyStateText: {
    color: 'text.secondaryAlt',
    fontSize: 16,
    mt: 2,
  },
} satisfies Record<string, SxProps>;

const DEFAULT_PER_PAGE = 25;

const CompanyMembersPage: FC = () => {
  const [isInviteDialogOpen, setInviteDialogOpen] = useState(false);
  const [filters, setFilters] = useState<CompanyUsersFilters>({
    page: 1,
    perPage: DEFAULT_PER_PAGE,
  });
  const [searchInput, setSearchInput] = useState('');

  // Debounce search to avoid too many API calls
  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined, page: 1 }));
  }, 300);

  const { data, isLoading } = useGetCompanyUsersQuery(filters);

  const users = data?.items || [];
  const meta = data?.meta;
  const totalCount = meta?.totalCount || 0;

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  const handleRoleFilterChange = (role: UserRole | '') => {
    setFilters((prev) => ({
      ...prev,
      role: role || undefined,
      page: 1,
    }));
  };

  const handleStateFilterChange = (state: UserState | '') => {
    setFilters((prev) => ({
      ...prev,
      state: state || undefined,
      page: 1,
    }));
  };

  const handlePageChange = (page: number) => {
    setFilters((prev) => ({ ...prev, page }));
  };

  const handlePerPageChange = (perPage: number) => {
    setFilters((prev) => ({ ...prev, perPage, page: 1 }));
  };

  const hasFilters = useMemo(() => {
    return !!filters.search || !!filters.role || !!filters.state;
  }, [filters.search, filters.role, filters.state]);

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>Team Members</Typography>
          <Typography sx={styles.subtitle}>Manage your company&apos;s team members and their access levels</Typography>
        </Box>
        <Button variant="contained" startIcon={<PersonAddIcon />} onClick={() => setInviteDialogOpen(true)}>
          Invite User
        </Button>
      </Box>

      <Stack direction="row" sx={styles.filters}>
        <TextField
          placeholder="Search by name or email..."
          value={searchInput}
          onChange={(e) => handleSearchChange(e.target.value)}
          size="small"
          sx={styles.searchField}
          InputProps={{
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon />
              </InputAdornment>
            ),
          }}
        />

        <FormControl size="small" sx={styles.selectField}>
          <InputLabel size="small">Role</InputLabel>
          <Select
            value={filters.role || ''}
            label="Role"
            onChange={(e) => handleRoleFilterChange(e.target.value as UserRole | '')}
          >
            <MenuItem value="">All Roles</MenuItem>
            <MenuItem value="admin">Admin</MenuItem>
            <MenuItem value="employee">Employee</MenuItem>
          </Select>
        </FormControl>

        <FormControl size="small" sx={styles.selectField}>
          <InputLabel size="small">Status</InputLabel>
          <Select
            value={filters.state || ''}
            label="Status"
            onChange={(e) => handleStateFilterChange(e.target.value as UserState | '')}
          >
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="active">Active</MenuItem>
            <MenuItem value="pending">Pending</MenuItem>
            <MenuItem value="archived">Archived</MenuItem>
          </Select>
        </FormControl>
      </Stack>

      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : users.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No members match your filters' : 'No team members yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setInviteDialogOpen(true)}>
              Invite your first team member
            </Button>
          )}
        </Box>
      ) : (
        <MembersTable
          users={users}
          page={filters.page || 1}
          perPage={filters.perPage || DEFAULT_PER_PAGE}
          totalCount={totalCount}
          onPageChange={handlePageChange}
          onPerPageChange={handlePerPageChange}
        />
      )}

      <InviteUserDialog open={isInviteDialogOpen} onClose={() => setInviteDialogOpen(false)} />
    </Box>
  );
};

export default CompanyMembersPage;
