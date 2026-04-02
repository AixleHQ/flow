import AddIcon from '@mui/icons-material/Add';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import HistoryIcon from '@mui/icons-material/History';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import SearchIcon from '@mui/icons-material/Search';
import SettingsIcon from '@mui/icons-material/Settings';
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  Grid,
  IconButton,
  InputAdornment,
  TextField,
  Tooltip,
  Typography,
  type SxProps,
} from '@mui/material';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useCallback, useMemo, useState, type FC, type ReactNode } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { AixleBuilderBanner } from 'features/aixle-builder';
import { Routes } from 'shared/routes';

import {
  useGetCompanyWorkflowsQuery,
  useGetProjectWorkflowsQuery,
  useDuplicateWorkflowToProjectMutation,
} from '../api/workflowsApi';
import type { Workflow } from '../lib/types';

import { CreateWorkflowDialog } from './CreateWorkflowDialog';
import { DeleteWorkflowDialog } from './DeleteWorkflowDialog';
import { EditWorkflowDialog } from './EditWorkflowDialog';

export interface RunWorkflowModalSlot {
  open: boolean;
  workflow: { id: number; name: string; description?: string } | null;
  projectId: number;
  onClose: () => void;
}

interface WorkflowsPanelProps {
  projectId?: number;
  renderRunModal?: (props: RunWorkflowModalSlot) => ReactNode;
}

const styles = {
  root: { p: 3 },
  header: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 },
  title: { fontSize: 24, fontWeight: 600, color: 'text.primaryAlt' },
  subtitle: { fontSize: 14, color: 'text.secondaryAlt', mt: 0.5 },
  filters: { display: 'flex', gap: 2, mb: 3, alignItems: 'center' },
  searchField: { width: 300 },
  loadingContainer: { display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: 400 },
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
  emptyStateText: { color: 'text.secondaryAlt', fontSize: 16, mt: 2 },
  card: {
    padding: '16px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '8px',
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
      backgroundColor: 'background.elevated',
    },
  },
  cardName: {
    fontSize: '16px',
    fontWeight: 500,
    color: 'text.primary',
  },
  cardMeta: {
    fontSize: '12px',
    color: 'text.secondary',
    mt: 0.5,
  },
  cardActions: {
    display: 'flex',
    gap: 1,
    mt: 'auto',
    pt: 1.5,
    alignItems: 'center',
    justifyContent: 'space-between',
  },
} satisfies Record<string, SxProps>;

