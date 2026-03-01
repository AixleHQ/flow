import {
  Autocomplete,
  Box,
  Button,
  Checkbox,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  MenuItem,
  Select,
  TextField,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useGetCurrentUserQuery, AVAILABLE_AGENTS, type AgentType } from 'entities/user';
import { useGetProjectRepositoriesQuery } from 'features/repositories-management/api/repositoriesApi';
import type { Repository } from 'features/repositories-management/lib/types';
import { Routes } from 'shared/routes';

interface AssetOption {
  id: number;
  name: string;
  folder: string | null;
  deletedAt: string | null;
}

interface StepOption {
  id: number;
  name: string;
  position: number;
  allowNonInteractive?: boolean;
  dependsOnStepIds?: number[];
}

export interface CreateRunParams {
  projectId: number;
  workflowId: number;
  mode: 'interactive' | 'non_interactive' | 'mixed';
  stepOverrides: Record<string, { autoRun: boolean }>;
  repositoryIds: number[];
  inputAssetIds: number[];
  agentRuntime: string;
}

interface RunWorkflowModalProps {
  open: boolean;
  workflow: { id: number; name: string; description?: string } | null;
  projectId: number;
  projectAssets?: AssetOption[];
  steps?: StepOption[];
  onCreateRun: (params: CreateRunParams) => Promise<{ id: number }>;
  isCreating?: boolean;
  onClose: () => void;
}

type UiMode = 'interactive' | 'non_interactive' | 'custom';

