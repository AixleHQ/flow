import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import ArrowDownwardIcon from '@mui/icons-material/ArrowDownward';
import ArrowUpwardIcon from '@mui/icons-material/ArrowUpward';
import DeleteIcon from '@mui/icons-material/Delete';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Autocomplete,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  Divider,
  FormControlLabel,
  IconButton,
  MenuItem,
  Select,
  Switch,
  TextField,
  Tooltip,
  Typography,
  type SxProps,
  type Theme,
} from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetMcpServersQuery } from 'entities/mcp-server';
import type { McpServer } from 'entities/mcp-server';
import { useGetCompanyAgentsQuery } from 'features/agents-management/api/agentsApi';
import type { Agent } from 'features/agents-management/lib/types';
import { useGetCompanySkillsQuery } from 'features/skills-management/api/skillsApi';
import type { Skill } from 'features/skills-management/lib/types';
import { useGetCompanyToolsQuery } from 'features/tools-management/api/toolsApi';
import type { Tool } from 'features/tools-management/lib/types';
import {
  useGetCompanyStepsQuery,
  useGetStepsQuery,
  useCreateCompanyStepMutation,
  useCreateStepMutation,
  useUpdateCompanyStepMutation,
  useUpdateStepMutation,
  useDeleteCompanyStepMutation,
  useDeleteStepMutation,
  useReorderCompanyStepsMutation,
  useReorderStepsMutation,
} from 'features/workflow-steps/api/stepsApi';
import type { Step, SubStepAttribute, AssetSpec, UpdateStepRequest } from 'features/workflow-steps/lib/types';
import { RunWorkflowModal } from 'features/run-workflow';
import {
  useGetCompanyWorkflowQuery,
  useUpdateCompanyWorkflowMutation,
  useUpdateProjectWorkflowMutation,
  useDuplicateWorkflowToProjectMutation,
} from 'features/workflows/api/workflowsApi';
import { Routes } from 'shared/routes';

const SKIP_POLICY_OPTIONS = [
  { value: 'never', label: 'Never' },
  { value: 'if_outputs_exist', label: 'If outputs exist' },
  { value: 'manual', label: 'Manual' },
];

const ON_FAILURE_OPTIONS = [
  { value: 'retry', label: 'Retry' },
  { value: 'skip', label: 'Skip' },
  { value: 'fail', label: 'Fail' },
];

const styles = {
  root: {
    display: 'flex',
    height: '100vh',
    backgroundColor: 'background.default',
    overflow: 'hidden',
  },
  sidebar: {
    width: '300px',
    minWidth: '300px',
    backgroundColor: 'background.paper',
    borderRight: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    flexDirection: 'column',
  },
  sidebarHeader: {
    padding: '16px 20px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    gap: 1,
  },
  stepsList: {
    flex: 1,
    overflow: 'auto',
    padding: '12px',
  },
  stepItem: {
    padding: '10px 12px',
    marginBottom: '6px',
    backgroundColor: 'background.elevated',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
    cursor: 'pointer',
    transition: 'all 0.15s ease',
    display: 'flex',
    alignItems: 'center',
    gap: 1,
    '&:hover': { borderColor: 'primary.main' },
  },
  stepItemActive: {
    borderColor: 'primary.main',
    backgroundColor: 'rgba(71, 133, 255, 0.08)',
  },
  stepInfo: { flex: 1, minWidth: 0 },
  stepActions: { display: 'flex', flexDirection: 'column', gap: 0 },
  main: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  header: {
    padding: '16px 32px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerLeft: { flex: 1 },
  content: {
    flex: 1,
    overflow: 'auto',
    padding: '24px 32px',
  },
  panel: { maxWidth: '800px', margin: '0 auto' },
  section: { marginBottom: '24px' },
  sectionTitle: {
    fontSize: '15px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '12px',
  },
  formField: { marginBottom: '14px' },
  label: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.secondary',
    marginBottom: '6px',
  },
  loadingContainer: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    height: '100vh',
  },
  notFound: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100vh',
    gap: 2,
  },
  emptyState: {
    textAlign: 'center',
    padding: '64px 32px',
  },
  assetSpecRow: {
    display: 'flex',
    gap: 1,
    alignItems: 'center',
    marginBottom: '8px',
  },
  subStepRow: {
    display: 'flex',
    gap: 1,
    alignItems: 'center',
    padding: '8px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
  },
} satisfies Record<string, SxProps<Theme>>;

const WorkflowBuilderPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const params = useParams({ strict: false }) as { workflowId?: string; projectId?: string };
  const workflowId = Number(params.workflowId);
  const routeProjectId = params.projectId;

  const [selectedStepId, setSelectedStepId] = useState<number | null>(null);
  const [deleteStepId, setDeleteStepId] = useState<number | null>(null);
  const [workflowName, setWorkflowName] = useState('');
  const [workflowDescription, setWorkflowDescription] = useState('');
  const [nameInitialized, setNameInitialized] = useState(false);
  const [runModalOpen, setRunModalOpen] = useState(false);

  // Fetch workflow
  const {
    data: workflow,
    isLoading: workflowLoading,
    isError: workflowError,
  } = useGetCompanyWorkflowQuery(workflowId, { skip: !workflowId || isNaN(workflowId) });

  const isCompanyScope = workflow?.scopeType === 'Company';
  const projectId = !isCompanyScope ? workflow?.scopeId : undefined;

  // Initialize local name/description from fetched data
  useEffect(() => {
    if (workflow && !nameInitialized) {
      setWorkflowName(workflow.name);
      setWorkflowDescription(workflow.description || '');
      setNameInitialized(true);
    }
  }, [workflow, nameInitialized]);

  // Fetch steps (scope-aware)
  const { data: companySteps } = useGetCompanyStepsQuery({ workflowId }, { skip: !workflow || !isCompanyScope });
  const { data: projectSteps } = useGetStepsQuery(
    { projectId: projectId!, workflowId },
    { skip: !workflow || isCompanyScope || !projectId },
  );
  const steps = useMemo(() => {
    const raw = isCompanyScope ? companySteps : projectSteps;
    return raw ? [...raw].sort((a, b) => a.position - b.position) : [];
  }, [isCompanyScope, companySteps, projectSteps]);

  const selectedStep = steps.find((s) => s.id === selectedStepId) ?? null;

  // Fetch agents, tools, mcp servers, skills
  const { data: agents = [] } = useGetCompanyAgentsQuery();
  const { data: tools = [] } = useGetCompanyToolsQuery();
  const { data: mcpServers = [] } = useGetMcpServersQuery();
  const { data: skills = [] } = useGetCompanySkillsQuery();

  // Mutations
  const [updateCompanyWorkflow] = useUpdateCompanyWorkflowMutation();
  const [updateProjectWorkflow] = useUpdateProjectWorkflowMutation();
  const [createCompanyStep] = useCreateCompanyStepMutation();
  const [createProjectStep] = useCreateStepMutation();
  const [updateCompanyStep] = useUpdateCompanyStepMutation();
  const [updateProjectStep] = useUpdateStepMutation();
  const [deleteCompanyStep] = useDeleteCompanyStepMutation();
  const [deleteProjectStep] = useDeleteStepMutation();
  const [reorderCompanySteps] = useReorderCompanyStepsMutation();
  const [reorderProjectSteps] = useReorderStepsMutation();
  const [duplicateToProject] = useDuplicateWorkflowToProjectMutation();

  const readOnly = !!(routeProjectId && isCompanyScope);

  const handleCopyToProject = useCallback(async () => {
    if (!routeProjectId || !workflow) return;
    try {
      const copy = await duplicateToProject({ projectId: Number(routeProjectId), id: workflow.id }).unwrap();
      enqueueSnackbar(`Copied "${workflow.name}" to project`, { variant: 'success' });
      navigate({
        to: Routes.frontend.projectWorkflowBuilderPath(routeProjectId, String(copy.id)),
      });
    } catch {
      enqueueSnackbar('Failed to copy workflow', { variant: 'error' });
    }
  }, [routeProjectId, workflow, duplicateToProject, enqueueSnackbar, navigate]);

  // Scope-aware helpers
  const updateWorkflow = useCallback(
    async (data: { name?: string; description?: string }) => {
      if (!workflow) return;
      try {
        if (isCompanyScope) {
          await updateCompanyWorkflow({ id: workflow.id, ...data }).unwrap();
        } else {
          await updateProjectWorkflow({ projectId: projectId!, id: workflow.id, ...data }).unwrap();
        }
      } catch {
        enqueueSnackbar('Failed to update workflow', { variant: 'error' });
      }
    },
    [workflow, isCompanyScope, projectId, updateCompanyWorkflow, updateProjectWorkflow, enqueueSnackbar],
  );

  const updateStep = useCallback(
    async (stepId: number, data: Omit<Partial<UpdateStepRequest>, 'id'>) => {
      if (!workflow) return;
      try {
        if (isCompanyScope) {
          await updateCompanyStep({ workflowId, id: stepId, ...data }).unwrap();
        } else {
          await updateProjectStep({
            projectId: projectId!,
            workflowId,
            id: stepId,
            ...data,
          }).unwrap();
        }
      } catch {
        enqueueSnackbar('Failed to update step', { variant: 'error' });
      }
    },
    [workflow, isCompanyScope, projectId, workflowId, updateCompanyStep, updateProjectStep, enqueueSnackbar],
  );

  // Debounced saves
  const debouncedUpdateWorkflow = useDebouncedCallback((data: { name?: string; description?: string }) => {
    updateWorkflow(data);
  }, 500);

  const debouncedUpdateStep = useDebouncedCallback((stepId: number, data: Omit<Partial<UpdateStepRequest>, 'id'>) => {
    updateStep(stepId, data);
  }, 500);

  // Handlers
  const handleNameChange = (value: string) => {
    setWorkflowName(value);
    debouncedUpdateWorkflow({ name: value });
  };

  const handleDescriptionChange = (value: string) => {
    setWorkflowDescription(value);
    debouncedUpdateWorkflow({ description: value });
  };

  const handleAddStep = async () => {
    if (!workflow) return;
    const nextPosition = steps.length + 1;
    try {
      let newStep: Step;
      if (isCompanyScope) {
        newStep = await createCompanyStep({
          workflowId,
          name: `Step ${nextPosition}`,
          position: nextPosition,
        }).unwrap();
      } else {
        newStep = await createProjectStep({
          projectId: projectId!,
          workflowId,
          name: `Step ${nextPosition}`,
          position: nextPosition,
        }).unwrap();
      }
      setSelectedStepId(newStep.id);
    } catch {
      enqueueSnackbar('Failed to create step', { variant: 'error' });
    }
  };

  const handleDeleteStep = async () => {
    if (!deleteStepId || !workflow) return;
    try {
      if (isCompanyScope) {
        await deleteCompanyStep({ workflowId, id: deleteStepId }).unwrap();
      } else {
        await deleteProjectStep({ projectId: projectId!, workflowId, id: deleteStepId }).unwrap();
      }
      if (selectedStepId === deleteStepId) setSelectedStepId(null);
    } catch {
      enqueueSnackbar('Failed to delete step', { variant: 'error' });
    }
    setDeleteStepId(null);
  };

  const handleReorder = async (stepId: number, direction: 'up' | 'down') => {
    const idx = steps.findIndex((s) => s.id === stepId);
    if (idx < 0) return;
    const swapIdx = direction === 'up' ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= steps.length) return;

    const positions: Record<number, number> = {};
    positions[steps[idx].id] = steps[swapIdx].position;
    positions[steps[swapIdx].id] = steps[idx].position;

    try {
      if (isCompanyScope) {
        await reorderCompanySteps({ workflowId, positions }).unwrap();
      } else {
        await reorderProjectSteps({ projectId: projectId!, workflowId, positions }).unwrap();
      }
    } catch {
      enqueueSnackbar('Failed to reorder steps', { variant: 'error' });
    }
  };

  const handleStepFieldChange = (
    field: keyof Omit<UpdateStepRequest, 'id'>,
    value: UpdateStepRequest[keyof UpdateStepRequest],
    immediate = false,
  ) => {
    if (!selectedStep) return;
    const payload = { [field]: value } as Omit<Partial<UpdateStepRequest>, 'id'>;
    if (immediate) {
      updateStep(selectedStep.id, payload);
    } else {
      debouncedUpdateStep(selectedStep.id, payload);
    }
  };

  const handleBack = () => {
    if (routeProjectId) {
      navigate({ to: Routes.frontend.companyProjectTabPath(routeProjectId, 'workflows') });
    } else if (isCompanyScope) {
      navigate({ to: Routes.frontend.companyWorkflowsPath });
    } else if (projectId) {
      navigate({ to: Routes.frontend.companyProjectTabPath(String(projectId), 'workflows') });
    }
  };

  // Sub-steps handlers
  const buildSubStepAttrs = (step: Step): SubStepAttribute[] =>
    step.subSteps.map((ss) => ({
      id: ss.id,
      name: ss.name,
      position: ss.position,
      description: ss.description || undefined,
      instructions: ss.instructions || undefined,
      required: ss.required,
    }));

  const handleAddSubStep = () => {
    if (!selectedStep) return;
    const attrs = buildSubStepAttrs(selectedStep);
    attrs.push({ name: `Sub-step ${attrs.length + 1}`, position: attrs.length + 1, required: true });
    updateStep(selectedStep.id, { subStepsAttributes: attrs });
  };

  const handleDeleteSubStep = (subStepId: number) => {
    if (!selectedStep) return;
    const attrs = buildSubStepAttrs(selectedStep).map((a) => (a.id === subStepId ? { ...a, _destroy: true } : a));
    updateStep(selectedStep.id, { subStepsAttributes: attrs });
  };

  const handleUpdateSubStep = (subStepId: number, field: string, value: unknown) => {
    if (!selectedStep) return;
    const attrs = buildSubStepAttrs(selectedStep).map((a) => (a.id === subStepId ? { ...a, [field]: value } : a));
    debouncedUpdateStep(selectedStep.id, { subStepsAttributes: attrs });
  };

  const handleReorderSubStep = (subStepId: number, direction: 'up' | 'down') => {
    if (!selectedStep) return;
    const sorted = [...selectedStep.subSteps].sort((a, b) => a.position - b.position);
    const idx = sorted.findIndex((ss) => ss.id === subStepId);
    if (idx < 0) return;
    const swapIdx = direction === 'up' ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= sorted.length) return;

    const attrs = buildSubStepAttrs(selectedStep);
    const attrIdx = attrs.findIndex((a) => a.id === subStepId);
    const attrSwap = attrs.findIndex((a) => a.id === sorted[swapIdx].id);
    if (attrIdx >= 0 && attrSwap >= 0) {
      const tmpPos = attrs[attrIdx].position;
      attrs[attrIdx].position = attrs[attrSwap].position;
      attrs[attrSwap].position = tmpPos;
    }
    updateStep(selectedStep.id, { subStepsAttributes: attrs });
  };

  // Asset specs handlers
  const handleAddAssetSpec = (field: 'inputAssetSpecs' | 'outputAssetSpecs') => {
    if (!selectedStep) return;
    const current = selectedStep[field] || [];
    const newSpec: AssetSpec = { name: '', assetType: 'file', required: true };
    updateStep(selectedStep.id, { [field]: [...current, newSpec] });
  };

  const handleRemoveAssetSpec = (field: 'inputAssetSpecs' | 'outputAssetSpecs', index: number) => {
    if (!selectedStep) return;
    const current = [...(selectedStep[field] || [])];
    current.splice(index, 1);
    updateStep(selectedStep.id, { [field]: current });
  };

  const handleUpdateAssetSpec = (
    field: 'inputAssetSpecs' | 'outputAssetSpecs',
    index: number,
    key: string,
    value: unknown,
  ) => {
    if (!selectedStep) return;
    const current = [...(selectedStep[field] || [])];
    current[index] = { ...current[index], [key]: value };
    debouncedUpdateStep(selectedStep.id, { [field]: current });
  };

  // Loading / error states
  if (workflowLoading) {
    return (
      <Box sx={styles.loadingContainer}>
        <CircularProgress />
      </Box>
    );
  }

  const backPath = routeProjectId
    ? Routes.frontend.companyProjectTabPath(routeProjectId, 'workflows')
    : Routes.frontend.companyWorkflowsPath;

  if (!workflowId || isNaN(workflowId)) {
    return (
      <Box sx={styles.notFound}>
        <Typography variant="h5" color="text.secondary">
          Invalid workflow ID
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 2 }}>
          Create a workflow first from the Workflows page, then open it to configure.
        </Typography>
        <Button variant="outlined" onClick={() => navigate({ to: backPath })}>
          Go to Workflows
        </Button>
      </Box>
    );
  }

  if (workflowError || !workflow) {
    return (
      <Box sx={styles.notFound}>
        <Typography variant="h5" color="text.secondary">
          Workflow not found
        </Typography>
        <Button variant="outlined" onClick={() => navigate({ to: backPath })}>
          Go back
        </Button>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      {/* Sidebar */}
      <Box sx={styles.sidebar}>
        <Box sx={styles.sidebarHeader}>
          <IconButton size="small" onClick={handleBack}>
            <ArrowBackIcon fontSize="small" />
          </IconButton>
          <Box>
            <Typography sx={{ fontSize: '16px', fontWeight: 600 }}>Steps</Typography>
            <Typography sx={{ fontSize: '12px', color: 'text.secondary' }}>
              {steps.length} step{steps.length !== 1 ? 's' : ''}
            </Typography>
          </Box>
        </Box>

        <Box sx={styles.stepsList}>
          {steps.map((step, idx) => {
            const agent = agents.find((a: Agent) => a.id === step.agentId);
            return (
              <Box
                key={step.id}
                sx={{ ...styles.stepItem, ...(selectedStepId === step.id ? styles.stepItemActive : {}) }}
                onClick={() => setSelectedStepId(step.id)}
              >
                <Box sx={styles.stepInfo}>
                  <Typography sx={{ fontSize: '11px', color: 'text.secondary' }}>#{step.position}</Typography>
                  <Typography
                    sx={{
                      fontSize: '13px',
                      fontWeight: 500,
                      whiteSpace: 'nowrap',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                    }}
                  >
                    {step.name}
                  </Typography>
                  <Typography sx={{ fontSize: '11px', color: 'text.secondary' }}>
                    {agent?.title || 'No agent'}
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mt: 0.5 }}>
                    {step.allowNonInteractive && (
                      <Chip label="Auto-run" size="small" sx={{ height: 18, fontSize: '10px' }} />
                    )}
                    {(step.dependsOnStepIds ?? []).length === 0 ? (
                      <Chip label="Root" size="small" variant="outlined" sx={{ height: 18, fontSize: '10px' }} />
                    ) : (
                      <Chip
                        label={`after: ${(step.dependsOnStepIds ?? [])
                          .map((id: number) => steps.find((s) => s.id === id)?.name ?? `#${id}`)
                          .join(', ')}`}
                        size="small"
                        variant="outlined"
                        color="secondary"
                        sx={{ height: 18, fontSize: '10px', maxWidth: 180 }}
                      />
                    )}
                  </Box>
                </Box>
                {!readOnly && (
                  <Box sx={styles.stepActions}>
                    <IconButton
                      size="small"
                      disabled={idx === 0}
                      onClick={(e) => {
                        e.stopPropagation();
                        handleReorder(step.id, 'up');
                      }}
                    >
                      <ArrowUpwardIcon sx={{ fontSize: 14 }} />
                    </IconButton>
                    <IconButton
                      size="small"
                      disabled={idx === steps.length - 1}
                      onClick={(e) => {
                        e.stopPropagation();
                        handleReorder(step.id, 'down');
                      }}
                    >
                      <ArrowDownwardIcon sx={{ fontSize: 14 }} />
                    </IconButton>
                  </Box>
                )}
              </Box>
            );
          })}
        </Box>

        {!readOnly && (
          <Button variant="outlined" sx={{ m: '12px', textTransform: 'none' }} onClick={handleAddStep}>
            + Add Step
          </Button>
        )}
      </Box>

      {/* Main */}
      <Box sx={styles.main}>
        {readOnly && (
          <Box
            sx={{
              px: 3,
              py: 1.5,
              backgroundColor: 'info.main',
              color: 'info.contrastText',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
            }}
          >
            <Typography variant="body2">
              This is a company-level workflow. Copy it to your project to customize.
            </Typography>
            <Button
              size="small"
              variant="contained"
              color="inherit"
              sx={{ color: 'info.main' }}
              onClick={handleCopyToProject}
            >
              Copy & Configure
            </Button>
          </Box>
        )}

        {/* Header */}
        <Box sx={styles.header}>
          <Box sx={styles.headerLeft}>
            <TextField
              value={workflowName}
              onChange={(e) => handleNameChange(e.target.value)}
              variant="standard"
              disabled={readOnly}
              InputProps={{ disableUnderline: true, sx: { fontSize: '22px', fontWeight: 600 } }}
              fullWidth
            />
            <TextField
              value={workflowDescription}
              onChange={(e) => handleDescriptionChange(e.target.value)}
              variant="standard"
              disabled={readOnly}
              InputProps={{ disableUnderline: true, sx: { fontSize: '13px', color: 'text.secondary' } }}
              placeholder="Add a description..."
              fullWidth
            />
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, ml: 2 }}>
            {!readOnly && (projectId || routeProjectId) && (
              <Button
                variant="contained"
                size="small"
                startIcon={<PlayArrowIcon />}
                onClick={() => setRunModalOpen(true)}
              >
                Run
              </Button>
            )}
            <Chip
              label={workflow.scopeIndicator}
              size="small"
              color={isCompanyScope ? 'primary' : 'default'}
              variant="outlined"
            />
          </Box>
        </Box>

        {/* Content */}
        <Box sx={styles.content}>
          {selectedStep ? (
            <StepDetailPanel
              step={selectedStep}
              allSteps={steps}
              agents={agents}
              tools={tools}
              mcpServers={mcpServers}
              skills={skills}
              onFieldChange={handleStepFieldChange}
              onDelete={() => setDeleteStepId(selectedStep.id)}
              onAddSubStep={handleAddSubStep}
              onDeleteSubStep={handleDeleteSubStep}
              onUpdateSubStep={handleUpdateSubStep}
              onReorderSubStep={handleReorderSubStep}
              onAddAssetSpec={handleAddAssetSpec}
              onRemoveAssetSpec={handleRemoveAssetSpec}
              onUpdateAssetSpec={handleUpdateAssetSpec}
              readOnly={readOnly}
            />
          ) : (
            <Box sx={styles.emptyState}>
              <Typography sx={{ fontSize: '48px', mb: 2 }}>&#128736;</Typography>
              <Typography sx={{ fontSize: '18px', fontWeight: 600, mb: 1 }}>
                {steps.length === 0 ? 'No steps yet' : 'Select a step to configure'}
              </Typography>
              <Typography sx={{ fontSize: '14px', color: 'text.secondary', mb: 3 }}>
                {steps.length === 0
                  ? 'Add your first workflow step to get started'
                  : 'Click on a step in the sidebar to edit its configuration'}
              </Typography>
              {steps.length === 0 && (
                <Button variant="contained" onClick={handleAddStep}>
                  Add First Step
                </Button>
              )}
            </Box>
          )}
        </Box>
      </Box>

      {/* Delete confirmation */}
      <Dialog open={!!deleteStepId} onClose={() => setDeleteStepId(null)}>
        <DialogTitle>Delete Step</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Are you sure you want to delete this step? This action cannot be undone.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteStepId(null)}>Cancel</Button>
          <Button color="error" onClick={handleDeleteStep}>
            Delete
          </Button>
        </DialogActions>
      </Dialog>

      {(projectId || routeProjectId) && (
        <RunWorkflowModal
          open={runModalOpen}
          workflow={workflow ? { id: workflow.id, name: workflow.name, description: workflow.description } : null}
          projectId={Number(projectId || routeProjectId)}
          onClose={() => setRunModalOpen(false)}
        />
      )}
    </Box>
  );
};

// --- Step Detail Panel ---

interface StepDetailPanelProps {
  step: Step;
  allSteps: Step[];
  agents: Agent[];
  tools: Tool[];
  mcpServers: McpServer[];
  skills: Skill[];
  onFieldChange: (
    field: keyof Omit<UpdateStepRequest, 'id'>,
    value: UpdateStepRequest[keyof UpdateStepRequest],
    immediate?: boolean,
  ) => void;
  onDelete: () => void;
  onAddSubStep: () => void;
  onDeleteSubStep: (id: number) => void;
  onUpdateSubStep: (id: number, field: string, value: unknown) => void;
  onReorderSubStep: (id: number, direction: 'up' | 'down') => void;
  onAddAssetSpec: (field: 'inputAssetSpecs' | 'outputAssetSpecs') => void;
  onRemoveAssetSpec: (field: 'inputAssetSpecs' | 'outputAssetSpecs', index: number) => void;
  onUpdateAssetSpec: (
    field: 'inputAssetSpecs' | 'outputAssetSpecs',
    index: number,
    key: string,
    value: unknown,
  ) => void;
  readOnly?: boolean;
}

function StepDetailPanel({
  step,
  allSteps,
  agents,
  tools,
  mcpServers,
  skills,
  onFieldChange,
  onDelete,
  onAddSubStep,
  onDeleteSubStep,
  onUpdateSubStep,
  onReorderSubStep,
  onAddAssetSpec,
  onRemoveAssetSpec,
  onUpdateAssetSpec,
  readOnly = false,
}: StepDetailPanelProps) {
  const [localName, setLocalName] = useState(step.name);
  const [localDesc, setLocalDesc] = useState(step.description || '');
  const [localInstructions, setLocalInstructions] = useState(step.instructions || '');

  useEffect(() => {
    setLocalName(step.name);
    setLocalDesc(step.description || '');
    setLocalInstructions(step.instructions || '');
  }, [step.id, step.name, step.description, step.instructions]);

  const selectedTools = useMemo(() => tools.filter((t: Tool) => step.toolIds?.includes(t.id)), [tools, step.toolIds]);
  const selectedMcpServers = useMemo(
    () => mcpServers.filter((s: McpServer) => step.mcpServerIds?.includes(s.id)),
    [mcpServers, step.mcpServerIds],
  );
  const selectedSkills = useMemo(
    () => skills.filter((s: Skill) => step.skillIds?.includes(s.id)),
    [skills, step.skillIds],
  );
  return (
    <Box sx={{ ...styles.panel, ...(readOnly ? { pointerEvents: 'none', opacity: 0.7 } : {}) }}>
      {/* Header */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography sx={{ fontSize: '18px', fontWeight: 600 }}>Step #{step.position}</Typography>
        {!readOnly && (
          <Tooltip title="Delete step">
            <IconButton size="small" color="error" onClick={onDelete}>
              <DeleteIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        )}
      </Box>

      {/* Configuration */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Configuration</Typography>

        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Name</Typography>
          <TextField
            fullWidth
            size="small"
            value={localName}
            onChange={(e) => {
              setLocalName(e.target.value);
              onFieldChange('name', e.target.value);
            }}
          />
        </Box>

        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Description</Typography>
          <TextField
            fullWidth
            size="small"
            multiline
            rows={2}
            value={localDesc}
            onChange={(e) => {
              setLocalDesc(e.target.value);
              onFieldChange('description', e.target.value);
            }}
          />
        </Box>

        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Instructions</Typography>
          <TextField
            fullWidth
            size="small"
            multiline
            rows={8}
            value={localInstructions}
            onChange={(e) => {
              setLocalInstructions(e.target.value);
              onFieldChange('instructions', e.target.value);
            }}
            placeholder="Enter step instructions... Use {{artifact_name}} for variable references."
          />
        </Box>

        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Agent</Typography>
          <Select
            fullWidth
            size="small"
            displayEmpty
            value={step.agentId ?? ''}
            onChange={(e) => onFieldChange('agentId', e.target.value === '' ? null : Number(e.target.value), true)}
          >
            <MenuItem value="">
              <em>No agent</em>
            </MenuItem>
            {agents.map((a: Agent) => (
              <MenuItem key={a.id} value={a.id}>
                {a.title || a.name}
              </MenuItem>
            ))}
          </Select>
        </Box>
      </Box>

      <Divider sx={{ my: 2 }} />

      {/* Execution */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Execution</Typography>

        <Box sx={styles.formField}>
          <FormControlLabel
            control={
              <Switch
                checked={step.allowNonInteractive}
                onChange={(e) => onFieldChange('allowNonInteractive', e.target.checked, true)}
              />
            }
            label="Auto-run available (skip user approval in non-interactive/mixed modes)"
          />
        </Box>

        <Box sx={{ display: 'flex', gap: 2 }}>
          <Box sx={{ ...styles.formField, flex: 1 }}>
            <Typography sx={styles.label}>Skip Policy</Typography>
            <Select
              fullWidth
              size="small"
              value={step.skipPolicy}
              onChange={(e) => onFieldChange('skipPolicy', e.target.value, true)}
            >
              {SKIP_POLICY_OPTIONS.map((o) => (
                <MenuItem key={o.value} value={o.value}>
                  {o.label}
                </MenuItem>
              ))}
            </Select>
          </Box>

          <Box sx={{ ...styles.formField, flex: 1 }}>
            <Typography sx={styles.label}>On Failure</Typography>
            <Select
              fullWidth
              size="small"
              value={step.onFailure}
              onChange={(e) => onFieldChange('onFailure', e.target.value, true)}
            >
              {ON_FAILURE_OPTIONS.map((o) => (
                <MenuItem key={o.value} value={o.value}>
                  {o.label}
                </MenuItem>
              ))}
            </Select>
          </Box>

          {step.onFailure === 'retry' && (
            <Box sx={{ ...styles.formField, width: 120 }}>
              <Typography sx={styles.label}>Max Retries</Typography>
              <TextField
                fullWidth
                size="small"
                type="number"
                value={step.maxRetries}
                onChange={(e) => onFieldChange('maxRetries', Number(e.target.value), true)}
                inputProps={{ min: 0, max: 10 }}
              />
            </Box>
          )}
        </Box>
      </Box>

      <Divider sx={{ my: 2 }} />

      {/* Tools */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Tools</Typography>
        <Autocomplete
          multiple
          size="small"
          options={tools}
          getOptionLabel={(t: Tool) => t.displayName || t.name}
          value={selectedTools}
          onChange={(_, newValue) =>
            onFieldChange(
              'toolIds',
              newValue.map((t: Tool) => t.id),
              true,
            )
          }
          renderInput={(params) => <TextField {...params} placeholder="Select tools..." />}
          isOptionEqualToValue={(opt, val) => opt.id === val.id}
        />
      </Box>

      {/* MCP Servers */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>MCP Servers</Typography>
        <Autocomplete
          multiple
          size="small"
          options={mcpServers}
          getOptionLabel={(s: McpServer) => s.displayName || s.name}
          value={selectedMcpServers}
          onChange={(_, newValue) =>
            onFieldChange(
              'mcpServerIds',
              newValue.map((s: McpServer) => s.id),
              true,
            )
          }
          renderInput={(params) => <TextField {...params} placeholder="Select MCP servers..." />}
          isOptionEqualToValue={(opt, val) => opt.id === val.id}
        />
      </Box>

      {/* Skills */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Skills</Typography>
        <Autocomplete
          multiple
          size="small"
          options={skills}
          getOptionLabel={(s: Skill) => s.name}
          value={selectedSkills}
          onChange={(_, newValue) =>
            onFieldChange(
              'skillIds',
              newValue.map((s: Skill) => s.id),
              true,
            )
          }
          renderInput={(params) => <TextField {...params} placeholder="Select skills..." />}
          isOptionEqualToValue={(opt, val) => opt.id === val.id}
        />
      </Box>

      {/* Mount Repositories */}
      <Box sx={styles.formField}>
        <FormControlLabel
          control={
            <Switch
              checked={step.mountRepositories ?? true}
              onChange={(e) => onFieldChange('mountRepositories', e.target.checked, true)}
            />
          }
          label="Mount repositories on this step"
        />
        <Typography variant="caption" color="text.secondary" sx={{ ml: 4 }}>
          Repositories are selected when running the workflow
        </Typography>
      </Box>

      {/* Dependencies */}
      <Box sx={{ mb: 2, mt: 2 }}>
        <Typography sx={styles.sectionTitle}>Dependencies</Typography>
        <Autocomplete
          multiple
          size="small"
          options={allSteps.filter((s) => s.id !== step.id)}
          getOptionLabel={(s: Step) => `${s.position}. ${s.name}`}
          value={allSteps.filter((s) => (step.dependsOnStepIds ?? []).includes(s.id))}
          onChange={(_, newValue) =>
            onFieldChange(
              'dependsOnStepIds',
              newValue.map((s: Step) => s.id),
              true,
            )
          }
          renderInput={(params) => (
            <TextField {...params} placeholder="Select steps this step depends on..." />
          )}
          isOptionEqualToValue={(opt, val) => opt.id === val.id}
          disabled={readOnly}
        />
        <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
          {(step.dependsOnStepIds ?? []).length === 0
            ? 'No dependencies — this step can run in parallel with other root steps'
            : 'This step will start after all selected steps complete'}
        </Typography>
      </Box>

      <Divider sx={{ my: 2 }} />

      {/* Sub-steps */}
      <Accordion defaultExpanded={step.subSteps?.length > 0}>
        <AccordionSummary expandIcon={<ExpandMoreIcon />}>
          <Typography sx={styles.sectionTitle}>Sub-steps ({step.subSteps?.length || 0})</Typography>
        </AccordionSummary>
        <AccordionDetails>
          {[...(step.subSteps || [])]
            .sort((a, b) => a.position - b.position)
            .map((ss, idx, arr) => (
              <Box
                key={ss.id}
                sx={{
                  p: 1.5,
                  mb: 1.5,
                  border: '1px solid',
                  borderColor: 'divider',
                  borderRadius: '6px',
                  backgroundColor: 'background.elevated',
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  <Typography sx={{ fontSize: '12px', color: 'text.secondary', fontWeight: 600, width: 28 }}>
                    #{ss.position}
                  </Typography>
                  <TextField
                    size="small"
                    sx={{ flex: 1 }}
                    defaultValue={ss.name}
                    placeholder="Sub-step name"
                    onBlur={(e) => onUpdateSubStep(ss.id, 'name', e.target.value)}
                  />
                  <FormControlLabel
                    control={
                      <Switch
                        size="small"
                        checked={ss.required}
                        onChange={(e) => onUpdateSubStep(ss.id, 'required', e.target.checked)}
                      />
                    }
                    label={<Typography sx={{ fontSize: '12px' }}>Required</Typography>}
                  />
                  <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                    <IconButton size="small" disabled={idx === 0} onClick={() => onReorderSubStep(ss.id, 'up')}>
                      <ArrowUpwardIcon sx={{ fontSize: 14 }} />
                    </IconButton>
                    <IconButton
                      size="small"
                      disabled={idx === arr.length - 1}
                      onClick={() => onReorderSubStep(ss.id, 'down')}
                    >
                      <ArrowDownwardIcon sx={{ fontSize: 14 }} />
                    </IconButton>
                  </Box>
                  <IconButton size="small" color="error" onClick={() => onDeleteSubStep(ss.id)}>
                    <DeleteIcon sx={{ fontSize: 16 }} />
                  </IconButton>
                </Box>
                <TextField
                  size="small"
                  fullWidth
                  placeholder="Description"
                  defaultValue={ss.description || ''}
                  onBlur={(e) => onUpdateSubStep(ss.id, 'description', e.target.value)}
                  sx={{ mb: 1 }}
                />
                <TextField
                  size="small"
                  fullWidth
                  multiline
                  rows={3}
                  placeholder="Instructions"
                  defaultValue={ss.instructions || ''}
                  onBlur={(e) => onUpdateSubStep(ss.id, 'instructions', e.target.value)}
                />
              </Box>
            ))}
          <Button size="small" sx={{ mt: 1, textTransform: 'none' }} onClick={onAddSubStep}>
            + Add Sub-step
          </Button>
        </AccordionDetails>
      </Accordion>

      <Divider sx={{ my: 2 }} />

      {/* Asset Specs */}
      <AssetSpecsSection
        title="Input Asset Specs"
        field="inputAssetSpecs"
        specs={step.inputAssetSpecs || []}
        onAdd={onAddAssetSpec}
        onRemove={onRemoveAssetSpec}
        onUpdate={onUpdateAssetSpec}
        showNamePattern={false}
      />

      <AssetSpecsSection
        title="Output Asset Specs"
        field="outputAssetSpecs"
        specs={step.outputAssetSpecs || []}
        onAdd={onAddAssetSpec}
        onRemove={onRemoveAssetSpec}
        onUpdate={onUpdateAssetSpec}
        showNamePattern
      />
    </Box>
  );
}

// --- Asset Specs Section ---

interface AssetSpecsSectionProps {
  title: string;
  field: 'inputAssetSpecs' | 'outputAssetSpecs';
  specs: AssetSpec[];
  onAdd: (field: 'inputAssetSpecs' | 'outputAssetSpecs') => void;
  onRemove: (field: 'inputAssetSpecs' | 'outputAssetSpecs', index: number) => void;
  onUpdate: (field: 'inputAssetSpecs' | 'outputAssetSpecs', index: number, key: string, value: unknown) => void;
  showNamePattern: boolean;
}

function AssetSpecsSection({
  title,
  field,
  specs,
  onAdd,
  onRemove,
  onUpdate,
  showNamePattern,
}: AssetSpecsSectionProps) {
  return (
    <Box sx={styles.section}>
      <Typography sx={styles.sectionTitle}>{title}</Typography>
      {specs.map((spec, idx) => (
        <Box key={idx} sx={styles.assetSpecRow}>
          <TextField
            size="small"
            placeholder="Name"
            defaultValue={spec.name}
            sx={{ flex: 1 }}
            onBlur={(e) => onUpdate(field, idx, 'name', e.target.value)}
          />
          <TextField
            size="small"
            placeholder="Type"
            defaultValue={spec.assetType}
            sx={{ width: 120 }}
            onBlur={(e) => onUpdate(field, idx, 'assetType', e.target.value)}
          />
          {showNamePattern && (
            <TextField
              size="small"
              placeholder="Pattern"
              defaultValue={spec.namePattern || ''}
              sx={{ width: 120 }}
              onBlur={(e) => onUpdate(field, idx, 'namePattern', e.target.value)}
            />
          )}
          <FormControlLabel
            control={
              <Switch
                size="small"
                checked={spec.required}
                onChange={(e) => onUpdate(field, idx, 'required', e.target.checked)}
              />
            }
            label={<Typography sx={{ fontSize: '11px' }}>Req</Typography>}
          />
          <IconButton size="small" color="error" onClick={() => onRemove(field, idx)}>
            <DeleteIcon sx={{ fontSize: 16 }} />
          </IconButton>
        </Box>
      ))}
      <Button size="small" sx={{ textTransform: 'none' }} onClick={() => onAdd(field)}>
        + Add
      </Button>
    </Box>
  );
}

export default WorkflowBuilderPage;
