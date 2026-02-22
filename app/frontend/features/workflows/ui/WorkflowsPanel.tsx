import AddIcon from '@mui/icons-material/Add';
import SearchIcon from '@mui/icons-material/Search';
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  InputAdornment,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
  IconButton,
  Tooltip,
  type SxProps,
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import SettingsIcon from '@mui/icons-material/Settings';
import { useState, useMemo, useCallback, type FC } from 'react';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useDebouncedCallback } from 'use-debounce';

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

interface WorkflowsPanelProps {
  projectId?: number;
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
} satisfies Record<string, SxProps>;

export const WorkflowsPanel: FC<WorkflowsPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [createOpen, setCreateOpen] = useState(false);
  const [editWorkflow, setEditWorkflow] = useState<Workflow | null>(null);
  const [deleteWorkflow, setDeleteWorkflow] = useState<Workflow | null>(null);
  const [duplicateWorkflow] = useDuplicateWorkflowToProjectMutation();

  const handleDuplicateAndConfigure = useCallback(
    async (wf: Workflow) => {
      if (!projectId) return;
      try {
        const copy = await duplicateWorkflow({ projectId, id: wf.id }).unwrap();
        enqueueSnackbar(`Copied "${wf.name}" to project`, { variant: 'success' });
        navigate({
          to: Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(copy.id)),
        });
      } catch {
        enqueueSnackbar('Failed to copy workflow', { variant: 'error' });
      }
    },
    [projectId, duplicateWorkflow, enqueueSnackbar, navigate],
  );

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
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setCreateOpen(true)}>
          New Workflow
        </Button>
      </Box>

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
        <TableContainer>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>Name</TableCell>
                <TableCell>Scope</TableCell>
                <TableCell>Steps</TableCell>
                <TableCell>Last Run</TableCell>
                <TableCell align="right">Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {filtered.map((wf) => {
                const isInherited = isProjectContext && wf.scopeIndicator === 'company';

                const handleNameClick = () => {
                  if (isInherited) {
                    handleDuplicateAndConfigure(wf);
                    return;
                  }
                  navigate({
                    to: projectId
                      ? Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(wf.id))
                      : Routes.frontend.companyWorkflowBuilderPath(String(wf.id)),
                  });
                };

                return (
                  <TableRow key={wf.id} hover>
                    <TableCell>
                      <Typography
                        variant="subtitle2"
                        sx={{ cursor: 'pointer', '&:hover': { color: 'primary.main' } }}
                        onClick={handleNameClick}
                      >
                        {wf.name}
                      </Typography>
                      {wf.descriptionExcerpt && (
                        <Typography variant="body2" color="text.secondary">
                          {wf.descriptionExcerpt}
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={wf.scopeIndicator}
                        size="small"
                        color={wf.scopeIndicator === 'company' ? 'primary' : 'default'}
                        variant="outlined"
                      />
                    </TableCell>
                    <TableCell>{wf.stepsCount}</TableCell>
                    <TableCell>
                      {wf.lastRunAt ? new Date(wf.lastRunAt).toLocaleDateString() : <Typography variant="body2" color="text.secondary">Never</Typography>}
                    </TableCell>
                    <TableCell align="right">
                      {isInherited ? (
                        <Tooltip title="Copy to project and configure">
                          <IconButton size="small" onClick={() => handleDuplicateAndConfigure(wf)}>
                            <ContentCopyIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      ) : (
                        <>
                          <IconButton
                            size="small"
                            onClick={() =>
                              navigate({
                                to: projectId
                                  ? Routes.frontend.projectWorkflowBuilderPath(String(projectId), String(wf.id))
                                  : Routes.frontend.companyWorkflowBuilderPath(String(wf.id)),
                              })
                            }
                            title="Configure steps"
                          >
                            <SettingsIcon fontSize="small" />
                          </IconButton>
                          <IconButton size="small" onClick={() => setEditWorkflow(wf)}>
                            <EditIcon fontSize="small" />
                          </IconButton>
                          <IconButton size="small" color="error" onClick={() => setDeleteWorkflow(wf)}>
                            <DeleteIcon fontSize="small" />
                          </IconButton>
                        </>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
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
    </Box>
  );
};

export default WorkflowsPanel;
