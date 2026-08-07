import { router } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Divider,
  Group,
  Modal,
  MultiSelect,
  Paper,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Text,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArrowRight } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

interface RunWorkflowStep {
  id: number;
  name: string;
  position: number;
  allowNonInteractive: boolean;
  dependsOnStepIds: number[];
}

interface NamedItem {
  id: number;
  name: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: { modelId: string; displayName: string }[];
}

interface RunWorkflowModalProps {
  opened: boolean;
  onClose: () => void;
  workflowId: number;
  workflowName: string;
  steps: RunWorkflowStep[];
  projectId: number;
  configuredAgents: string[];
  agentModels?: AgentModelsEntry[];
  repositories: NamedItem[];
  assets: NamedItem[];
}

type ExecutionMode = 'interactive' | 'automatic' | 'custom';

interface Wave {
  label: string;
  steps: RunWorkflowStep[];
}

function computeWaves(steps: RunWorkflowStep[]): Wave[] {
  const stepMap = new Map(steps.map((s) => [s.id, s]));
  const assigned = new Map<number, number>();
  const waves: Wave[] = [];

  let remaining = [...steps];
  while (remaining.length > 0) {
    const waveIndex = waves.length;
    const currentWave: RunWorkflowStep[] = [];

    for (const step of remaining) {
      const allDepsAssigned = step.dependsOnStepIds.every(
        (depId) => assigned.has(depId) && assigned.get(depId)! < waveIndex,
      );
      if (allDepsAssigned) {
        currentWave.push(step);
      }
    }

    if (currentWave.length === 0) break;

    for (const step of currentWave) {
      assigned.set(step.id, waveIndex);
    }

    let label: string;
    if (waveIndex === 0) {
      label = 'Start';
    } else {
      const depNames = new Set<string>();
      for (const step of currentWave) {
        for (const depId of step.dependsOnStepIds) {
          const dep = stepMap.get(depId);
          if (dep) depNames.add(dep.name);
        }
      }
      label = `After ${[...depNames].join(', ')}`;
    }

    waves.push({ label, steps: currentWave });
    remaining = remaining.filter((s) => !assigned.has(s.id));
  }

  return waves;
}

