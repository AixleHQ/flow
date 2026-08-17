import { router } from '@inertiajs/react';
import { Box, Button, Drawer, MultiSelect, Select, Stack, Switch, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAdjustments, IconPlayerPlay, IconRobot, IconSitemap } from '@tabler/icons-react';
import { useEffect, useMemo, useState } from 'react';

import { FormSection, ModeCards, RuntimeTiles, StatusTag } from 'shared/ui/sessions';

import classes from './RunWorkflowDrawer.module.css';

export interface RunWorkflowStep {
  id: number;
  name: string;
  position: number;
  allowNonInteractive: boolean;
  dependsOnStepIds: number[];
}

export interface RunWorkflowOption {
  id: number;
  name: string;
  steps: RunWorkflowStep[];
}

interface NamedItem {
  id: number;
  name: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: { modelId: string; displayName: string }[];
}

interface RunWorkflowDrawerProps {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  /** Every workflow the user may run. One-element lists skip the selector. */
  workflows: RunWorkflowOption[];
  /** Pre-selected workflow — set when launched from a workflow's own page. */
  initialWorkflowId?: number | null;
  configuredAgents: string[];
  defaultAgentRuntime?: string | null;
  agentModels?: AgentModelsEntry[];
  repositories: NamedItem[];
  assets: NamedItem[];
}

type ExecutionMode = 'interactive' | 'automatic' | 'custom';

const API_MODE_MAP: Record<ExecutionMode, string> = {
  interactive: 'interactive',
  automatic: 'non_interactive',
  custom: 'mixed',
};

const MODE_OPTIONS = [
  { value: 'automatic' as const, title: 'Fully automatic', description: 'Runs end-to-end' },
  { value: 'interactive' as const, title: 'Interactive', description: 'Approve each step' },
  { value: 'custom' as const, title: 'Custom', description: 'Pick per step' },
];

/**
 * Run Workflow as a 460px right drawer, structurally identical to New Session:
 * Workflow → Agent runtime → Execution mode → Configuration, with the same
 * runtime tiles and the same execution-mode tag-cards. The two flows used to
 * share nothing but their purpose.
 */
