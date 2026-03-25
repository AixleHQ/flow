import AddIcon from '@mui/icons-material/Add';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import EditIcon from '@mui/icons-material/Edit';
import FolderIcon from '@mui/icons-material/Folder';
import LockIcon from '@mui/icons-material/Lock';
import PublicIcon from '@mui/icons-material/Public';
import {
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  IconButton,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { useMemo, useState, type FC } from 'react';

import {
  useGetCompanyRepositoriesQuery,
  useGetProjectRepositoriesQuery,
  useCreateCompanyRepositoryMutation,
  useCreateProjectRepositoryMutation,
  useUpdateCompanyRepositoryMutation,
  useUpdateProjectRepositoryMutation,
  useDeleteCompanyRepositoryMutation,
  useDeleteProjectRepositoryMutation,
  useGetWebhookInfoQuery,
} from '../api/repositoriesApi';
import type { Repository } from '../lib/types';

import { AddRepositoryDialog } from './AddRepositoryDialog';
import { EditRepositoryDialog } from './EditRepositoryDialog';

interface RepositoriesPanelProps {
  projectId?: number;
}

const styles = {
  root: { p: 3 },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    mb: 3,
  },
  title: { fontSize: 24, fontWeight: 600, color: 'text.primaryAlt' },
  subtitle: { fontSize: 14, color: 'text.secondaryAlt', mt: 0.5 },
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
  card: {
    backgroundColor: 'background.surface',
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
};

interface WebhookInfoDialogProps {
  repositoryId: number | null;
  projectId?: number;
  onClose: () => void;
}

const WebhookInfoDialog: FC<WebhookInfoDialogProps> = ({ repositoryId, projectId, onClose }) => {
  const { data: webhookInfo } = useGetWebhookInfoQuery(
    { id: repositoryId!, projectId },
    { skip: repositoryId === null },
  );
  const { enqueueSnackbar } = useSnackbar();

  const copyToClipboard = (value: string, label: string) => {
    navigator.clipboard.writeText(value);
    enqueueSnackbar(`${label} copied to clipboard`, { variant: 'info' });
  };

  return (
    <Dialog open={repositoryId !== null} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>Configure GitLab Webhook</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
        <Typography variant="body2" color="text.secondary">
          To receive pipeline events, add a webhook to your GitLab repository with the following settings:
        </Typography>
        {webhookInfo ? (
          <>
            <TextField
              label="Webhook URL"
              value={webhookInfo.url}
              size="small"
              fullWidth
              InputProps={{
                readOnly: true,
                endAdornment: (
                  <IconButton size="small" onClick={() => copyToClipboard(webhookInfo.url, 'Webhook URL')}>
                    <ContentCopyIcon fontSize="small" />
                  </IconButton>
                ),
              }}
            />
            <TextField
              label="Secret Token"
              value={webhookInfo.secretToken}
              size="small"
              fullWidth
              InputProps={{
                readOnly: true,
                endAdornment: (
                  <IconButton size="small" onClick={() => copyToClipboard(webhookInfo.secretToken, 'Secret token')}>
                    <ContentCopyIcon fontSize="small" />
                  </IconButton>
                ),
              }}
            />
            <TextField
              label="Trigger"
              value={webhookInfo.trigger}
              size="small"
              fullWidth
              InputProps={{ readOnly: true }}
            />
          </>
        ) : (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 2 }}>
            <CircularProgress size={24} />
          </Box>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} variant="contained">
          Done
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export const RepositoriesPanel: FC<RepositoriesPanelProps> = ({ projectId }) => {
  const companyQuery = useGetCompanyRepositoriesQuery(undefined, { skip: !!projectId });
  const projectQuery = useGetProjectRepositoriesQuery(projectId!, { skip: !projectId });

  const { data: repositories, isLoading } = projectId ? projectQuery : companyQuery;

  const [createCompany] = useCreateCompanyRepositoryMutation();
  const [createProject] = useCreateProjectRepositoryMutation();
  const [updateCompany] = useUpdateCompanyRepositoryMutation();
  const [updateProject] = useUpdateProjectRepositoryMutation();
  const [deleteCompany] = useDeleteCompanyRepositoryMutation();
  const [deleteProject] = useDeleteProjectRepositoryMutation();

  const { enqueueSnackbar } = useSnackbar();
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<Repository | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Repository | null>(null);
  const [webhookInfoRepositoryId, setWebhookInfoRepositoryId] = useState<number | null>(null);

  const existingRepoNames = useMemo(() => new Set((repositories ?? []).map((r) => r.fullName)), [repositories]);

  const handleAdd = async (integrationId: number, fullName: string, sourceBranch: string, purpose: string) => {
    try {
      let repo: Repository;
      if (projectId) {
        repo = await createProject({
          projectId,
          integrationId,
          fullName,
          sourceBranch,
          purpose: purpose || undefined,
        }).unwrap();
      } else {
        repo = await createCompany({ integrationId, fullName, sourceBranch, purpose: purpose || undefined }).unwrap();
      }
      enqueueSnackbar('Repository added', { variant: 'success' });
      if (repo.integration?.provider === 'gitlab') {
        setWebhookInfoRepositoryId(repo.id);
      }
    } catch {
      enqueueSnackbar('Failed to add repository', { variant: 'error' });
    }
  };

  const handleUpdate = async (id: number, sourceBranch: string, purpose: string) => {
    try {
      if (projectId) {
        await updateProject({ projectId, id, sourceBranch, purpose }).unwrap();
      } else {
        await updateCompany({ id, sourceBranch, purpose }).unwrap();
      }
      enqueueSnackbar('Repository updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update repository', { variant: 'error' });
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      if (projectId) {
        await deleteProject({ projectId, id: deleteTarget.id }).unwrap();
      } else {
        await deleteCompany(deleteTarget.id).unwrap();
      }
      enqueueSnackbar('Repository removed', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to remove repository', { variant: 'error' });
    }
    setDeleteTarget(null);
  };

  const canEdit = (repo: Repository) => !projectId || repo.scopeIndicator === 'project';

  if (isLoading) {
    return (
      <Box sx={styles.loadingContainer}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>Repositories</Typography>
          <Typography sx={styles.subtitle}>Repositories available for agent sessions</Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setAddDialogOpen(true)}>
          Add Repository
        </Button>
      </Box>

      {!repositories?.length ? (
        <Box sx={styles.emptyState}>
          <FolderIcon sx={{ fontSize: 48, color: 'text.disabled', mb: 2 }} />
          <Typography variant="h6" color="text.secondary">
            No repositories added
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 2 }}>
            Add repositories to use as code context in agent sessions
          </Typography>
          <Button variant="outlined" startIcon={<AddIcon />} onClick={() => setAddDialogOpen(true)}>
            Add Repository
          </Button>
        </Box>
      ) : (
        <Stack spacing={2}>
          {repositories.map((repo) => (
            <Card key={repo.id} variant="outlined" sx={styles.card}>
              <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2, '&:last-child': { pb: 2 } }}>
                {repo.isPrivate ? (
                  <LockIcon sx={{ fontSize: 28, color: 'warning.main' }} />
                ) : (
                  <PublicIcon sx={{ fontSize: 28, color: 'success.main' }} />
                )}
                <Box sx={{ flex: 1 }}>
                  <Typography variant="subtitle1" fontWeight={600}>
                    {repo.fullName}
                  </Typography>
                  {repo.purpose && (
                    <Typography variant="body2" color="text.primary" sx={{ fontStyle: 'italic' }}>
                      {repo.purpose}
                    </Typography>
                  )}
                  <Typography variant="body2" color="text.secondary">
                    {repo.sourceBranch} &middot; {repo.integration?.name}
                    {repo.description && ` — ${repo.description}`}
                  </Typography>
                </Box>
                <Chip label={repo.sourceBranch} size="small" variant="outlined" />
                {projectId && (
                  <Chip
                    label={repo.scopeIndicator}
                    size="small"
                    color={repo.scopeIndicator === 'company' ? 'info' : 'default'}
                    variant="outlined"
                  />
                )}
                {canEdit(repo) && (
                  <IconButton size="small" onClick={() => setEditTarget(repo)}>
                    <EditIcon fontSize="small" />
                  </IconButton>
                )}
                {canEdit(repo) && (
                  <IconButton size="small" color="error" onClick={() => setDeleteTarget(repo)}>
                    <DeleteOutlineIcon />
                  </IconButton>
                )}
              </CardContent>
            </Card>
          ))}
        </Stack>
      )}

      <AddRepositoryDialog
        open={addDialogOpen}
        onClose={() => setAddDialogOpen(false)}
        onAdd={handleAdd}
        existingRepoNames={existingRepoNames}
        projectId={projectId}
      />

      <EditRepositoryDialog
        open={!!editTarget}
        repository={editTarget}
        onClose={() => setEditTarget(null)}
        onSave={handleUpdate}
      />

      <WebhookInfoDialog
        repositoryId={webhookInfoRepositoryId}
        projectId={projectId}
        onClose={() => setWebhookInfoRepositoryId(null)}
      />

      <Dialog open={!!deleteTarget} onClose={() => setDeleteTarget(null)}>
        <DialogTitle>Remove Repository</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Remove <strong>{deleteTarget?.fullName}</strong> from this {projectId ? 'project' : 'company'}?
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteTarget(null)}>Cancel</Button>
          <Button onClick={handleDelete} color="error" variant="contained">
            Remove
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};
