import { router } from '@inertiajs/react';
import { Box, Button, MultiSelect, Select, Stack, Switch, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAdjustments, IconPlayerPlay, IconRobot, IconSitemap } from '@tabler/icons-react';
import { useEffect, useMemo, useState } from 'react';

import type { RunnerSummary } from '@/types/generated';

import { AssetPicker, type AssetPickerItem } from 'shared/components/AssetPicker';
import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import { RunnerCredentialNote, RunnerSelect } from 'shared/resources/runners/runnerChoice';
import { runnerUnusableReason } from 'shared/resources/runners/runnerCopy';
import { NO_AGENT_CREDENTIALS } from 'shared/ui/agentRuntimes';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';
import { FormSection, ModeCards, RuntimeTiles, StatusTag } from 'shared/ui/sessions';

import classes from './RunWorkflowDrawer.module.css';

interface RunWorkflowStep {
  id: number;
  name: string;
  position: number;
  allowNonInteractive: boolean;
  dependsOnStepIds: number[];
}

export interface RunWorkflowOption {
  id: number;
  name: string;
  /** The workflow's runner, null for hosted: what "Runs on" starts from. */
  runnerId?: number | null;
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
  assets: AssetPickerItem[];
  /** The runners the project can see; only read with the externalRunners flag. */
  runners?: RunnerSummary[];
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

const SHOWN_STEP_NAMES = 3;

function namedSteps(steps: RunWorkflowStep[]): string {
  const names = steps.slice(0, SHOWN_STEP_NAMES).map((s) => `"${s.name}"`);
  const hidden = steps.length - names.length;
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(hidden > 0 ? [...names, `${hidden} more`] : names);
}

function automaticModeOption(manualSteps: RunWorkflowStep[]) {
  const option = MODE_OPTIONS[0];
  if (manualSteps.length === 0) return option;

  const count = manualSteps.length;
  return {
    ...option,
    description: count === 1 ? '1 session needs input' : `${count} sessions need input`,
    disabled: true,
    disabledReason: `Auto-run is off for ${namedSteps(manualSteps)}. Turn on "Auto-run available" for every session to run this workflow fully automatic.`,
  };
}

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
  runners = [],
}: RunWorkflowDrawerProps) {
  const externalRunners = useFeatureFlag('externalRunners');
  const [workflowId, setWorkflowId] = useState<number | null>(initialWorkflowId ?? null);
  // Undefined until the person picks: the run then takes its workflow's runner.
  const [runnerPick, setRunnerPick] = useState<number | null | undefined>(undefined);
  const [mode, setMode] = useState<ExecutionMode>('automatic');
  // The member's default agent for this company wins; the first configured
  // credential is only a fallback (its order is whatever Postgres returns).
  const [agentRuntime, setAgentRuntime] = useState<string | null>(
    defaultAgentRuntime && configuredAgents.includes(defaultAgentRuntime)
      ? defaultAgentRuntime
      : (configuredAgents[0] ?? null),
  );
  const [selectedRepoIds, setSelectedRepoIds] = useState<string[]>([]);
  const [selectedAssetIds, setSelectedAssetIds] = useState<number[]>([]);
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
    setCustomAutoRun({});
    setRequestedModel(null);
    setRunnerPick(undefined);
  }, [opened, initialWorkflowId]);

  const workflow = useMemo(() => workflows.find((w) => w.id === workflowId) ?? null, [workflows, workflowId]);
  const steps = workflow?.steps ?? [];
  const workflowRunnerId = workflow?.runnerId ?? null;
  const runnerId = runnerPick === undefined ? workflowRunnerId : runnerPick;
  const runner = runners.find((r) => r.id === runnerId);
  const runnerWarning = runner ? runnerUnusableReason(runner) : null;

  // Derived on every render, not synced through an effect: the steps come from
  // props, and an Inertia reload can switch a session's auto-run while the
  // drawer is open. The server refuses the same runs (WorkflowService#validate_mode!).
  const manualSteps = steps.filter((s) => !s.allowNonInteractive);
  const automaticAvailable = manualSteps.length === 0;
  const defaultMode: ExecutionMode = automaticAvailable ? 'automatic' : 'interactive';
  const effectiveMode: ExecutionMode = mode === 'automatic' && !automaticAvailable ? 'interactive' : mode;
  const modeOptions = [automaticModeOption(manualSteps), ...MODE_OPTIONS.slice(1)];

  // Custom mode starts from each step's own capability — a step that cannot run
  // unattended must not silently default to "auto", nor be switched to it.
  const stepAutoRun = (step: RunWorkflowStep) => step.allowNonInteractive && (customAutoRun[step.id] ?? true);

  const modelOptions = useMemo(() => {
    if (!agentRuntime) return [];
    const entry = agentModels.find((e) => e.agentType === agentRuntime);
    return (entry?.models ?? [])
      .filter((m) => m.modelId)
      .map((m) => ({ value: m.modelId, label: m.displayName || m.modelId }));
  }, [agentRuntime, agentModels]);

  const canSubmit = !!workflow && !!agentRuntime && steps.length > 0 && !starting;

  // Mirrors what the open-effect resets. The runtime pick survives a close, and the per-step
  // switches only exist in Custom mode, which is never the default and so already counts.
  const dirty =
    workflowId !== (initialWorkflowId ?? null) ||
    effectiveMode !== defaultMode ||
    selectedRepoIds.length > 0 ||
    selectedAssetIds.length > 0 ||
    requestedModel !== null ||
    runnerId !== workflowRunnerId;
  const requestClose = useConfirmClose(dirty, onClose);

  const handleSubmit = () => {
    if (!canSubmit || !workflow) return;

    setStarting(true);
    router.post(
      `/company/projects/${projectId}/workflow_runs`,
      {
        workflowRun: {
          workflowId: workflow.id,
          mode: API_MODE_MAP[effectiveMode],
          agentRuntime: agentRuntime,
          requestedModel: requestedModel || undefined,
          repositoryIds: selectedRepoIds.map(Number),
          inputAssetIds: selectedAssetIds,
          // Only a pick that differs from the workflow's is an override (DESIGN.md §3.3); null is hosted.
          ...(externalRunners && runnerId !== workflowRunnerId && { runnerId }),
          ...(effectiveMode === 'custom' && {
            stepOverrides: Object.fromEntries(steps.map((s) => [s.id, { autoRun: stepAutoRun(s) }])),
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
    <ResourceDrawer
      opened={opened}
      onClose={requestClose}
      // The drawer names what you are about to run as soon as you have chosen.
      title={workflow ? `Run: ${workflow.name}` : 'Run workflow'}
      footer={
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
      }
    >
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
            onChange={(v) => {
              setWorkflowId(v ? Number(v) : null);
              setRunnerPick(undefined);
            }}
            searchable
          />
        </Box>

        {externalRunners && workflow && (
          <Box>
            <RunnerSelect
              label="Runs on"
              hostedLabel="Hosted"
              description="Defaults to the workflow's runner"
              runners={runners}
              value={runnerId}
              onChange={setRunnerPick}
            />
            <RunnerCredentialNote runner={runner} />
            {runnerWarning && (
              <Text size="xs" c="var(--app-warning-fg)" mt={4}>
                {runnerWarning} The run fails at launch.
              </Text>
            )}
          </Box>
        )}

        <Box>
          <FormSection icon={<IconRobot size={14} />}>Fallback agent runtime</FormSection>
          <RuntimeTiles value={agentRuntime} configured={configuredAgents} onChange={setAgentRuntime} />
          {configuredAgents.length === 0 && (
            <Text size="xs" c="dimmed" mt={8}>
              {NO_AGENT_CREDENTIALS}
            </Text>
          )}
        </Box>

        <Box>
          <FormSection icon={<IconPlayerPlay size={14} />}>Execution mode</FormSection>
          <ModeCards aria-label="Execution mode" options={modeOptions} value={effectiveMode} onChange={setMode} />

          {effectiveMode !== 'custom' && (
            <p className={classes.note}>
              {effectiveMode === 'automatic'
                ? "All sessions run automatically end-to-end. You'll get the finished run and its assets when it's done."
                : "You'll be prompted to review and approve each session before it continues."}
            </p>
          )}

          {effectiveMode === 'custom' && steps.length > 0 && (
            <div className={classes.stepCard}>
              <div className={classes.stepCardHead}>Sessions</div>
              <Stack gap="xs">
                {steps.map((step) => {
                  const forced = !step.allowNonInteractive;
                  const autoRun = stepAutoRun(step);
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
            <Box>
              <Text size="sm" fw={500} mb={2}>
                Input assets
              </Text>
              <Text size="xs" c="dimmed" mb={4}>
                Project assets available as inputs to workflow steps
              </Text>
              <AssetPicker
                assets={assets}
                value={selectedAssetIds}
                onChange={setSelectedAssetIds}
                placeholder="Select assets to include…"
                aria-label="Input assets"
              />
            </Box>
          </Stack>
        </Box>
      </Stack>
    </ResourceDrawer>
  );
}
