import {
  ActionIcon,
  Box,
  Group,
  MultiSelect,
  Select,
  Stack,
  Switch,
  Text,
  Textarea,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { IconArrowsMaximize, IconArrowsMinimize, IconInfoCircle } from '@tabler/icons-react';
import { useState } from 'react';

import classes from './BuilderPage.module.css';

interface NamedItem {
  id: number;
  name: string;
}

interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
}

interface AssetSpec {
  name: string;
  assetType: string;
  required: boolean;
  namePattern?: string | null;
}

interface Step {
  id: number;
  name: string;
  description: string | null;
  instructions: string | null;
  position: number;
  agentId: number | null;
  requiredAgentRuntime: string | null;
  allowNonInteractive: boolean;
  skipPolicy: string;
  onFailure: string;
  mountRepositories: boolean;
  bmadEnabled: boolean;
  dependsOnStepIds: number[];
  toolIds: number[];
  mcpServerIds: number[];
  skillIds: number[];
  assetIds: number[];
  inputAssetSpecs: AssetSpec[];
  outputAssetSpecs: AssetSpec[];
}

const SKIP_POLICY_TEXTS: Record<string, string> = {
  never: 'This session always runs when the workflow is triggered.',
  if_outputs_exist: 'Skips this session if its output artifacts already exist.',
  manual: 'You decide at run time whether to run this session.',
};

const ON_FAILURE_TEXTS: Record<string, string> = {
  fail: 'The entire workflow run stops immediately if this session fails.',
  retry: 'The session is retried automatically before failing.',
  skip: 'The workflow continues even if this session fails.',
};

interface SectionLabelProps {
  icon: React.ReactNode;
  label: string;
}

function SectionLabel({ icon, label }: SectionLabelProps) {
  return (
    <Group gap={6} pb={8} mb={12} style={{ borderBottom: '1px solid var(--border)' }}>
      {icon}
      <Text size="xs" fw={700} style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.1em' }}>
        {label}
      </Text>
    </Group>
  );
}

interface AssetSpecRowsProps {
  specs: AssetSpec[];
  onChange: (specs: AssetSpec[]) => void;
  showNamePattern: boolean;
  disabled: boolean;
}

function AssetSpecRows({ specs, onChange, showNamePattern, disabled }: AssetSpecRowsProps) {
  const addSpec = () => onChange([...specs, { name: '', assetType: 'file', required: true, namePattern: null }]);
  const removeSpec = (i: number) => onChange(specs.filter((_, idx) => idx !== i));
  const updateSpec = (i: number, field: string, value: unknown) =>
    onChange(specs.map((s, idx) => (idx === i ? { ...s, [field]: value } : s)));

  return (
    <Stack gap="xs">
      {specs.map((spec, idx) => (
        <Group key={idx} gap="xs" wrap="nowrap">
          <TextInput
            size="xs"
            placeholder="e.g. tasks/report.md"
            value={spec.name}
            onChange={(e) => updateSpec(idx, 'name', e.currentTarget.value)}
            style={{ flex: 1 }}
            disabled={disabled}
          />
          {showNamePattern && (
            <TextInput
              size="xs"
              placeholder="e.g. report"
              value={spec.namePattern ?? ''}
              onChange={(e) => updateSpec(idx, 'namePattern', e.currentTarget.value || null)}
              w={100}
              disabled={disabled}
            />
          )}
          <Switch
            size="xs"
            checked={spec.required}
            onChange={(e) => updateSpec(idx, 'required', e.currentTarget.checked)}
            disabled={disabled}
          />
          {!disabled && (
            <ActionIcon size="xs" color="red" variant="subtle" onClick={() => removeSpec(idx)}>
              ×
            </ActionIcon>
          )}
        </Group>
      ))}
      {!disabled && (
        <Box>
          <button
            type="button"
            className={classes.ghostRow}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '4px 0',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 4,
            }}
            onClick={addSpec}
          >
            <Text size="xs" style={{ color: 'var(--accent)' }}>
              + Add {showNamePattern ? 'output' : 'input'}
            </Text>
          </button>
        </Box>
      )}
      {specs.length === 0 && (
        <Text size="xs" style={{ color: 'var(--text-3)' }}>
          None added
        </Text>
      )}
    </Stack>
  );
}

const GROUP_PREFIX = 'grp:';

