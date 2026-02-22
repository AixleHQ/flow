import {
  Autocomplete,
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  MenuItem,
  Select,
  TextField,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useCallback, useMemo, useState } from 'react';

import { useGetCompanyRepositoriesQuery } from 'features/repositories-management/api/repositoriesApi';
import type { Repository } from 'features/repositories-management/lib/types';
import { useCreateWorkflowRunMutation } from 'features/workflow-execution/api/workflowRunsApi';
import type { CreateWorkflowRunRequest } from 'features/workflow-execution/lib/types';
import { Routes } from 'shared/routes';

interface RunWorkflowModalProps {
  open: boolean;
  workflow: { id: number; name: string; description?: string } | null;
  projectId: number;
  onClose: () => void;
}

const RUNTIME_OPTIONS = [
  { value: 'docker', label: 'Docker (default)' },
  { value: 'local', label: 'Local' },
  { value: 'cloud', label: 'Cloud' },
];

const MODE_OPTIONS = [
  { value: 'interactive', label: 'Interactive — pause at each step for review' },
  { value: 'non_interactive', label: 'Non-interactive — run all steps automatically' },
  { value: 'mixed', label: 'Mixed — auto-advance compatible steps' },
];

const styles = {
  dialog: {
    '& .MuiDialog-paper': {
      backgroundColor: 'background.paper',
      borderRadius: '12px',
      maxWidth: '600px',
      width: '100%',
    },
  },
  title: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    padding: '24px 24px 8px',
  },
  description: {
    fontSize: '14px',
    color: 'text.secondary',
    padding: '0 24px 16px',
  },
  content: {
    padding: '24px',
  },
  section: {
    marginBottom: '24px',
  },
  sectionTitle: {
    fontSize: '14px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '12px',
  },
  formField: {
    marginBottom: '16px',
  },
  label: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '6px',
  },
  actions: {
    padding: '16px 24px',
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  emptyState: {
    textAlign: 'center',
    padding: '32px',
  },
} satisfies Record<string, SxProps<Theme>>;

const RunWorkflowModal = ({ open, workflow, projectId, onClose }: RunWorkflowModalProps) => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const [mode, setMode] = useState<CreateWorkflowRunRequest['mode']>('interactive');
  const [selectedRepoIds, setSelectedRepoIds] = useState<number[]>([]);
  const [agentRuntime, setAgentRuntime] = useState('docker');

  const { data: repositories = [] } = useGetCompanyRepositoriesQuery();
  const [createRun, { isLoading }] = useCreateWorkflowRunMutation();

  const selectedRepos = useMemo(
    () => repositories.filter((r: Repository) => selectedRepoIds.includes(r.id)),
    [repositories, selectedRepoIds],
  );

  const handleRun = useCallback(async () => {
    if (!workflow) return;
    try {
      const result = await createRun({
        projectId,
        workflowId: workflow.id,
        mode,
        repositoryIds: selectedRepoIds,
        agentRuntime,
      }).unwrap();
      enqueueSnackbar('Workflow run started', { variant: 'success' });
      handleClose();
      navigate({
        to: Routes.frontend.workflowRunPath(String(projectId), String(result.id)),
      });
    } catch {
      enqueueSnackbar('Failed to start workflow run', { variant: 'error' });
    }
  }, [workflow, projectId, mode, selectedRepoIds, agentRuntime, createRun, enqueueSnackbar, navigate]);

  const handleClose = useCallback(() => {
    setMode('interactive');
    setSelectedRepoIds([]);
    setAgentRuntime('docker');
    onClose();
  }, [onClose]);

  if (!workflow) {
    return (
      <Dialog open={open} onClose={handleClose} sx={styles.dialog}>
        <DialogContent>
          <Box sx={styles.emptyState}>
            <Typography sx={{ fontSize: '48px', mb: 2 }}>&#9888;&#65039;</Typography>
            <Typography variant="body2" color="text.secondary">
              No workflow selected
            </Typography>
          </Box>
        </DialogContent>
        <DialogActions sx={styles.actions}>
          <Button onClick={handleClose}>Close</Button>
        </DialogActions>
      </Dialog>
    );
  }

  return (
    <Dialog open={open} onClose={handleClose} sx={styles.dialog}>
      <DialogTitle sx={styles.title}>Run: {workflow.name}</DialogTitle>
      {workflow.description && <Typography sx={styles.description}>{workflow.description}</Typography>}

      <DialogContent sx={styles.content}>
        {/* Execution Mode */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Execution Mode</Typography>
          <Select
            fullWidth
            size="small"
            value={mode}
            onChange={(e) => setMode(e.target.value as CreateWorkflowRunRequest['mode'])}
          >
            {MODE_OPTIONS.map((opt) => (
              <MenuItem key={opt.value} value={opt.value}>
                {opt.label}
              </MenuItem>
            ))}
          </Select>
        </Box>

        {/* Agent Runtime */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Agent Runtime</Typography>
          <Select
            fullWidth
            size="small"
            value={agentRuntime}
            onChange={(e) => setAgentRuntime(e.target.value)}
          >
            {RUNTIME_OPTIONS.map((opt) => (
              <MenuItem key={opt.value} value={opt.value}>
                {opt.label}
              </MenuItem>
            ))}
          </Select>
          <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
            Environment where agents will execute steps
          </Typography>
        </Box>

        {/* Repositories */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Repositories</Typography>
          <Autocomplete
            multiple
            size="small"
            options={repositories}
            getOptionLabel={(r: Repository) => r.fullName || r.repoName}
            value={selectedRepos}
            onChange={(_, newValue) => setSelectedRepoIds(newValue.map((r: Repository) => r.id))}
            renderInput={(params) => <TextField {...params} placeholder="Select repositories to mount..." />}
            renderTags={(value, getTagProps) =>
              value.map((repo, index) => (
                <Chip
                  {...getTagProps({ index })}
                  key={repo.id}
                  label={repo.repoName}
                  size="small"
                  variant="outlined"
                />
              ))
            }
            isOptionEqualToValue={(opt, val) => opt.id === val.id}
          />
          <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
            Selected repos will be available to steps that have &quot;Mount repositories&quot; enabled
          </Typography>
        </Box>
      </DialogContent>

      <DialogActions sx={styles.actions}>
        <Button onClick={handleClose}>Cancel</Button>
        <Button variant="contained" onClick={handleRun} disabled={isLoading} sx={{ minWidth: 120 }}>
          {isLoading ? 'Starting...' : 'Run Workflow'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default RunWorkflowModal;