const MODE_OPTIONS: { value: UiMode; label: string }[] = [
  { value: 'interactive', label: 'Interactive — pause at each step for review' },
  { value: 'non_interactive', label: 'Fully automatic — run all steps without stopping' },
  { value: 'custom', label: 'Custom — choose which steps to auto-run' },
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

const RunWorkflowModal = ({
  open,
  workflow,
  projectId,
  projectAssets = [],
  steps = [],
  onCreateRun,
  isCreating = false,
  onClose,
}: RunWorkflowModalProps) => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const [uiMode, setUiMode] = useState<UiMode>('interactive');
  const [stepAutoRun, setStepAutoRun] = useState<Record<number, boolean>>({});
  const [selectedRepoIds, setSelectedRepoIds] = useState<number[]>([]);
  const [selectedAssetIds, setSelectedAssetIds] = useState<number[]>([]);
  const [agentRuntime, setAgentRuntime] = useState<string>('');

  const { data: currentUser } = useGetCurrentUserQuery();
  const { data: repositories = [] } = useGetProjectRepositoriesQuery(projectId);

  useEffect(() => {
    if (steps.length > 0) {
      const defaults: Record<number, boolean> = {};
      steps.forEach((s) => {
        defaults[s.id] = s.allowNonInteractive ?? false;
      });
      setStepAutoRun(defaults);
    }
  }, [steps]);

  interface Wave {
    index: number;
    steps: StepOption[];
    deps: string;
  }

  const waves: Wave[] = useMemo(() => {
    if (steps.length === 0) return [];

    const sorted = [...steps].sort((a, b) => a.position - b.position);
    const waveMap = new Map<number, number>();
    const nameMap = new Map<number, string>();

    sorted.forEach((s) => nameMap.set(s.id, s.name));

    sorted.forEach((s) => {
      const deps = s.dependsOnStepIds ?? [];
      if (deps.length === 0) {
        waveMap.set(s.id, 0);
      } else {
        const maxDep = Math.max(...deps.map((d) => waveMap.get(d) ?? 0));
        waveMap.set(s.id, maxDep + 1);
      }
    });

    const grouped = new Map<number, StepOption[]>();
    sorted.forEach((s) => {
      const w = waveMap.get(s.id) ?? 0;
      grouped.set(w, [...(grouped.get(w) ?? []), s]);
    });

    return Array.from(grouped.entries())
      .sort(([a], [b]) => a - b)
      .map(([idx, waveSteps]) => {
        const depIds = new Set(waveSteps.flatMap((s) => s.dependsOnStepIds ?? []));
        const depNames = Array.from(depIds)
          .map((id) => nameMap.get(id))
          .filter(Boolean);
        return {
          index: idx,
          steps: waveSteps,
          deps: depNames.join(', '),
        };
      });
  }, [steps]);

  const agentOptions = useMemo(() => {
    const configured = currentUser?.configuredAgents ?? [];
    return AVAILABLE_AGENTS.filter((a) => configured.includes(a.type));
  }, [currentUser?.configuredAgents]);

  const effectiveRuntime = agentRuntime || agentOptions[0]?.type || '';

  const selectedRepos = useMemo(
    () => repositories.filter((r: Repository) => selectedRepoIds.includes(r.id)),
    [repositories, selectedRepoIds],
  );

  const activeAssets = useMemo(() => projectAssets.filter((a) => !a.deletedAt), [projectAssets]);

  const selectedAssets = useMemo(
    () => activeAssets.filter((a) => selectedAssetIds.includes(a.id)),
    [activeAssets, selectedAssetIds],
  );

  const handleClose = useCallback(() => {
    setUiMode('interactive');
    setSelectedRepoIds([]);
    setSelectedAssetIds([]);
    setAgentRuntime('');
    onClose();
  }, [onClose]);

  const handleRun = useCallback(async () => {
    if (!workflow || !effectiveRuntime) return;

    const backendMode = uiMode === 'custom' ? 'mixed' : uiMode;
    const overrides: Record<string, { autoRun: boolean }> =
      uiMode === 'custom' ? Object.fromEntries(Object.entries(stepAutoRun).map(([id, v]) => [id, { autoRun: v }])) : {};

    try {
      const result = await onCreateRun({
        projectId,
        workflowId: workflow.id,
        mode: backendMode,
        stepOverrides: overrides,
        repositoryIds: selectedRepoIds,
        inputAssetIds: selectedAssetIds,
        agentRuntime: effectiveRuntime,
      });
      enqueueSnackbar('Workflow run started', { variant: 'success' });
      handleClose();
      navigate({
        to: Routes.frontend.workflowRunPath(String(projectId), String(result.id)),
      });
    } catch (err) {
      const message =
        (err as { data?: { errors?: Record<string, string[]> } })?.data?.errors?.mode?.[0] ||
        (err as { data?: { error?: string } })?.data?.error ||
        'Failed to start workflow run';
      enqueueSnackbar(message, { variant: 'error' });
    }
  }, [
    workflow,
    projectId,
    uiMode,
    stepAutoRun,
    selectedRepoIds,
    selectedAssetIds,
    effectiveRuntime,
    onCreateRun,
    enqueueSnackbar,
    navigate,
    handleClose,
  ]);

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
          <Select fullWidth size="small" value={uiMode} onChange={(e) => setUiMode(e.target.value as UiMode)}>
            {MODE_OPTIONS.map((opt) => (
              <MenuItem key={opt.value} value={opt.value}>
                {opt.label}
              </MenuItem>
            ))}
          </Select>

          {uiMode !== 'custom' && waves.length > 0 && (
            <Box sx={{ mt: 1, pl: 1 }}>
              {waves.map((wave) => (
                <Box key={wave.index} sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mb: 0.5 }}>
                  {wave.steps.map((s) => {
                    const willAutoRun = uiMode === 'non_interactive' || s.allowNonInteractive;
                    return (
                      <Chip
                        key={s.id}
                        label={s.name}
                        size="small"
                        color={willAutoRun ? 'success' : 'default'}
                        variant="outlined"
                        sx={{ fontSize: '11px' }}
                      />
                    );
                  })}
                  {wave.index < waves.length - 1 && (
                    <Typography variant="caption" sx={{ alignSelf: 'center', color: 'text.disabled', mx: 0.5 }}>
                      {'\u2192'}
                    </Typography>
                  )}
                </Box>
              ))}
              <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                <Chip
                  label=""
                  size="small"
                  color="success"
                  variant="outlined"
                  sx={{ width: 10, height: 14, mr: 0.5 }}
                />
                auto
                <Chip label="" size="small" variant="outlined" sx={{ width: 10, height: 14, mx: 0.5, ml: 1.5 }} />
                interactive
              </Typography>
            </Box>
          )}

          {uiMode === 'custom' && waves.length > 0 && (
            <Box sx={{ mt: 1.5 }}>
              <Typography variant="caption" color="text.secondary" sx={{ mb: 1, display: 'block' }}>
                Select which steps to run automatically:
              </Typography>
              {waves.map((wave) => (
                <Box
                  key={wave.index}
                  sx={{
                    mb: 1.5,
                    pl: 1,
                    borderLeft: '2px solid',
                    borderColor: wave.steps.length > 1 ? 'info.main' : 'divider',
                  }}
                >
                  <Typography
                    variant="caption"
                    sx={{ fontWeight: 600, color: 'text.secondary', mb: 0.5, display: 'block' }}
                  >
                    {wave.index === 0 ? 'Start' : `After ${wave.deps}`}
                    {wave.steps.length > 1 && ' (parallel)'}
                  </Typography>
                  {wave.steps.map((step) => {
                    const autoRun = stepAutoRun[step.id] ?? false;
                    return (
                      <FormControlLabel
                        key={step.id}
                        control={
                          <Checkbox
                            size="small"
                            checked={autoRun}
                            disabled={!step.allowNonInteractive}
                            onChange={(e) => setStepAutoRun((prev) => ({ ...prev, [step.id]: e.target.checked }))}
                          />
                        }
                        label={
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                            <Typography variant="body2">{step.name}</Typography>
                            <Chip
                              label={autoRun ? 'auto' : 'interactive'}
                              size="small"
                              color={autoRun ? 'success' : 'default'}
                              variant="outlined"
                              sx={{ height: 18, fontSize: '10px' }}
                            />
                            {!step.allowNonInteractive && (
                              <Chip
                                label="requires input"
                                size="small"
                                color="warning"
                                variant="outlined"
                                sx={{ height: 18, fontSize: '10px' }}
                              />
                            )}
                          </Box>
                        }
                        sx={{ display: 'flex', mb: 0.25 }}
                      />
                    );
                  })}
                </Box>
              ))}
            </Box>
          )}
        </Box>

        {/* Agent Runtime */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Agent Runtime</Typography>
          {agentOptions.length > 0 ? (
            <Select
              fullWidth
              size="small"
              value={effectiveRuntime}
              onChange={(e) => setAgentRuntime(e.target.value as AgentType)}
            >
              {agentOptions.map((agent) => (
                <MenuItem key={agent.type} value={agent.type}>
                  {agent.name}
                </MenuItem>
              ))}
            </Select>
          ) : (
            <Typography variant="body2" color="text.secondary">
              No configured agents. Set up agent credentials in your profile first.
            </Typography>
          )}
          <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
            AI agent that will execute workflow steps
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
                <Chip {...getTagProps({ index })} key={repo.id} label={repo.repoName} size="small" variant="outlined" />
              ))
            }
            isOptionEqualToValue={(opt, val) => opt.id === val.id}
          />
          <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
            Selected repos will be available to steps that have &quot;Mount repositories&quot; enabled
          </Typography>
        </Box>

        {/* Input Assets */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Input Assets</Typography>
          <Autocomplete
            multiple
            size="small"
            options={activeAssets}
            getOptionLabel={(a: AssetOption) => {
              const folder = a.folder ? `${a.folder}/` : '';
              return `${folder}${a.name}`;
            }}
            value={selectedAssets}
            onChange={(_, newValue) => setSelectedAssetIds(newValue.map((a: AssetOption) => a.id))}
            renderInput={(params) => <TextField {...params} placeholder="Select assets to include..." />}
            renderTags={(value, getTagProps) =>
              value.map((asset, index) => (
                <Chip {...getTagProps({ index })} key={asset.id} label={asset.name} size="small" variant="outlined" />
              ))
            }
            groupBy={(a: AssetOption) => a.folder || 'Root'}
            isOptionEqualToValue={(opt, val) => opt.id === val.id}
          />
          <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
            Project assets that will be available as inputs to workflow steps
          </Typography>
        </Box>
      </DialogContent>

      <DialogActions sx={styles.actions}>
        <Button onClick={handleClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={handleRun}
          disabled={isCreating || !effectiveRuntime}
          sx={{ minWidth: 120 }}
        >
          {isCreating ? 'Starting...' : 'Run Workflow'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default RunWorkflowModal;