export const WorkflowsPanel: FC<WorkflowsPanelProps> = ({ projectId, renderRunModal }) => {
  const isProjectContext = !!projectId;
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [createOpen, setCreateOpen] = useState(false);
  const [editWorkflow, setEditWorkflow] = useState<Workflow | null>(null);
  const [deleteWorkflow, setDeleteWorkflow] = useState<Workflow | null>(null);
  const [runWorkflow, setRunWorkflow] = useState<Workflow | null>(null);
  const [duplicateWorkflowMutation] = useDuplicateWorkflowToProjectMutation();

  const { data: companyWorkflows, isLoading: isLoadingCompany } = useGetCompanyWorkflowsQuery(undefined, {
    skip: isProjectContext,
  });
  const { data: projectWorkflows, isLoading: isLoadingProject } = useGetProjectWorkflowsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const workflows = isProjectContext ? projectWorkflows : companyWorkflows;

  const debouncedSetSearch = useDebouncedCallback((value: string) => setSearch(value), 300);
  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  const filtered = useMemo(() => {
    if (!workflows) return [];
    if (!search) return workflows;
    const lower = search.toLowerCase();
    return workflows.filter(
      (w) => w.name.toLowerCase().includes(lower) || w.description?.toLowerCase().includes(lower),
    );
  }, [workflows, search]);

  const handleDuplicateAndConfigure = useCallback(
    async (wf: Workflow) => {
      if (!projectId) return;
      try {
        const copy = await duplicateWorkflowMutation({ projectId, id: wf.id }).unwrap();
        enqueueSnackbar(`Copied "${wf.name}" to project`, { variant: 'success' });
        navigate({
          to: Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(copy.id)),
        });
      } catch {
        enqueueSnackbar('Failed to copy workflow', { variant: 'error' });
      }
    },
    [projectId, duplicateWorkflowMutation, enqueueSnackbar, navigate],
  );

  const navigateToBuilder = useCallback(
    (wf: Workflow) => {
      navigate({
        to: projectId
          ? Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(wf.id))
          : Routes.frontend.companyWorkflowBuilderPath(String(wf.id)),
      });
    },
    [navigate, projectId],
  );

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project Workflows' : 'Company Workflows'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage workflows for this project. Company workflows are shared across all projects.'
              : 'Manage company-wide workflow templates available in all projects.'}
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', gap: 1 }}>
          {isProjectContext && (
            <Button
              variant="outlined"
              startIcon={<HistoryIcon />}
              onClick={() => navigate({ to: Routes.frontend.companyProjectTabPath(String(projectId), 'runs') })}
            >
              Run History
            </Button>
          )}
          <Button variant="contained" startIcon={<AddIcon />} onClick={() => setCreateOpen(true)}>
            New Workflow
          </Button>
        </Box>
      </Box>

      {isProjectContext && <AixleBuilderBanner projectId={projectId!} />}

      <Box sx={styles.filters}>
        <TextField
          placeholder="Search workflows..."
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
      </Box>

      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filtered.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>&#128736;</Typography>
          <Typography sx={styles.emptyStateText}>
            {search ? 'No workflows match your search' : 'No workflows yet'}
          </Typography>
          {!search && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setCreateOpen(true)}>
              Create your first workflow
            </Button>
          )}
        </Box>
      ) : (
        <Grid container spacing={2}>
          {filtered.map((wf) => {
            const isInherited = isProjectContext && wf.scopeIndicator === 'company';

            return (
              <Grid item xs={12} sm={6} md={4} key={wf.id}>
                <Box sx={styles.card}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Typography sx={styles.cardName}>{wf.name}</Typography>
                    {isInherited && <Chip label="company" size="small" color="primary" variant="outlined" />}
                  </Box>
                  {wf.descriptionExcerpt && (
                    <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }} noWrap>
                      {wf.descriptionExcerpt}
                    </Typography>
                  )}
                  <Typography sx={styles.cardMeta}>
                    {wf.stepsCount} steps
                    {wf.lastRunAt && <> &middot; Last run {new Date(wf.lastRunAt).toLocaleDateString()}</>}
                  </Typography>

                  <Box sx={styles.cardActions}>
                    <Box sx={{ display: 'flex', gap: 1 }}>
                      {isProjectContext && (
                        <Button
                          size="small"
                          variant="contained"
                          startIcon={<PlayArrowIcon />}
                          onClick={() => setRunWorkflow(wf)}
                        >
                          Run
                        </Button>
                      )}
                      {isInherited ? (
                        <Button
                          size="small"
                          variant="outlined"
                          startIcon={<ContentCopyIcon />}
                          onClick={() => handleDuplicateAndConfigure(wf)}
                        >
                          Copy & Configure
                        </Button>
                      ) : (
                        <Button
                          size="small"
                          variant="outlined"
                          startIcon={<SettingsIcon />}
                          onClick={() => navigateToBuilder(wf)}
                        >
                          Configure
                        </Button>
                      )}
                    </Box>

                    {!isInherited && (
                      <Box sx={{ display: 'flex', gap: 0.5 }}>
                        <Tooltip title="Edit name & description">
                          <IconButton size="small" onClick={() => setEditWorkflow(wf)}>
                            <EditIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title="Delete workflow">
                          <IconButton size="small" color="error" onClick={() => setDeleteWorkflow(wf)}>
                            <DeleteIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      </Box>
                    )}
                  </Box>
                </Box>
              </Grid>
            );
          })}
        </Grid>
      )}

      <CreateWorkflowDialog
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        projectId={projectId}
        onSuccess={(id) =>
          navigate({
            to: projectId
              ? Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(id))
              : Routes.frontend.companyWorkflowBuilderPath(String(id)),
          })
        }
      />

      {editWorkflow && (
        <EditWorkflowDialog
          open={!!editWorkflow}
          onClose={() => setEditWorkflow(null)}
          workflow={editWorkflow}
          projectId={projectId}
        />
      )}

      {deleteWorkflow && (
        <DeleteWorkflowDialog
          open={!!deleteWorkflow}
          onClose={() => setDeleteWorkflow(null)}
          workflow={deleteWorkflow}
          projectId={projectId}
        />
      )}

      {isProjectContext &&
        renderRunModal?.({
          open: !!runWorkflow,
          workflow: runWorkflow
            ? { id: runWorkflow.id, name: runWorkflow.name, description: runWorkflow.description ?? undefined }
            : null,
          projectId: projectId!,
          onClose: () => setRunWorkflow(null),
        })}
    </Box>
  );
};

export default WorkflowsPanel;
