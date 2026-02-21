import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';
import EditIcon from '@mui/icons-material/Edit';
import GitHubIcon from '@mui/icons-material/GitHub';
import LinkIcon from '@mui/icons-material/Link';
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
  Typography,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import { useState, type FC } from 'react';

import { useGetCompanyIntegrationsQuery, useDeleteIntegrationMutation } from '../api/integrationsApi';
import type { Integration } from '../lib/types';

const getGithubInstallUrl = () => {
  const slug = window.Settings?.githubAppSlug;
  return slug ? `https://github.com/apps/${slug}/installations/new` : null;
};

const statusColors: Record<string, 'success' | 'default' | 'error'> = {
  active: 'success',
  inactive: 'default',
  error: 'error',
};

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

export const IntegrationsPanel: FC = () => {
  const { data: integrations, isLoading } = useGetCompanyIntegrationsQuery();
  const [deleteIntegration] = useDeleteIntegrationMutation();
  const { enqueueSnackbar } = useSnackbar();
  const [deleteTarget, setDeleteTarget] = useState<Integration | null>(null);

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await deleteIntegration(deleteTarget.id).unwrap();
      enqueueSnackbar('Integration removed', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to remove integration', { variant: 'error' });
    }
    setDeleteTarget(null);
  };

  const handleConnectGithub = () => {
    const url = getGithubInstallUrl();
    if (url) {
      window.open(url, '_blank');
    } else {
      enqueueSnackbar('GitHub App not configured', { variant: 'warning' });
    }
  };

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
          <Typography sx={styles.title}>Integrations</Typography>
          <Typography sx={styles.subtitle}>Connect external services to your company</Typography>
        </Box>
        <Button variant="contained" startIcon={<GitHubIcon />} onClick={handleConnectGithub}>
          Connect GitHub
        </Button>
      </Box>

      {!integrations?.length ? (
        <Box sx={styles.emptyState}>
          <LinkIcon sx={{ fontSize: 48, color: 'text.disabled', mb: 2 }} />
          <Typography variant="h6" color="text.secondary">
            No integrations connected
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 2 }}>
            Connect GitHub to access repositories in agent sessions
          </Typography>
          <Button variant="outlined" startIcon={<GitHubIcon />} onClick={handleConnectGithub}>
            Connect GitHub
          </Button>
        </Box>
      ) : (
        <Stack spacing={2}>
          {integrations.map((integration) => (
            <Card key={integration.id} variant="outlined" sx={styles.card}>
              <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2, '&:last-child': { pb: 2 } }}>
                <GitHubIcon sx={{ fontSize: 32, color: 'text.secondary' }} />
                <Box sx={{ flex: 1 }}>
                  <Typography variant="subtitle1" fontWeight={600}>
                    {integration.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Connected by {integration.connectedBy?.name}
                  </Typography>
                </Box>
                <Chip label={integration.status} size="small" color={statusColors[integration.status] || 'default'} />
                {integration.githubUrl && (
                  <IconButton
                    size="small"
                    onClick={() => window.open(integration.githubUrl!, '_blank')}
                    title="Manage on GitHub"
                  >
                    <EditIcon fontSize="small" />
                  </IconButton>
                )}
                <IconButton size="small" color="error" onClick={() => setDeleteTarget(integration)}>
                  <DeleteOutlineIcon />
                </IconButton>
              </CardContent>
            </Card>
          ))}
        </Stack>
      )}

      <Dialog open={!!deleteTarget} onClose={() => setDeleteTarget(null)}>
        <DialogTitle>Remove Integration</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Are you sure you want to remove <strong>{deleteTarget?.name}</strong>? This will also remove all linked
            repositories.
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
