import GitHubIcon from '@mui/icons-material/GitHub';
import LockIcon from '@mui/icons-material/Lock';
import PublicIcon from '@mui/icons-material/Public';
import SearchIcon from '@mui/icons-material/Search';
import {
  Autocomplete,
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  TextField,
  Typography,
} from '@mui/material';
import { useState, useMemo, useEffect, type FC } from 'react';

import type { Integration } from 'features/integrations-management/lib/types';
import { useGetCompanyIntegrationsQuery } from 'features/integrations-management/api/integrationsApi';

import { useGetAvailableRepositoriesQuery, useGetBranchesQuery } from '../api/repositoriesApi';
import type { AvailableRepo } from '../lib/types';

interface AddRepositoryDialogProps {
  open: boolean;
  onClose: () => void;
  onAdd: (integrationId: number, fullName: string, sourceBranch: string, purpose: string) => void;
  existingRepoNames: Set<string>;
  projectId?: number;
}

export const AddRepositoryDialog: FC<AddRepositoryDialogProps> = ({
  open,
  onClose,
  onAdd,
  existingRepoNames,
  projectId,
}) => {
  const { data: integrations } = useGetCompanyIntegrationsQuery();
  const githubIntegrations = useMemo(
    () => (integrations ?? []).filter((i: Integration) => i.provider === 'github' && i.status === 'active'),
    [integrations],
  );

  const [selectedIntegrationId, setSelectedIntegrationId] = useState<number | ''>('');
  const [selectedRepo, setSelectedRepo] = useState<AvailableRepo | null>(null);
  const [selectedBranch, setSelectedBranch] = useState<string | null>(null);
  const [purpose, setPurpose] = useState('');

  const integrationId = selectedIntegrationId || githubIntegrations[0]?.id;

  const { data: availableRepos, isLoading: isLoadingRepos } = useGetAvailableRepositoriesQuery(
    { integrationId: integrationId as number, projectId },
    { skip: !integrationId || !open },
  );

  const { data: branches, isLoading: isLoadingBranches } = useGetBranchesQuery(
    { integrationId: integrationId as number, fullName: selectedRepo?.fullName ?? '', projectId },
    { skip: !integrationId || !selectedRepo },
  );

  useEffect(() => {
    if (selectedRepo && branches?.length) {
      setSelectedBranch(selectedRepo.defaultBranch);
    } else {
      setSelectedBranch(null);
    }
  }, [selectedRepo, branches]);

  const handleAdd = () => {
    if (!integrationId || !selectedRepo || !selectedBranch) return;
    onAdd(integrationId as number, selectedRepo.fullName, selectedBranch, purpose);
    handleClose();
  };

  const handleClose = () => {
    setSelectedRepo(null);
    setSelectedBranch(null);
    setSelectedIntegrationId('');
    setPurpose('');
    onClose();
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Add Repository</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
        {githubIntegrations.length > 1 && (
          <FormControl fullWidth size="small">
            <InputLabel>GitHub Organization</InputLabel>
            <Select
              value={selectedIntegrationId || githubIntegrations[0]?.id || ''}
              label="GitHub Organization"
              onChange={(e) => {
                setSelectedIntegrationId(e.target.value as number);
                setSelectedRepo(null);
                setSelectedBranch(null);
              }}
            >
              {githubIntegrations.map((i: Integration) => (
                <MenuItem key={i.id} value={i.id}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <GitHubIcon fontSize="small" />
                    {i.name}
                  </Box>
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        )}

        <Autocomplete
          options={availableRepos ?? []}
          loading={isLoadingRepos}
          value={selectedRepo}
          onChange={(_, value) => {
            setSelectedRepo(value);
            setSelectedBranch(null);
          }}
          getOptionLabel={(option) => option.fullName}
          getOptionDisabled={(option) => existingRepoNames.has(option.fullName)}
          renderOption={(props, option) => (
            <li {...props} key={option.fullName}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, width: '100%' }}>
                {option.isPrivate ? <LockIcon fontSize="small" color="warning" /> : <PublicIcon fontSize="small" color="success" />}
                <Box sx={{ flex: 1 }}>
                  <Typography variant="body2" fontWeight={500}>
                    {option.fullName}
                  </Typography>
                  {option.description && (
                    <Typography variant="caption" color="text.secondary" noWrap>
                      {option.description}
                    </Typography>
                  )}
                </Box>
                <Typography variant="caption" color="text.secondary">
                  {option.defaultBranch}
                </Typography>
                {existingRepoNames.has(option.fullName) && (
                  <Typography variant="caption" color="text.disabled">
                    added
                  </Typography>
                )}
              </Box>
            </li>
          )}
          renderInput={(params) => (
            <TextField
              {...params}
              label="Search repositories"
              placeholder="Type to search..."
              InputProps={{
                ...params.InputProps,
                startAdornment: <SearchIcon fontSize="small" sx={{ mr: 1, color: 'text.secondary' }} />,
                endAdornment: (
                  <>
                    {isLoadingRepos ? <CircularProgress size={20} /> : null}
                    {params.InputProps.endAdornment}
                  </>
                ),
              }}
            />
          )}
        />

        {selectedRepo && (
          <>
            <Autocomplete
              options={branches ?? []}
              loading={isLoadingBranches}
              value={selectedBranch}
              onChange={(_, value) => setSelectedBranch(value)}
              renderInput={(params) => (
                <TextField
                  {...params}
                  label="Source branch"
                  placeholder={isLoadingBranches ? 'Loading branches...' : 'Select branch'}
                  InputProps={{
                    ...params.InputProps,
                    endAdornment: (
                      <>
                        {isLoadingBranches ? <CircularProgress size={20} /> : null}
                        {params.InputProps.endAdornment}
                      </>
                    ),
                  }}
                />
              )}
            />
            <TextField
              label="Purpose"
              placeholder='e.g. "Our main Rails app" or "React template for new projects"'
              value={purpose}
              onChange={(e) => setPurpose(e.target.value)}
              multiline
              minRows={2}
              maxRows={4}
              helperText="Helps AI agents understand what this repository is used for"
            />
          </>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose}>Cancel</Button>
        <Button onClick={handleAdd} variant="contained" disabled={!selectedRepo || !selectedBranch}>
          Add Repository
        </Button>
      </DialogActions>
    </Dialog>
  );
};