export function RunWorkflowDrawer({
  opened,
  onClose,
  projectId,
  workflows,
  initialWorkflowId = null,
  configuredAgents,
  defaultAgentRuntime,
  agentModels = [],
  repositories,
  assets,
}: RunWorkflowDrawerProps) {
  const [workflowId, setWorkflowId] = useState<number | null>(initialWorkflowId ?? null);
  const [mode, setMode] = useState<ExecutionMode>('automatic');
  // The member's default agent for this company wins; the first configured
  // credential is only a fallback (its order is whatever Postgres returns).
  const [agentRuntime, setAgentRuntime] = useState<string | null>(
    defaultAgentRuntime && configuredAgents.includes(defaultAgentRuntime)
      ? defaultAgentRuntime
      : (configuredAgents[0] ?? null),
  );
  const [selectedRepoIds, setSelectedRepoIds] = useState<string[]>([]);
  const [selectedAssetIds, setSelectedAssetIds] = useState<string[]>([]);
  const [customAutoRun, setCustomAutoRun] = useState<Record<number, boolean>>({});
  const [requestedModel, setRequestedModel] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);

  // The drawer stays mounted between opens (only `opened` toggles visibility),
  // so its form state has to be reset explicitly — otherwise reopening shows
  // the previous run's stale selections.
  useEffect(() => {
    if (!opened) return;
    setWorkflowId(initialWorkflowId ?? null);
    setMode('automatic');
    setSelectedRepoIds([]);
    setSelectedAssetIds([]);
    setRequestedModel(null);
  }, [opened, initialWorkflowId]);

  const workflow = useMemo(() => workflows.find((w) => w.id === workflowId) ?? null, [workflows, workflowId]);
  const steps = workflow?.steps ?? [];

  // Custom mode starts from each step's own capability — a step that cannot run
  // unattended must not silently default to "auto".
  useEffect(() => {
    setCustomAutoRun(Object.fromEntries((workflow?.steps ?? []).map((s) => [s.id, s.allowNonInteractive])));
  }, [workflow]);

  const modelOptions = useMemo(() => {
    if (!agentRuntime) return [];
    const entry = agentModels.find((e) => e.agentType === agentRuntime);
    return (entry?.models ?? [])
      .filter((m) => m.modelId)
      .map((m) => ({ value: m.modelId, label: m.displayName || m.modelId }));
  }, [agentRuntime, agentModels]);

  const canSubmit = !!workflow && !!agentRuntime && steps.length > 0 && !starting;

  const handleSubmit = () => {
    if (!canSubmit || !workflow) return;

    setStarting(true);
    router.post(
      `/company/projects/${projectId}/workflow_runs`,
      {
        workflowRun: {
          workflowId: workflow.id,
          mode: API_MODE_MAP[mode],
          agentRuntime: agentRuntime,
          requestedModel: requestedModel || undefined,
          repositoryIds: selectedRepoIds.map(Number),
          inputAssetIds: selectedAssetIds.map(Number),
          ...(mode === 'custom' && {
            stepOverrides: Object.fromEntries(steps.map((s) => [s.id, { autoRun: !!customAutoRun[s.id] }])),
          }),
        },
      },
      {
        onSuccess: () => onClose(),
        onError: (errors) => {
          const message = Object.values(errors).flat().join(', ') || 'Failed to start workflow';
          notifications.show({ title: 'Failed to start workflow', message, color: 'red' });
        },
        onFinish: () => setStarting(false),
      },
    );
  };

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={460}
      // The drawer names what you are about to run as soon as you have chosen.
      title={workflow ? `Run: ${workflow.name}` : 'Run workflow'}
      padding={0}
      styles={{ body: { padding: 0, height: 'calc(100% - 60px)' } }}
    >
      <div className={classes.layout}>
        <div className={classes.body}>
          <Stack gap="md">
            <Box>
              <FormSection icon={<IconSitemap size={14} />} first>
                Workflow
              </FormSection>
              <Select
                aria-label="Workflow"
                placeholder="Select a workflow…"
                data={workflows.map((w) => ({ value: String(w.id), label: w.name }))}
                value={workflowId ? String(workflowId) : null}
                onChange={(v) => setWorkflowId(v ? Number(v) : null)}
                searchable
              />
            </Box>

            <Box>
              <FormSection icon={<IconRobot size={14} />}>Fallback agent runtime</FormSection>
              <RuntimeTiles value={agentRuntime} configured={configuredAgents} onChange={setAgentRuntime} />
              {configuredAgents.length === 0 && (
                <Text size="xs" c="dimmed" mt={8}>
                  No connected runtimes — connect one in your profile before running a workflow.
                </Text>
              )}
            </Box>

            <Box>
              <FormSection icon={<IconPlayerPlay size={14} />}>Execution mode</FormSection>
              <ModeCards aria-label="Execution mode" options={MODE_OPTIONS} value={mode} onChange={setMode} />

              {mode !== 'custom' && (
                <p className={classes.note}>
                  {mode === 'automatic'
                    ? "All sessions run automatically end-to-end. You'll get the finished run and its assets when it's done."
                    : "You'll be prompted to review and approve each session before it continues."}
                </p>
              )}

              {mode === 'custom' && steps.length > 0 && (
                <div className={classes.stepCard}>
                  <div className={classes.stepCardHead}>Sessions</div>
                  <Stack gap="xs">
                    {steps.map((step) => {
                      const forced = !step.allowNonInteractive;
                      const autoRun = forced ? false : !!customAutoRun[step.id];
                      return (
                        <div className={classes.stepRow} key={step.id}>
                          <Switch
                            size="sm"
                            checked={autoRun}
                            disabled={forced}
                            aria-label={`Run "${step.name}" automatically`}
                            onChange={(e) => {
                              const checked = e.currentTarget.checked;
                              setCustomAutoRun((prev) => ({ ...prev, [step.id]: checked }));
                            }}
                          />
                          <span className={classes.stepName}>{step.name}</span>
                          <StatusTag plain className={classes.stepTag}>
                            {forced ? 'Requires input' : autoRun ? 'Auto' : 'Interactive'}
                          </StatusTag>
                        </div>
                      );
                    })}
                  </Stack>
                </div>
              )}
            </Box>

            <Box>
              <FormSection icon={<IconAdjustments size={14} />}>Configuration</FormSection>
              <Stack gap="md">
                {modelOptions.length > 0 && (
                  <Select
                    label="Fallback model"
                    description="Used for steps without a preferred model"
                    placeholder="Default (per-step or credential)"
                    value={requestedModel}
                    onChange={setRequestedModel}
                    data={modelOptions}
                    clearable
                    searchable
                  />
                )}
                <MultiSelect
                  label="Repositories"
                  description="Overrides the repositories chosen on the workflow, for this run only"
                  placeholder="Select repositories to mount…"
                  value={selectedRepoIds}
                  onChange={setSelectedRepoIds}
                  data={repositories.map((r) => ({ value: String(r.id), label: r.name }))}
                  searchable
                />
                <MultiSelect
                  label="Input assets"
                  description="Project assets available as inputs to workflow steps"
                  placeholder="Select assets to include…"
                  value={selectedAssetIds}
                  onChange={setSelectedAssetIds}
                  data={assets.map((a) => ({ value: String(a.id), label: a.name }))}
                  searchable
                />
              </Stack>
            </Box>
          </Stack>
        </div>

        <div className={classes.footer}>
          <Button
            fullWidth
            size="md"
            leftSection={<IconPlayerPlay size={18} />}
            onClick={handleSubmit}
            loading={starting}
            disabled={!canSubmit}
          >
            Run workflow
          </Button>
        </div>
      </div>
    </Drawer>
  );
}
