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

import {
  useDeleteIntegrationMutation,
  useDeleteProjectIntegrationMutation,
  useGetCompanyIntegrationsQuery,
  useGetProjectIntegrationsQuery,
} from '../api/integrationsApi';
import type { Integration } from '../lib/types';

export interface IntegrationsPanelProps {
  /** When set, loads integrations visible to this project (company-wide + project-scoped). */
  projectId?: number;
}

const getGithubInstallUrl = (projectId?: number) => {
  const slug = window.Settings?.githubAppSlug;
  if (!slug) return null;
  const base = `https://github.com/apps/${slug}/installations/new`;
  if (projectId == null) return base;
  return `${base}?state=${encodeURIComponent(`project:${projectId}`)}`;
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
  sectionLabel: { fontSize: 13, fontWeight: 600, color: 'text.secondary', mt: 2, mb: 1 },
};

export const IntegrationsPanel: FC<IntegrationsPanelProps> = ({ projectId }) => {
  const companyQuery = useGetCompanyIntegrationsQuery(undefined, { skip: projectId != null });
  const projectQuery = useGetProjectIntegrationsQuery(projectId!, { skip: projectId == null });

  const integrations = projectId != null ? projectQuery.data : companyQuery.data;
  const isLoading = projectId != null ? projectQuery.isLoading : companyQuery.isLoading;

  const [deleteCompanyIntegration] = useDeleteIntegrationMutation();
  const [deleteProjectIntegration] = useDeleteProjectIntegrationMutation();
  const { enqueueSnackbar } = useSnackbar();
  const [deleteTarget, setDeleteTarget] = useState<Integration | null>(null);

  const canRemove = (integration: Integration) => {
    if (projectId == null) return true;
    return integration.scope === 'project';
  };

  /** Company-wide rows on a project screen are informational only — no GitHub management link. */
  const canOpenGithubSettings = (integration: Integration) => {
    if (!integration.githubUrl) return false;
    if (projectId != null && integration.scope === 'company') return false;
    return true;
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      if (projectId != null && deleteTarget.scope === 'project') {
        await deleteProjectIntegration({ projectId, id: deleteTarget.id }).unwrap();
      } else if (projectId == null) {
        await deleteCompanyIntegration(deleteTarget.id).unwrap();
      }
      enqueueSnackbar('Integration removed', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to remove integration', { variant: 'error' });
    }
    setDeleteTarget(null);
  };

  const handleConnectGithub = () => {
    const url = getGithubInstallUrl(projectId);
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

  const list = integrations ?? [];
  const projectScoped = projectId != null ? list.filter((i) => i.scope === 'project') : list;
  const companyScoped = projectId != null ? list.filter((i) => i.scope === 'company') : [];

  const renderCard = (integration: Integration) => (
    <Card key={`${integration.scope}-${integration.id}`} variant="outlined" sx={styles.card}>
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
        {integration.scope === 'company' && projectId != null && (
          <Chip size="small" label="Company-wide" variant="outlined" sx={{ mr: 0.5 }} />
        )}
        <Chip label={integration.status} size="small" color={statusColors[integration.status] || 'default'} />
        {canOpenGithubSettings(integration) && (
          <IconButton
            size="small"
            onClick={() => window.open(integration.githubUrl!, '_blank')}
            title="Manage on GitHub"
          >
            <EditIcon fontSize="small" />
          </IconButton>
        )}
        {canRemove(integration) && (
          <IconButton size="small" color="error" onClick={() => setDeleteTarget(integration)}>
            <DeleteOutlineIcon />
          </IconButton>
        )}
      </CardContent>
    </Card>
  );

  const showMainEmpty = list.length === 0;

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>Integrations</Typography>
          <Typography sx={styles.subtitle}>
            {projectId != null
              ? 'Connect GitHub for this project, or use company-wide integrations already linked below'
              : 'Connect external services to your company'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<GitHubIcon />} onClick={handleConnectGithub}>
          Connect GitHub
        </Button>
      </Box>

      {showMainEmpty ? (
        <Box sx={styles.emptyState}>
          <LinkIcon sx={{ fontSize: 48, color: 'text.disabled', mb: 2 }} />
          <Typography variant="h6" color="text.secondary">
            No integrations connected
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 2 }}>
            {projectId != null
              ? 'Add a project-scoped GitHub installation, or rely on company integrations'
              : 'Connect GitHub to access repositories in agent sessions'}
          </Typography>
          <Button variant="outlined" startIcon={<GitHubIcon />} onClick={handleConnectGithub}>
            Connect GitHub
          </Button>
        </Box>
      ) : (
        <Stack spacing={2}>
          {projectId != null && projectScoped.length > 0 && (
            <>
              <Typography sx={styles.sectionLabel}>This project</Typography>
              {projectScoped.map(renderCard)}
            </>
          )}
          {projectId != null && companyScoped.length > 0 && (
            <>
              <Typography sx={styles.sectionLabel}>Company-wide (read-only here)</Typography>
              {companyScoped.map(renderCard)}
            </>
          )}
          {projectId == null && list.map(renderCard)}
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
