import {
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  TextField,
  Autocomplete,
} from '@mui/material';
import { useState, useEffect, type FC } from 'react';

import { useGetBranchesQuery } from '../api/repositoriesApi';
import type { Repository } from '../lib/types';

interface EditRepositoryDialogProps {
  open: boolean;
  repository: Repository | null;
  onClose: () => void;
  onSave: (id: number, sourceBranch: string, purpose: string) => void;
}

export const EditRepositoryDialog: FC<EditRepositoryDialogProps> = ({ open, repository, onClose, onSave }) => {
  const [sourceBranch, setSourceBranch] = useState('');
  const [purpose, setPurpose] = useState('');

  const { data: branches, isLoading: isLoadingBranches } = useGetBranchesQuery(
    { integrationId: repository?.integration?.id ?? 0, fullName: repository?.fullName ?? '' },
    { skip: !repository || !open },
  );

  useEffect(() => {
    if (repository) {
      setSourceBranch(repository.sourceBranch);
      setPurpose(repository.purpose ?? '');
    }
  }, [repository]);

  const handleSave = () => {
    if (!repository || !sourceBranch) return;
    onSave(repository.id, sourceBranch, purpose);
    onClose();
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Edit {repository?.fullName}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
        <Autocomplete
          freeSolo
          options={branches ?? []}
          loading={isLoadingBranches}
          value={sourceBranch}
          onChange={(_, value) => setSourceBranch(value ?? '')}
          onInputChange={(_, value) => setSourceBranch(value)}
          renderInput={(params) => (
            <TextField
              {...params}
              label="Source branch"
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
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={handleSave} variant="contained" disabled={!sourceBranch}>
          Save
        </Button>
      </DialogActions>
    </Dialog>
  );
};
