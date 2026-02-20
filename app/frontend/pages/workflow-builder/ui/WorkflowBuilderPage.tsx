import { Box, Button, IconButton, MenuItem, Select, TextField, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

import { Routes } from 'shared/routes';

interface IWorkflowStep {
  id: string;
  name: string;
  agent: string;
  prompt: string;
  assets: string[];
  dependsOn?: string[];
}

interface IWorkflow {
  id: string;
  name: string;
  description: string;
  steps: IWorkflowStep[];
}

const AGENT_OPTIONS = [
  { value: 'claude_code', label: 'Claude Code', color: '#D97706' },
  { value: 'cursor_cli', label: 'Cursor CLI', color: '#7C3AED' },
  { value: 'codex', label: 'OpenAI Codex', color: '#10A37F' },
  { value: 'gemini_cli', label: 'Gemini CLI', color: '#3B82F6' },
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
    backgroundColor: 'background.paper',
    borderRight: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    flexDirection: 'column',
  },
  sidebarHeader: {
    padding: '20px',
    borderBottom: '1px solid',
    borderColor: 'divider',
  },
  sidebarTitle: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
  },
  stepsList: {
    flex: 1,
    overflow: 'auto',
    padding: '12px',
  },
  stepItem: {
    padding: '12px',
    marginBottom: '8px',
    backgroundColor: 'background.elevated',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
    },
  },
  stepItemActive: {
    borderColor: 'primary.main',
    backgroundColor: 'rgba(71, 133, 255, 0.08)',
  },
  stepNumber: {
    fontSize: '12px',
    color: 'text.secondary',
    marginBottom: '4px',
  },
  stepName: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '4px',
  },
  stepAgent: {
    fontSize: '12px',
    color: 'text.secondary',
  },
  addStepButton: {
    margin: '12px',
    textTransform: 'none',
  },
  main: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  header: {
    padding: '20px 32px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerLeft: {
    flex: 1,
  },
  workflowName: {
    fontSize: '24px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
  },
  workflowDescription: {
    fontSize: '14px',
    color: 'text.secondary',
  },
  headerActions: {
    display: 'flex',
    gap: '12px',
  },
  actionButton: {
    textTransform: 'none',
    minWidth: '100px',
  },
  content: {
    flex: 1,
    overflow: 'auto',
    padding: '32px',
  },
  panel: {
    maxWidth: '800px',
    margin: '0 auto',
  },
  section: {
    marginBottom: '32px',
  },
  sectionTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
  },
  formField: {
    marginBottom: '16px',
  },
  label: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '8px',
  },
  input: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.paper',
    },
  },
  assetsList: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '8px',
    marginTop: '8px',
  },
  assetChip: {
    padding: '6px 12px',
    backgroundColor: 'background.elevated',
    borderRadius: '6px',
    border: '1px solid',
    borderColor: 'divider',
    fontSize: '13px',
    color: 'text.primary',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  removeButton: {
    width: '16px',
    height: '16px',
    padding: 0,
    minWidth: 'unset',
    fontSize: '12px',
    color: 'text.secondary',
    '&:hover': {
      color: 'error.main',
    },
  },
  emptyState: {
    textAlign: 'center',
    padding: '64px 32px',
  },
  emptyIcon: {
    fontSize: '48px',
    marginBottom: '16px',
  },
  emptyTitle: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '8px',
  },
  emptyDescription: {
    fontSize: '14px',
    color: 'text.secondary',
    marginBottom: '24px',
  },
  agentSelect: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.paper',
    },
  },
  colorDot: {
    width: '12px',
    height: '12px',
    borderRadius: '50%',
    marginRight: '8px',
    display: 'inline-block',
  },
} satisfies Record<string, SxProps<Theme>>;

const WorkflowBuilderPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const params = useParams({ strict: false });
  const workflowId = (params as { workflowId?: string }).workflowId || 'new';

  const [workflow, setWorkflow] = useState<IWorkflow>({
    id: workflowId || 'new',
    name: 'New Workflow',
    description: 'Add a description for your workflow',
    steps: [],
  });

  const [selectedStepId, setSelectedStepId] = useState<string | null>(null);
  const [assetInput, setAssetInput] = useState('');

  const selectedStep = workflow.steps.find((s) => s.id === selectedStepId);

  const handleAddStep = () => {
    const newStep: IWorkflowStep = {
      id: `step-${Date.now()}`,
      name: `Step ${workflow.steps.length + 1}`,
      agent: 'claude_code',
      prompt: '',
      assets: [],
    };
    setWorkflow((prev) => ({ ...prev, steps: [...prev.steps, newStep] }));
    setSelectedStepId(newStep.id);
  };

  const handleUpdateStep = (stepId: string, updates: Partial<IWorkflowStep>) => {
    setWorkflow((prev) => ({
      ...prev,
      steps: prev.steps.map((step) => (step.id === stepId ? { ...step, ...updates } : step)),
    }));
  };

  const handleDeleteStep = (stepId: string) => {
    setWorkflow((prev) => ({
      ...prev,
      steps: prev.steps.filter((step) => step.id !== stepId),
    }));
    if (selectedStepId === stepId) {
      setSelectedStepId(null);
    }
  };

  const handleAddAsset = () => {
    if (!selectedStep || !assetInput.trim()) return;
    handleUpdateStep(selectedStep.id, {
      assets: [...selectedStep.assets, assetInput.trim()],
    });
    setAssetInput('');
  };

  const handleRemoveAsset = (asset: string) => {
    if (!selectedStep) return;
    handleUpdateStep(selectedStep.id, {
      assets: selectedStep.assets.filter((a) => a !== asset),
    });
  };

  const handleSave = () => {
    enqueueSnackbar('Workflow saved successfully', { variant: 'success' });
  };

  const handleTest = () => {
    enqueueSnackbar('Starting test run...', { variant: 'info' });
  };

  return (
    <Box sx={styles.root}>
      {/* Sidebar - Steps List */}
      <Box sx={styles.sidebar}>
        <Box sx={styles.sidebarHeader}>
          <Typography sx={styles.sidebarTitle}>Workflow Steps</Typography>
          <Typography sx={{ fontSize: '12px', color: 'text.secondary', marginTop: '4px' }}>
            {workflow.steps.length} step{workflow.steps.length !== 1 ? 's' : ''}
          </Typography>
        </Box>

        <Box sx={styles.stepsList}>
          {workflow.steps.map((step, index) => {
            const agent = AGENT_OPTIONS.find((a) => a.value === step.agent);
            return (
              <Box
                key={step.id}
                sx={{
                  ...styles.stepItem,
                  ...(selectedStepId === step.id ? styles.stepItemActive : {}),
                }}
                onClick={() => setSelectedStepId(step.id)}
              >
                <Typography sx={styles.stepNumber}>Step {index + 1}</Typography>
                <Typography sx={styles.stepName}>{step.name}</Typography>
                <Typography sx={styles.stepAgent}>
                  <span style={{ ...styles.colorDot, backgroundColor: agent?.color }} />
                  {agent?.label}
                </Typography>
              </Box>
            );
          })}
        </Box>

        <Button variant="outlined" sx={styles.addStepButton} onClick={handleAddStep}>
          + Add Step
        </Button>
      </Box>

      {/* Main Content */}
      <Box sx={styles.main}>
        {/* Header */}
        <Box sx={styles.header}>
          <Box sx={styles.headerLeft}>
            <TextField
              value={workflow.name}
              onChange={(e) => setWorkflow({ ...workflow, name: e.target.value })}
              sx={{ ...styles.workflowName, '& .MuiInputBase-input': { padding: '0', fontSize: '24px' } }}
              variant="standard"
              InputProps={{ disableUnderline: true }}
            />
            <TextField
              value={workflow.description}
              onChange={(e) => setWorkflow({ ...workflow, description: e.target.value })}
              sx={{ ...styles.workflowDescription, '& .MuiInputBase-input': { padding: '0', fontSize: '14px' } }}
              variant="standard"
              InputProps={{ disableUnderline: true }}
            />
          </Box>

          <Box sx={styles.headerActions}>
            <Button
              variant="outlined"
              sx={styles.actionButton}
              onClick={() => navigate({ to: Routes.frontend.companyProjectsPath })}
            >
              Cancel
            </Button>
            <Button variant="outlined" sx={styles.actionButton} onClick={handleTest}>
              Test Run
            </Button>
            <Button variant="contained" sx={styles.actionButton} onClick={handleSave}>
              Save
            </Button>
          </Box>
        </Box>

        {/* Content */}
        <Box sx={styles.content}>
          {selectedStep ? (
            <Box sx={styles.panel}>
              {/* Step Configuration */}
              <Box sx={styles.section}>
                <Box
                  sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}
                >
                  <Typography sx={styles.sectionTitle}>Step Configuration</Typography>
                  <Tooltip title="Delete Step">
                    <IconButton
                      size="small"
                      onClick={() => handleDeleteStep(selectedStep.id)}
                      sx={{ color: 'error.main' }}
                    >
                      🗑️
                    </IconButton>
                  </Tooltip>
                </Box>

                <Box sx={styles.formField}>
                  <Typography sx={styles.label}>Step Name</Typography>
                  <TextField
                    fullWidth
                    size="small"
                    value={selectedStep.name}
                    onChange={(e) => handleUpdateStep(selectedStep.id, { name: e.target.value })}
                    placeholder="e.g. 'Generate API endpoints'"
                    sx={styles.input}
                  />
                </Box>

                <Box sx={styles.formField}>
                  <Typography sx={styles.label}>Agent</Typography>
                  <Select
                    fullWidth
                    size="small"
                    value={selectedStep.agent}
                    onChange={(e) => handleUpdateStep(selectedStep.id, { agent: e.target.value })}
                    sx={styles.agentSelect}
                  >
                    {AGENT_OPTIONS.map((agent) => (
                      <MenuItem key={agent.value} value={agent.value}>
                        <span style={{ ...styles.colorDot, backgroundColor: agent.color }} />
                        {agent.label}
                      </MenuItem>
                    ))}
                  </Select>
                </Box>

                <Box sx={styles.formField}>
                  <Typography sx={styles.label}>Prompt</Typography>
                  <TextField
                    fullWidth
                    multiline
                    rows={6}
                    value={selectedStep.prompt}
                    onChange={(e) => handleUpdateStep(selectedStep.id, { prompt: e.target.value })}
                    placeholder="Enter the task prompt for this step..."
                    sx={styles.input}
                  />
                </Box>
              </Box>

              {/* Assets */}
              <Box sx={styles.section}>
                <Typography sx={styles.sectionTitle}>Expected Assets</Typography>
                <Typography sx={{ fontSize: '13px', color: 'text.secondary', marginBottom: '12px' }}>
                  Specify files or outputs that should be produced by this step
                </Typography>

                <Box sx={{ display: 'flex', gap: '8px', marginBottom: '12px' }}>
                  <TextField
                    fullWidth
                    size="small"
                    value={assetInput}
                    onChange={(e) => setAssetInput(e.target.value)}
                    placeholder="e.g. 'src/api/endpoints.ts'"
                    sx={styles.input}
                    onKeyPress={(e) => {
                      if (e.key === 'Enter') {
                        handleAddAsset();
                      }
                    }}
                  />
                  <Button variant="outlined" onClick={handleAddAsset} disabled={!assetInput.trim()}>
                    Add
                  </Button>
                </Box>

                {selectedStep.assets.length > 0 && (
                  <Box sx={styles.assetsList}>
                    {selectedStep.assets.map((asset) => (
                      <Box key={asset} sx={styles.assetChip}>
                        📄 {asset}
                        <IconButton sx={styles.removeButton} onClick={() => handleRemoveAsset(asset)}>
                          ✕
                        </IconButton>
                      </Box>
                    ))}
                  </Box>
                )}
              </Box>

              {/* Dependencies (placeholder) */}
              <Box sx={styles.section}>
                <Typography sx={styles.sectionTitle}>Dependencies</Typography>
                <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                  This step will run after all previous steps are completed
                </Typography>
              </Box>
            </Box>
          ) : (
            <Box sx={styles.emptyState}>
              <Typography sx={styles.emptyIcon}>📋</Typography>
              <Typography sx={styles.emptyTitle}>
                {workflow.steps.length === 0 ? 'No steps yet' : 'Select a step to configure'}
              </Typography>
              <Typography sx={styles.emptyDescription}>
                {workflow.steps.length === 0
                  ? 'Add your first workflow step to get started'
                  : 'Click on a step in the sidebar to edit its configuration'}
              </Typography>
              {workflow.steps.length === 0 && (
                <Button variant="contained" onClick={handleAddStep}>
                  Add First Step
                </Button>
              )}
            </Box>
          )}
        </Box>
      </Box>
    </Box>
  );
};

export default WorkflowBuilderPage;