function formatAgentLabel(agent: string): string {
  return agent
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

export function RunWorkflowModal({
  opened,
  onClose,
  workflowId,
  workflowName,
  steps,
  projectId,
  configuredAgents,
  agentModels = [],
  repositories,
  assets,
}: RunWorkflowModalProps) {
  const [mode, setMode] = useState<ExecutionMode>('automatic');
  const [agentRuntime, setAgentRuntime] = useState<string | null>(configuredAgents[0] ?? null);
  const [selectedRepoIds, setSelectedRepoIds] = useState<string[]>([]);
  const [selectedAssetIds, setSelectedAssetIds] = useState<string[]>([]);
  const [customAutoRun, setCustomAutoRun] = useState<Record<number, boolean>>(() =>
    Object.fromEntries(steps.map((s) => [s.id, s.allowNonInteractive])),
  );
  const [requestedModel, setRequestedModel] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);

  const modelsMap = useMemo(() => {
    const m: Record<string, { value: string; label: string }[]> = {};
    for (const entry of agentModels) {
      m[entry.agentType] = entry.models
        .filter((model) => model.modelId)
        .map((model) => ({ value: model.modelId, label: model.displayName || model.modelId }));
    }
    return m;
  }, [agentModels]);

  const modelOptions = useMemo(() => (agentRuntime ? (modelsMap[agentRuntime] ?? []) : []), [agentRuntime, modelsMap]);

  const waves = computeWaves(steps);

  const handleSubmit = () => {
    if (!agentRuntime || steps.length === 0) return;

    const API_MODE_MAP: Record<ExecutionMode, string> = {
      interactive: 'interactive',
      automatic: 'non_interactive',
      custom: 'mixed',
    };

    setStarting(true);
    router.post(
      `/company/projects/${projectId}/workflow_runs`,
      {
        workflowRun: {
          workflowId: workflowId,
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
    <Modal
      opened={opened}
      onClose={onClose}
      title={
        <Text fw={600} size="lg">
          Run: {workflowName}
        </Text>
      }
      size="lg"
    >
      <Stack gap="md">
        <Box>
          <Text size="sm" fw={500} mb={4}>
            Execution Mode
          </Text>
          <SegmentedControl
            fullWidth
            value={mode}
            onChange={(v) => setMode(v as ExecutionMode)}
            data={[
              { value: 'automatic', label: 'Fully Automatic' },
              { value: 'interactive', label: 'Interactive' },
              { value: 'custom', label: 'Custom' },
            ]}
          />
        </Box>

        {mode !== 'custom' && waves.length > 0 && (
          <Box>
            <Group gap="xs" mb="xs">
              <Badge color="green" variant="filled" size="xs">
                Auto
              </Badge>
              <Badge variant="outline" size="xs">
                Interactive
              </Badge>
            </Group>
            <Group gap="xs" wrap="wrap" align="center">
              {waves.map((wave, wi) => (
                <Group key={wi} gap="xs" wrap="nowrap" align="center">
                  {wi > 0 && <IconArrowRight size={16} color="gray" />}
                  <Group gap={4} wrap="wrap">
                    {wave.steps.map((step) => (
                      <Badge
                        key={step.id}
                        variant={mode === 'automatic' ? 'filled' : 'outline'}
                        color={mode === 'automatic' ? 'green' : 'gray'}
                        size="sm"
                      >
                        {step.name}
                      </Badge>
                    ))}
                  </Group>
                </Group>
              ))}
            </Group>
          </Box>
        )}

        {mode === 'custom' && (
          <Stack gap="sm">
            {waves.map((wave, wi) => (
              <Paper
                key={wi}
                p="sm"
                withBorder
                style={wave.steps.length > 1 ? { borderLeft: '3px solid var(--mantine-color-blue-5)' } : undefined}
              >
                <Text size="xs" c="dimmed" mb="xs">
                  {wave.label}
                </Text>
                <Stack gap="xs">
                  {wave.steps.map((step) => {
                    const forced = !step.allowNonInteractive;
                    const autoRun = forced ? false : !!customAutoRun[step.id];

                    return (
                      <Group key={step.id} gap="sm" wrap="nowrap">
                        <Switch
                          checked={autoRun}
                          disabled={forced}
                          onChange={(e) => {
                            const checked = e.currentTarget.checked;
                            setCustomAutoRun((prev) => ({
                              ...prev,
                              [step.id]: checked,
                            }));
                          }}
                          size="sm"
                        />
                        <Text size="sm" style={{ flex: 1 }}>
                          {step.name}
                        </Text>
                        <Group gap={4} wrap="nowrap">
                          {autoRun ? (
                            <Badge color="green" variant="filled" size="xs">
                              auto
                            </Badge>
                          ) : (
                            <Badge variant="outline" size="xs">
                              interactive
                            </Badge>
                          )}
                          {forced && (
                            <Badge color="orange" variant="light" size="xs">
                              requires input
                            </Badge>
                          )}
                        </Group>
                      </Group>
                    );
                  })}
                </Stack>
              </Paper>
            ))}
          </Stack>
        )}

        <Divider />

        {configuredAgents.length > 0 ? (
          <Select
            label="Fallback Agent Runtime"
            description="Used for steps that don't have a specific runtime configured"
            value={agentRuntime}
            onChange={setAgentRuntime}
            data={configuredAgents.map((a) => ({
              value: a,
              label: formatAgentLabel(a),
            }))}
          />
        ) : (
          <Box>
            <Text size="sm" fw={500} mb={4}>
              Fallback Agent Runtime
            </Text>
            <Text size="sm" c="dimmed">
              No configured agents
            </Text>
          </Box>
        )}

        {modelOptions.length > 0 && (
          <Select
            label="Fallback Model"
            description="Used for steps without a preferred model (leave empty for credential default)"
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
          placeholder="Leave empty to use the workflow's repositories..."
          value={selectedRepoIds}
          onChange={setSelectedRepoIds}
          data={repositories.map((r) => ({
            value: String(r.id),
            label: r.name,
          }))}
        />

        <MultiSelect
          label="Input Assets"
          description="Project assets that will be available as inputs to workflow steps"
          placeholder="Select assets to include..."
          value={selectedAssetIds}
          onChange={setSelectedAssetIds}
          data={assets.map((a) => ({
            value: String(a.id),
            label: a.name,
          }))}
        />

        <Divider />

        <Group justify="flex-end">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} loading={starting} disabled={starting || !agentRuntime || steps.length === 0}>
            {starting ? 'Starting...' : 'Run Workflow'}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