interface SessionEditorPanelProps {
  step: Step;
  allSteps: Step[];
  agents: NamedItem[];
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  readOnly: boolean;
  onFieldChange: (field: string, value: unknown, immediate?: boolean) => void;
  onAssetSpecsChange: (field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => void;
}

export function SessionEditorPanel({
  step,
  allSteps,
  agents,
  tools,
  toolGroups,
  skills,
  mcpServers,
  readOnly,
  onFieldChange,
  onAssetSpecsChange,
}: SessionEditorPanelProps) {
  const [instructionsExpanded, setInstructionsExpanded] = useState(false);
  const charCount = (step.instructions ?? '').length;

  const groupedToolIds = new Set(toolGroups.flatMap((g) => g.toolIds));
  const toolSelectData = [
    ...toolGroups.map((g) => ({ value: `${GROUP_PREFIX}${g.tag}`, label: g.label })),
    ...tools
      .filter((i) => i?.id != null && !groupedToolIds.has(i.id))
      .map((i) => ({ value: String(i.id), label: i.name ?? '' })),
  ];

  const toToolValue = (ids: number[]) => {
    const set = new Set(Array.isArray(ids) ? ids : []);
    const groupTokens = toolGroups
      .filter((g) => g.toolIds.some((id) => set.has(id)))
      .map((g) => `${GROUP_PREFIX}${g.tag}`);
    const individual = [...set].filter((id) => !groupedToolIds.has(id)).map(String);
    return [...groupTokens, ...individual];
  };

  const fromToolValue = (values: string[]): number[] => {
    const ids = new Set<number>();
    (Array.isArray(values) ? values : []).forEach((v) => {
      if (v.startsWith(GROUP_PREFIX)) {
        const group = toolGroups.find((g) => `${GROUP_PREFIX}${g.tag}` === v);
        group?.toolIds.forEach((id) => ids.add(id));
      } else {
        ids.add(Number(v));
      }
    });
    return [...ids];
  };

  const toSelectData = (items: NamedItem[]) =>
    Array.isArray(items)
      ? items.filter((i) => i?.id != null).map((i) => ({ value: String(i.id), label: i.name ?? '' }))
      : [];

  const toStringArr = (ids: number[]) => (Array.isArray(ids) ? ids : []).map(String);
  const toNumberArr = (vals: string[]) => (Array.isArray(vals) ? vals : []).map(Number);

  const otherSessions = allSteps.filter((s) => s.id !== step.id);
  const dependencyOptions = otherSessions.map((s) => ({
    value: String(s.id),
    label: `${s.position}. ${s.name}`,
  }));

  const depNote =
    step.dependsOnStepIds.length === 0
      ? 'No dependencies — this session can run in parallel with other root sessions.'
      : `Waits for ${allSteps
          .filter((s) => step.dependsOnStepIds.includes(s.id))
          .map((s) => s.name)
          .join(', ')} to complete before starting.`;

  return (
    <div className={classes.editorPanel}>
      {/* DEFINITION */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Definition" />

        <TextInput
          placeholder="Session name…"
          value={step.name}
          onChange={(e) => onFieldChange('name', e.currentTarget.value)}
          disabled={readOnly}
          variant="unstyled"
          styles={{
            input: {
              fontSize: 18,
              fontWeight: 700,
              fontFamily: 'Sora, sans-serif',
              color: 'var(--text-1)',
              padding: '4px 0',
              borderBottom: '1px solid transparent',
              borderRadius: 0,
              '&:hover': { borderBottomColor: 'var(--border-mid)' },
              '&:focus': { borderBottomColor: 'var(--accent)' },
            },
          }}
          mb={12}
        />

        <Textarea
          placeholder="One-line summary of what this does…"
          value={step.description ?? ''}
          onChange={(e) => onFieldChange('description', e.currentTarget.value)}
          disabled={readOnly}
          autosize
          minRows={2}
          mb={16}
          styles={{ input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4 } }}
        />

        {/* Instructions */}
        <Box>
          <Group gap={6} mb={6} justify="space-between">
            <Group gap={4}>
              <Text size="xs" fw={600} style={{ color: 'var(--text-1)' }}>
                Instructions
              </Text>
              <span style={{ color: 'var(--mantine-color-red-6)', fontSize: 12 }}>•</span>
              <Tooltip
                label="The prompt the AI agent receives. Use {{artifact_name}} to reference assets."
                withArrow
                multiline
                w={260}
              >
                <ActionIcon size="xs" variant="subtle" style={{ color: 'var(--text-3)' }}>
                  <IconInfoCircle size={12} />
                </ActionIcon>
              </Tooltip>
            </Group>
          </Group>
          <Textarea
            placeholder="Enter session instructions… Use {{artifact_name}} to reference workflow assets."
            value={step.instructions ?? ''}
            onChange={(e) => onFieldChange('instructions', e.currentTarget.value)}
            disabled={readOnly}
            minRows={instructionsExpanded ? 20 : 10}
            autosize={!instructionsExpanded}
            styles={{
              input: {
                minHeight: instructionsExpanded ? 400 : 180,
                background: 'transparent',
                border: '1px solid var(--border)',
                borderRadius: 4,
              },
            }}
            mb={4}
          />
          <Group justify="space-between">
            <Text size="xs" style={{ color: 'var(--text-3)' }}>
              {charCount} characters
            </Text>
            <Group gap={4}>
              <Text size="xs" style={{ color: 'var(--text-2)' }}>
                Use {'{{artifact_name}}'} to reference workflow assets.{' '}
                <a href="#" style={{ color: 'var(--accent)' }}>
                  Prompt guide ↗
                </a>
              </Text>
              <ActionIcon
                size="xs"
                variant="subtle"
                style={{ color: 'var(--text-2)' }}
                onClick={() => setInstructionsExpanded((v) => !v)}
              >
                {instructionsExpanded ? <IconArrowsMinimize size={12} /> : <IconArrowsMaximize size={12} />}
              </ActionIcon>
            </Group>
          </Group>
        </Box>
      </Box>

      {/* EXECUTION */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Execution" />
        <Group grow mb={12}>
          <Box>
            <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
              Agent
            </Text>
            <Select
              data={[{ value: '', label: 'No agent' }, ...toSelectData(agents)]}
              value={step.agentId ? String(step.agentId) : ''}
              onChange={(v) => onFieldChange('agentId', v ? Number(v) : null, true)}
              disabled={readOnly}
              clearable
              placeholder="No agent"
            />
          </Box>
          <Box>
            <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
              Execution Environment
            </Text>
            <Select
              data={[
                { value: '', label: 'None (default)' },
                { value: 'claude_code', label: 'Claude Code' },
                { value: 'cursor_cli', label: 'Cursor CLI' },
                { value: 'codex', label: 'Codex' },
                { value: 'gemini_cli', label: 'Gemini CLI' },
              ]}
              value={step.requiredAgentRuntime ?? ''}
              onChange={(v) => onFieldChange('requiredAgentRuntime', v || null, true)}
              disabled={readOnly}
              clearable
              placeholder="None (default)"
            />
          </Box>
        </Group>
      </Box>

      {/* RESOURCES */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Resources" />
        <Box
          p={10}
          mb={12}
          style={{
            borderLeft: '2px solid var(--accent)',
            background: 'var(--accent-dim)',
            borderRadius: '0 4px 4px 0',
          }}
        >
          <Text size="xs" style={{ color: 'var(--text-2)' }}>
            ℹ Session-level additions — stacked on top of Base Resources
          </Text>
        </Box>
        <Stack gap="sm">
          <Box>
            <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
              Tools — custom functions this session can call
            </Text>
            <MultiSelect
              data={toolSelectData}
              value={toToolValue(step.toolIds)}
              onChange={(v) => onFieldChange('toolIds', fromToolValue(v), true)}
              disabled={readOnly}
              searchable
              placeholder="None added"
            />
          </Box>
          <Box>
            <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
              MCP Servers — external providers
            </Text>
            <MultiSelect
              data={toSelectData(mcpServers)}
              value={toStringArr(step.mcpServerIds)}
              onChange={(v) => onFieldChange('mcpServerIds', toNumberArr(v), true)}
              disabled={readOnly}
              searchable
              placeholder="None added"
            />
          </Box>
          <Box>
            <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
              Skills — capability modules
            </Text>
            <MultiSelect
              data={toSelectData(skills)}
              value={toStringArr(step.skillIds)}
              onChange={(v) => onFieldChange('skillIds', toNumberArr(v), true)}
              disabled={readOnly}
              searchable
              placeholder="None added"
            />
          </Box>
        </Stack>
      </Box>

      {/* DEPENDENCIES */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Dependencies" />
        <Box
          p={10}
          mb={12}
          style={{
            borderLeft: '2px solid var(--mantine-color-green-6)',
            background: 'rgba(52,211,153,0.06)',
            borderRadius: '0 4px 4px 0',
          }}
        >
          <Text size="xs" style={{ color: 'var(--text-2)' }}>
            {depNote}
          </Text>
        </Box>
        <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={4}>
          Run after
        </Text>
        <MultiSelect
          data={dependencyOptions}
          value={toStringArr(step.dependsOnStepIds)}
          onChange={(v) => onFieldChange('dependsOnStepIds', toNumberArr(v), true)}
          disabled={readOnly}
          searchable
          placeholder="Select sessions this session depends on…"
        />
      </Box>

      {/* DATA FLOW */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Data Flow" />
        <Box mb={16}>
          <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={8}>
            INPUTS — files this session reads
          </Text>
          <AssetSpecRows
            specs={step.inputAssetSpecs ?? []}
            onChange={(specs) => onAssetSpecsChange('inputAssetSpecs', specs)}
            showNamePattern={false}
            disabled={readOnly}
          />
        </Box>
        <Box>
          <Text size="xs" fw={600} style={{ color: 'var(--text-2)' }} mb={8}>
            OUTPUT ARTIFACT — file this session produces
          </Text>
          <AssetSpecRows
            specs={step.outputAssetSpecs ?? []}
            onChange={(specs) => onAssetSpecsChange('outputAssetSpecs', specs)}
            showNamePattern
            disabled={readOnly}
          />
        </Box>
      </Box>

      {/* BEHAVIOR */}
      <Box mb={24}>
        <SectionLabel icon={null} label="Behavior" />

        {/* Run control */}
        <Text
          size="xs"
          fw={600}
          style={{ color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          mb={8}
        >
          Run control
        </Text>
        <Stack gap="sm" mb={16}>
          <Switch
            label="Auto-run available"
            description="Skip user approval in non-interactive/mixed modes."
            checked={step.allowNonInteractive}
            onChange={(e) => onFieldChange('allowNonInteractive', e.currentTarget.checked, true)}
            disabled={readOnly}
          />
          <Box>
            <Select
              label="Skip Policy"
              data={[
                { value: 'never', label: 'Never' },
                { value: 'if_outputs_exist', label: 'If outputs exist' },
                { value: 'manual', label: 'Manual' },
              ]}
              value={step.skipPolicy}
              onChange={(v) => onFieldChange('skipPolicy', v ?? 'never', true)}
              disabled={readOnly}
              allowDeselect={false}
            />
            <Text size="xs" style={{ color: 'var(--text-3)' }} mt={4}>
              {SKIP_POLICY_TEXTS[step.skipPolicy] ?? ''}
            </Text>
          </Box>
          <Box>
            <Select
              label="On Failure"
              data={[
                { value: 'fail', label: 'Fail' },
                { value: 'retry', label: 'Retry' },
                { value: 'skip', label: 'Skip' },
              ]}
              value={step.onFailure}
              onChange={(v) => onFieldChange('onFailure', v ?? 'fail', true)}
              disabled={readOnly}
              allowDeselect={false}
            />
            <Text size="xs" style={{ color: 'var(--text-3)' }} mt={4}>
              {ON_FAILURE_TEXTS[step.onFailure] ?? ''}
            </Text>
          </Box>
        </Stack>

        {/* Environment */}
        <Text
          size="xs"
          fw={600}
          style={{ color: 'var(--text-3)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          mb={8}
        >
          Environment
        </Text>
        <Stack gap="sm">
          <Switch
            label="Mount repositories"
            description="Makes project repositories available to the agent during this session."
            checked={step.mountRepositories}
            onChange={(e) => onFieldChange('mountRepositories', e.currentTarget.checked, true)}
            disabled={readOnly}
          />
          <Switch
            label="BMAD Method"
            description={
              <>
                Enable the BMAD methodology for this session.{' '}
                <a href="#" style={{ color: 'var(--accent)' }}>
                  Learn more ↗
                </a>
              </>
            }
            checked={step.bmadEnabled}
            onChange={(e) => onFieldChange('bmadEnabled', e.currentTarget.checked, true)}
            disabled={readOnly}
          />
        </Stack>
      </Box>
    </div>
  );
}
