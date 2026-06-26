import {
  DndContext,
  DragEndEvent,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Head, router, usePage } from '@inertiajs/react';
import {
  Accordion,
  ActionIcon,
  Alert,
  Badge,
  Box,
  Button,
  Divider,
  Group,
  Modal,
  MultiSelect,
  NumberInput,
  Paper,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
  Textarea,
  Tooltip,
} from '@mantine/core';
import {
  IconChevronDown,
  IconChevronLeft,
  IconChevronUp,
  IconGripVertical,
  IconInfoCircle,
  IconPlayerPlay,
  IconPlus,
  IconBolt,
  IconTool,
  IconGitBranch,
  IconListCheck,
  IconFileDescription,
  IconTrash,
} from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { RunWorkflowModal } from 'shared/components/RunWorkflowModal';
import {
  apiV1ProjectWorkflowPath,
  apiV1ProjectWorkflowStepsPath,
  apiV1ProjectWorkflowStepPath,
  reorderApiV1ProjectWorkflowStepsPath,
} from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './BuilderPage.module.css';

interface Project {
  id: number;
  name: string;
}
type ProjectOrNull = Project | null;
interface NamedItem {
  id: number;
  name: string;
}
interface SubStep {
  id: number;
  name: string;
  description: string | null;
  instructions: string | null;
  position: number;
  required: boolean;
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
  preferredModel: string | null;
  allowNonInteractive: boolean;
  skipPolicy: string;
  onFailure: string;
  maxRetries: number;
  mountRepositories: boolean;
  bmadEnabled: boolean;
  dependsOnStepIds: number[];
  toolIds: number[];
  mcpServerIds: number[];
  skillIds: number[];
  inputAssetSpecs: AssetSpec[];
  outputAssetSpecs: AssetSpec[];
  subSteps: SubStep[];
}
interface Workflow {
  id: number;
  name: string;
  description: string | null;
  scopeType: string;
  scopeIndicator: string;
  inheritAllProjectResources: boolean;
  baseToolIds: number[];
  baseSkillIds: number[];
  baseMCPServerIds: number[];
  baseAssetIds: number[];
}
interface AgentModel {
  modelId: string;
  displayName: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface Props {
  project: ProjectOrNull;
  workflow: Workflow;
  steps: Step[];
  agents?: NamedItem[];
  tools?: NamedItem[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  assets?: NamedItem[];
  repositories?: NamedItem[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  configuredAgents: string[];
}

const AVAILABLE_RUNTIMES = [
  { value: 'claude_code', label: 'Claude Code' },
  { value: 'cursor_cli', label: 'Cursor CLI' },
  { value: 'codex', label: 'Codex' },
  { value: 'gemini_cli', label: 'Gemini CLI' },
];

const SKIP_POLICIES = [
  { value: 'never', label: 'Never' },
  { value: 'if_outputs_exist', label: 'If outputs exist' },
  { value: 'manual', label: 'Manual' },
];

const ON_FAILURE_OPTIONS = [
  { value: 'retry', label: 'Retry' },
  { value: 'skip', label: 'Skip' },
  { value: 'fail', label: 'Fail' },
];

// Workflows are always edited within a project context (the company-level
// workflow editor was removed). These helpers require a non-null projectId.
const requireProjectId = (projectId: number | null): number => {
  if (projectId == null) throw new Error('BuilderPage requires a project context');
  return projectId;
};

const workflowApi = (projectId: number | null, workflowId: number) =>
  apiV1ProjectWorkflowPath(requireProjectId(projectId), workflowId);

const stepsCollectionApi = (projectId: number | null, workflowId: number) =>
  apiV1ProjectWorkflowStepsPath(requireProjectId(projectId), workflowId);

const stepApi = (projectId: number | null, workflowId: number, stepId: number) =>
  apiV1ProjectWorkflowStepPath(requireProjectId(projectId), workflowId, stepId);

const stepsReorderApi = (projectId: number | null, workflowId: number) =>
  reorderApiV1ProjectWorkflowStepsPath(requireProjectId(projectId), workflowId);

// Fields stored in the workflow's config JSON — must be sent nested under `config` in PATCH requests.
const CONFIG_FIELDS = new Set([
  'inheritAllProjectResources',
  'baseToolIds',
  'baseSkillIds',
  'baseMCPServerIds',
  'baseAssetIds',
]);

const jsonHeaders = { 'Content-Type': 'application/json' };
const fetchOpts = { credentials: 'include' as const };

// --- Asset Specs Editor ---

function AssetSpecsEditor({
  specs,
  onChange,
  showNamePattern,
  disabled,
}: {
  specs: AssetSpec[];
  onChange: (specs: AssetSpec[]) => void;
  showNamePattern: boolean;
  disabled: boolean;
}) {
  const addSpec = () => {
    onChange([...specs, { name: '', assetType: 'file', required: true, namePattern: null }]);
  };

  const removeSpec = (index: number) => {
    onChange(specs.filter((_, i) => i !== index));
  };

  const updateSpec = (index: number, field: string, value: unknown) => {
    onChange(specs.map((s, i) => (i === index ? { ...s, [field]: value } : s)));
  };

  return (
    <Stack gap="xs">
      {specs.length > 0 && (
        <div className={classes.assetSpecRow}>
          <Text size="xs" c="dimmed" style={{ flex: 1 }}>
            Path
          </Text>
          {showNamePattern && (
            <Text size="xs" c="dimmed" w={120}>
              Match pattern
            </Text>
          )}
          <Text size="xs" c="dimmed" w={40}>
            Req
          </Text>
          {!disabled && <Box w={22} />}
        </div>
      )}
      {specs.map((spec, idx) => (
        <div key={idx} className={classes.assetSpecRow}>
          <TextInput
            size="xs"
            placeholder="e.g. tasks/report.md"
            value={spec.name}
            onChange={(e) => updateSpec(idx, 'name', e.currentTarget.value)}
            style={{ flex: 1 }}
            disabled={disabled}
          />
          {showNamePattern && (
            <Tooltip
              label="Regexp matched anywhere in the file path. Partial match works — e.g. 'summary' matches tasks/summary-final.md. Leave empty to use Path as an exact match."
              withArrow
              multiline
              w={260}
              position="top"
            >
              <TextInput
                size="xs"
                placeholder="e.g. report"
                value={spec.namePattern ?? ''}
                onChange={(e) => updateSpec(idx, 'namePattern', e.currentTarget.value || null)}
                w={120}
                disabled={disabled}
              />
            </Tooltip>
          )}
          <Switch
            size="xs"
            checked={spec.required}
            onChange={(e) => updateSpec(idx, 'required', e.currentTarget.checked)}
            disabled={disabled}
            w={40}
          />
          {!disabled && (
            <ActionIcon size="xs" color="red" variant="subtle" onClick={() => removeSpec(idx)}>
              <IconTrash size={12} />
            </ActionIcon>
          )}
        </div>
      ))}
      {!disabled && (
        <Button size="xs" variant="subtle" leftSection={<IconPlus size={12} />} onClick={addSpec} w="fit-content">
          Add
        </Button>
      )}
      {specs.length === 0 && (
        <Text size="xs" c="dimmed">
          No asset specs defined
        </Text>
      )}
    </Stack>
  );
}

// --- Accordion control label helper ---

function AccordionLabel({ icon, label }: { icon: React.ReactNode; label: string }) {
  return (
    <Group gap="xs">
      {icon}
      <Text size="sm" fw={600}>
        {label}
      </Text>
    </Group>
  );
}

// --- Sortable Sub-step ---

function SortableSubStep({
  ss,
  stepId,
  readOnly,
  onRemove,
  onChange,
}: {
  ss: SubStep;
  stepId: number;
  readOnly: boolean;
  onRemove: (stepId: number, subStepId: number) => void;
  onChange: (stepId: number, subStepId: number, field: string, value: unknown) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: ss.id,
    disabled: readOnly,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <Paper ref={setNodeRef} style={style} p="sm" withBorder radius="sm">
      <Group justify="space-between" mb="xs">
        <Group gap="xs">
          {!readOnly && (
            <Box {...attributes} {...listeners} style={{ cursor: 'grab', touchAction: 'none' }}>
              <IconGripVertical size={14} color="var(--mantine-color-dimmed)" />
            </Box>
          )}
          <Text size="xs" c="dimmed" fw={700}>
            #{ss.position}
          </Text>
        </Group>
        <Group gap="xs">
          <Switch
            label="Required"
            size="xs"
            checked={ss.required}
            onChange={(e) => onChange(stepId, ss.id, 'required', e.currentTarget.checked)}
            disabled={readOnly}
          />
          {!readOnly && (
            <ActionIcon size="xs" color="red" variant="subtle" onClick={() => onRemove(stepId, ss.id)}>
              <IconTrash size={12} />
            </ActionIcon>
          )}
        </Group>
      </Group>
      <TextInput
        placeholder="Name"
        size="xs"
        mb="xs"
        value={ss.name}
        onChange={(e) => onChange(stepId, ss.id, 'name', e.currentTarget.value)}
        disabled={readOnly}
      />
      <Textarea
        placeholder="Description"
        size="xs"
        mb="xs"
        value={ss.description ?? ''}
        onChange={(e) => onChange(stepId, ss.id, 'description', e.currentTarget.value)}
        autosize
        minRows={1}
        disabled={readOnly}
      />
      <Textarea
        placeholder="Instructions"
        size="xs"
        value={ss.instructions ?? ''}
        onChange={(e) => onChange(stepId, ss.id, 'instructions', e.currentTarget.value)}
        autosize
        minRows={2}
        disabled={readOnly}
      />
    </Paper>
  );
}

// --- Main Page ---

const BuilderPage = () => {
  const {
    project,
    workflow: initialWorkflow,
    steps: initialSteps,
    agents: rawAgents,
    tools: rawTools,
    skills: rawSkills,
    mcpServers: rawMcpServers,
    assets: rawAssets,
    repositories: rawRepositories,
    agentModels: rawAgentModels,
    readOnly,
    configuredAgents,
  } = usePage<{ props: Props }>().props as unknown as Props;

  const agents = rawAgents ?? [];
  const tools = rawTools ?? [];
  const skills = rawSkills ?? [];
  const mcpServers = rawMcpServers ?? [];
  const assets = rawAssets ?? [];
  const repositories = rawRepositories ?? [];
  const agentModels = rawAgentModels ?? [];

  const modelsMap = useMemo(() => {
    const m: Record<string, AgentModel[]> = {};
    for (const entry of agentModels) m[entry.agentType] = entry.models;
    return m;
  }, [agentModels]);

  const projectId = project?.id ?? null;
  // Company-level workflows were removed; BuilderPage always renders within a project.
  const backPath = projectId ? `/company/projects/${projectId}/workflows` : '/company/projects';

  const [workflow, setWorkflow] = useState(initialWorkflow);
  const [steps, setSteps] = useState(initialSteps);
  const [selectedStepId, setSelectedStepId] = useState<number | null>(initialSteps[0]?.id ?? null);
  const [deleteStepConfirm, setDeleteStepConfirm] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [runModalOpen, setRunModalOpen] = useState(false);

  const selectedStep = useMemo(() => steps.find((s) => s.id === selectedStepId) ?? null, [steps, selectedStepId]);

  const sortedSteps = useMemo(() => [...steps].sort((a, b) => a.position - b.position), [steps]);

  // --- Workflow autosave ---
  const saveWorkflow = useDebouncedCallback(async (field: string, value: unknown) => {
    setSaving(true);
    const payload = CONFIG_FIELDS.has(field)
      ? { workflow: { config: { [field]: value } } }
      : { workflow: { [field]: value } };
    await fetch(workflowApi(projectId, workflow.id), {
      method: 'PATCH',
      headers: jsonHeaders,
      ...fetchOpts,
      body: JSON.stringify(payload),
    });
    setSaving(false);
  }, 500);

  const updateWorkflowField = useCallback(
    (field: string, value: unknown) => {
      setWorkflow((w) => ({ ...w, [field]: value }));
      saveWorkflow(field, value);
    },
    [saveWorkflow],
  );

  // --- Step CRUD ---
  const createStep = useCallback(async () => {
    setSaving(true);
    const nextPos = steps.length > 0 ? Math.max(...steps.map((s) => s.position)) + 1 : 1;
    const res = await fetch(stepsCollectionApi(projectId, workflow.id), {
      method: 'POST',
      headers: jsonHeaders,
      ...fetchOpts,
      body: JSON.stringify({ step: { name: `Step ${nextPos}`, position: nextPos } }),
    });
    if (res.ok) {
      const data = await res.json();
      const newStep: Step = {
        ...data,
        subSteps: data.subSteps ?? [],
        toolIds: data.toolIds ?? [],
        mcpServerIds: data.mcpServerIds ?? [],
        skillIds: data.skillIds ?? [],
        dependsOnStepIds: data.dependsOnStepIds ?? [],
        inputAssetSpecs: data.inputAssetSpecs ?? [],
        outputAssetSpecs: data.outputAssetSpecs ?? [],
      };
      setSteps((prev) => [...prev, newStep]);
      setSelectedStepId(newStep.id);
    }
    setSaving(false);
  }, [steps, projectId, workflow.id]);

  const deleteStep = useCallback(
    async (stepId: number) => {
      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), { method: 'DELETE', ...fetchOpts });
      setSteps((prev) => prev.filter((s) => s.id !== stepId));
      if (selectedStepId === stepId) setSelectedStepId(null);
      setDeleteStepConfirm(null);
      setSaving(false);
    },
    [projectId, workflow.id, selectedStepId],
  );

  const reorderStep = useCallback(
    async (stepId: number, direction: 'up' | 'down') => {
      const idx = sortedSteps.findIndex((s) => s.id === stepId);
      if (idx < 0) return;
      const swapIdx = direction === 'up' ? idx - 1 : idx + 1;
      if (swapIdx < 0 || swapIdx >= sortedSteps.length) return;

      const positions: Record<string, number> = {};
      const a = sortedSteps[idx];
      const b = sortedSteps[swapIdx];
      positions[a.id] = b.position;
      positions[b.id] = a.position;

      setSteps((prev) =>
        prev.map((s) => {
          if (s.id === a.id) return { ...s, position: b.position };
          if (s.id === b.id) return { ...s, position: a.position };
          return s;
        }),
      );

      await fetch(stepsReorderApi(projectId, workflow.id), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({ positions }),
      });
    },
    [sortedSteps, projectId, workflow.id],
  );

  // --- Step field save ---
  const saveStepField = useDebouncedCallback(async (stepId: number, field: string, value: unknown) => {
    setSaving(true);
    await fetch(stepApi(projectId, workflow.id, stepId), {
      method: 'PATCH',
      headers: jsonHeaders,
      ...fetchOpts,
      body: JSON.stringify({ step: { [field]: value } }),
    });
    setSaving(false);
  }, 500);

  const saveStepFieldImmediate = useCallback(
    async (stepId: number, field: string, value: unknown) => {
      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({ step: { [field]: value } }),
      });
      setSaving(false);
    },
    [projectId, workflow.id],
  );

  const updateStepField = useCallback(
    (stepId: number, field: string, value: unknown, immediate = false) => {
      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: value } : s)));
      if (immediate) saveStepFieldImmediate(stepId, field, value);
      else saveStepField(stepId, field, value);
    },
    [saveStepField, saveStepFieldImmediate],
  );

  // --- Sub-step management ---
  const addSubStep = useCallback(
    async (stepId: number) => {
      const step = steps.find((s) => s.id === stepId);
      if (!step) return;
      const nextPos = step.subSteps.length + 1;
      setSaving(true);
      const res = await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({
          step: {
            subStepsAttributes: [{ name: `Sub-step ${nextPos}`, position: nextPos, required: true }],
          },
        }),
      });
      if (res.ok) {
        const json = await res.json();
        const stepData = json.data ?? json;
        setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, subSteps: stepData.subSteps ?? [] } : s)));
      }
      setSaving(false);
    },
    [steps, projectId, workflow.id],
  );

  const removeSubStep = useCallback(
    async (stepId: number, subStepId: number) => {
      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({
          step: { subStepsAttributes: [{ id: subStepId, _destroy: true }] },
        }),
      });
      setSteps((prev) =>
        prev.map((s) => (s.id === stepId ? { ...s, subSteps: s.subSteps.filter((ss) => ss.id !== subStepId) } : s)),
      );
      setSaving(false);
    },
    [projectId, workflow.id],
  );

  const updateSubStepField = useDebouncedCallback(
    async (stepId: number, subStepId: number, field: string, value: unknown) => {
      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({
          step: { subStepsAttributes: [{ id: subStepId, [field]: value }] },
        }),
      });
      setSaving(false);
    },
    500,
  );

  const handleSubStepChange = useCallback(
    (stepId: number, subStepId: number, field: string, value: unknown) => {
      setSteps((prev) =>
        prev.map((s) =>
          s.id === stepId
            ? { ...s, subSteps: s.subSteps.map((ss) => (ss.id === subStepId ? { ...ss, [field]: value } : ss)) }
            : s,
        ),
      );
      updateSubStepField(stepId, subStepId, field, value);
    },
    [updateSubStepField],
  );

  const reorderSubSteps = useCallback(
    async (stepId: number, oldIndex: number, newIndex: number) => {
      const step = steps.find((s) => s.id === stepId);
      if (!step) return;

      const sorted = [...step.subSteps].sort((a, b) => a.position - b.position);
      const reordered = arrayMove(sorted, oldIndex, newIndex);
      const updated = reordered.map((ss, i) => ({ ...ss, position: i + 1 }));

      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, subSteps: updated } : s)));

      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({
          step: {
            subStepsAttributes: updated.map((ss) => ({ id: ss.id, position: ss.position })),
          },
        }),
      });
      setSaving(false);
    },
    [steps, projectId, workflow.id],
  );

  const handleSubStepDragEnd = useCallback(
    (stepId: number, event: DragEndEvent) => {
      const { active, over } = event;
      if (!over || active.id === over.id) return;

      const step = steps.find((s) => s.id === stepId);
      if (!step) return;

      const sorted = [...step.subSteps].sort((a, b) => a.position - b.position);
      const oldIndex = sorted.findIndex((ss) => ss.id === active.id);
      const newIndex = sorted.findIndex((ss) => ss.id === over.id);

      if (oldIndex !== -1 && newIndex !== -1) {
        reorderSubSteps(stepId, oldIndex, newIndex);
      }
    },
    [steps, reorderSubSteps],
  );

  const subStepSensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  // --- Multi-select helpers ---
  const toSelectData = (items: NamedItem[]) =>
    Array.isArray(items)
      ? items.filter((i) => i?.id != null).map((i) => ({ value: String(i.id), label: i.name ?? '' }))
      : [];
  const toStringArr = (ids: number[]) => (Array.isArray(ids) ? ids : []).map(String);
  const toNumberArr = (vals: string[]) => (Array.isArray(vals) ? vals : []).map(Number);

  const dependencyOptions = useMemo(
    () =>
      sortedSteps
        .filter((s) => s.id !== selectedStepId)
        .map((s) => ({
          value: String(s.id),
          label: `${s.position}. ${s.name}`,
        })),
    [sortedSteps, selectedStepId],
  );

  // --- Asset Specs handlers ---
  const saveAssetSpecs = useCallback(
    async (stepId: number, field: string, specs: AssetSpec[]) => {
      setSaving(true);
      await fetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        ...fetchOpts,
        body: JSON.stringify({ step: { [field]: specs } }),
      });
      setSaving(false);
    },
    [projectId, workflow.id],
  );

  const debouncedSaveAssetSpecs = useDebouncedCallback(
    (stepId: number, field: string, specs: AssetSpec[]) => saveAssetSpecs(stepId, field, specs),
    500,
  );

  const handleAssetSpecsChange = useCallback(
    (stepId: number, field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => {
      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: specs } : s)));
      debouncedSaveAssetSpecs(stepId, field, specs);
    },
    [debouncedSaveAssetSpecs],
  );

  return (
    <>
      <Head title={project ? `${workflow.name} — ${project.name}` : `${workflow.name} — Company Workflows`} />
      {readOnly && (
        <Alert
          icon={<IconInfoCircle size={16} />}
          color="blue"
          mb={0}
          radius={0}
          style={{ margin: '-24px -32px 0', borderBottom: '1px solid var(--mantine-color-dark-4)' }}
        >
          This is a company-level workflow. Copy it to your project to customize.
        </Alert>
      )}

      <div className={classes.root}>
        {/* ===== SIDEBAR ===== */}
        <div className={classes.sidebar}>
          <div className={classes.sidebarHeader}>
            <Group justify="space-between">
              <Group gap="xs">
                <ActionIcon variant="subtle" size="sm" onClick={() => router.visit(backPath)}>
                  <IconChevronLeft size={16} />
                </ActionIcon>
                <Box>
                  <Text size="sm" fw={600}>
                    Steps
                  </Text>
                  <Text size="xs" c="dimmed">
                    {steps.length} step{steps.length !== 1 ? 's' : ''}
                  </Text>
                </Box>
              </Group>
              {saving && (
                <Badge size="xs" variant="dot" color="yellow">
                  Saving
                </Badge>
              )}
            </Group>
          </div>

          <div className={classes.stepsList}>
            {sortedSteps.map((step, idx) => {
              const isSelected = step.id === selectedStepId;
              return (
                <div
                  key={step.id}
                  className={`${classes.stepCard} ${isSelected ? classes.stepCardSelected : ''}`}
                  onClick={() => setSelectedStepId(step.id)}
                >
                  <Group justify="space-between" wrap="nowrap">
                    <Group gap="xs" style={{ flex: 1, minWidth: 0 }}>
                      <Text size="xs" c="dimmed" fw={700} w={20} ta="center">
                        {step.position}
                      </Text>
                      <Box style={{ flex: 1, minWidth: 0 }}>
                        <Text size="sm" fw={500} truncate>
                          {step.name || 'Untitled'}
                        </Text>
                        {step.agentId && (
                          <Text size="xs" c="dimmed" truncate>
                            {agents.find((a) => a.id === step.agentId)?.name ?? 'Agent'}
                          </Text>
                        )}
                      </Box>
                    </Group>
                    {!readOnly && (
                      <Group gap={0}>
                        <ActionIcon
                          size="xs"
                          variant="subtle"
                          c="dimmed"
                          disabled={idx === 0}
                          onClick={(e) => {
                            e.stopPropagation();
                            reorderStep(step.id, 'up');
                          }}
                        >
                          <IconChevronUp size={12} />
                        </ActionIcon>
                        <ActionIcon
                          size="xs"
                          variant="subtle"
                          c="dimmed"
                          disabled={idx === sortedSteps.length - 1}
                          onClick={(e) => {
                            e.stopPropagation();
                            reorderStep(step.id, 'down');
                          }}
                        >
                          <IconChevronDown size={12} />
                        </ActionIcon>
                      </Group>
                    )}
                  </Group>
                  <Group gap={4} mt={4} wrap="wrap">
                    {step.allowNonInteractive && (
                      <Badge size="xs" variant="outline">
                        Auto
                      </Badge>
                    )}
                    {step.bmadEnabled && (
                      <Badge size="xs" color="blue" variant="outline">
                        BMAD
                      </Badge>
                    )}
                    {step.requiredAgentRuntime && (
                      <Badge size="xs" color="yellow" variant="outline">
                        {AVAILABLE_RUNTIMES.find((a) => a.value === step.requiredAgentRuntime)?.label ??
                          step.requiredAgentRuntime}
                      </Badge>
                    )}
                    {step.dependsOnStepIds.length === 0 && (
                      <Badge size="xs" variant="outline" color="gray">
                        Root
                      </Badge>
                    )}
                    {step.dependsOnStepIds.length > 0 && (
                      <Tooltip
                        label={step.dependsOnStepIds.map((id) => steps.find((s) => s.id === id)?.name ?? id).join(', ')}
                      >
                        <Badge
                          size="xs"
                          variant="outline"
                          color="grape"
                          maw={160}
                          style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}
                        >
                          after:{' '}
                          {step.dependsOnStepIds.map((id) => steps.find((s) => s.id === id)?.name ?? id).join(', ')}
                        </Badge>
                      </Tooltip>
                    )}
                  </Group>
                </div>
              );
            })}
          </div>

          {!readOnly && (
            <div className={classes.sidebarFooter}>
              <Button
                fullWidth
                variant="light"
                size="xs"
                leftSection={<IconPlus size={14} />}
                onClick={createStep}
                loading={saving}
              >
                Add Step
              </Button>
            </div>
          )}

          {/* Base Resources — workflow-level, in sidebar */}
          <div className={classes.sidebarBase}>
            <Accordion variant="contained" radius="sm">
              <Accordion.Item value="base-resources">
                <Accordion.Control>
                  <Group gap="xs">
                    <IconTool size={14} />
                    <Text size="xs" fw={600}>
                      Base Resources
                    </Text>
                  </Group>
                </Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    <Switch
                      label="Inherit all project resources"
                      size="xs"
                      checked={workflow.inheritAllProjectResources}
                      onChange={(e) => updateWorkflowField('inheritAllProjectResources', e.currentTarget.checked)}
                      disabled={readOnly}
                    />
                    {workflow.inheritAllProjectResources && (
                      <Text size="xs" c="dimmed">
                        All project tools, skills, and MCP servers are available in every step.
                      </Text>
                    )}
                    <MultiSelect
                      label="Tools"
                      size="xs"
                      data={toSelectData(tools)}
                      value={toStringArr(workflow.baseToolIds)}
                      onChange={(v) => updateWorkflowField('baseToolIds', toNumberArr(v))}
                      disabled={readOnly || workflow.inheritAllProjectResources}
                      searchable
                    />
                    <MultiSelect
                      label="Skills"
                      size="xs"
                      data={toSelectData(skills)}
                      value={toStringArr(workflow.baseSkillIds)}
                      onChange={(v) => updateWorkflowField('baseSkillIds', toNumberArr(v))}
                      disabled={readOnly || workflow.inheritAllProjectResources}
                      searchable
                    />
                    <MultiSelect
                      label="MCP Servers"
                      size="xs"
                      data={toSelectData(mcpServers)}
                      value={toStringArr(workflow.baseMCPServerIds)}
                      onChange={(v) => updateWorkflowField('baseMCPServerIds', toNumberArr(v))}
                      disabled={readOnly || workflow.inheritAllProjectResources}
                      searchable
                    />
                    <MultiSelect
                      label="Assets"
                      size="xs"
                      data={toSelectData(assets)}
                      value={toStringArr(workflow.baseAssetIds)}
                      onChange={(v) => updateWorkflowField('baseAssetIds', toNumberArr(v))}
                      disabled={readOnly || workflow.inheritAllProjectResources}
                      searchable
                    />
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            </Accordion>
          </div>
        </div>

        {/* ===== MAIN AREA ===== */}
        <div className={classes.mainArea}>
          <div className={classes.mainHeader}>
            <Group justify="space-between">
              <Group gap="sm" style={{ flex: 1 }}>
                {readOnly ? (
                  <Text fw={600} size="lg">
                    {workflow.name}
                  </Text>
                ) : (
                  <TextInput
                    value={workflow.name}
                    onChange={(e) => updateWorkflowField('name', e.currentTarget.value)}
                    variant="unstyled"
                    styles={{ input: { fontWeight: 600, fontSize: 20 } }}
                    style={{ flex: 1 }}
                  />
                )}
                <Badge size="sm" variant="outline">
                  {workflow.scopeIndicator}
                </Badge>
              </Group>
              {project && (
                <Button
                  size="sm"
                  leftSection={<IconPlayerPlay size={14} />}
                  disabled={readOnly || steps.length === 0}
                  onClick={() => setRunModalOpen(true)}
                >
                  Run
                </Button>
              )}
            </Group>
            {!readOnly && (
              <Textarea
                value={workflow.description ?? ''}
                onChange={(e) => updateWorkflowField('description', e.currentTarget.value)}
                placeholder="Add a description..."
                autosize
                minRows={1}
                maxRows={3}
                variant="unstyled"
                size="sm"
                mt={4}
              />
            )}
          </div>

          <div className={classes.mainContent}>
            {selectedStep ? (
              <div key={selectedStep.id} className={classes.detailPanel}>
                {/* Step header */}
                <Group justify="space-between" mb="md">
                  <Group gap="xs">
                    <Badge variant="filled" size="lg" circle>
                      {selectedStep.position}
                    </Badge>
                    <Text size="lg" fw={600}>
                      {selectedStep.name || 'Untitled step'}
                    </Text>
                  </Group>
                  {!readOnly && (
                    <Tooltip label="Delete step">
                      <ActionIcon color="red" variant="subtle" onClick={() => setDeleteStepConfirm(selectedStep.id)}>
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Tooltip>
                  )}
                </Group>

                {/* Configuration — always visible */}
                <Stack gap="sm" mb="lg">
                  <TextInput
                    label="Name"
                    size="sm"
                    value={selectedStep.name}
                    onChange={(e) => updateStepField(selectedStep.id, 'name', e.currentTarget.value)}
                    disabled={readOnly}
                  />
                  <Textarea
                    label="Description"
                    size="sm"
                    value={selectedStep.description ?? ''}
                    onChange={(e) => updateStepField(selectedStep.id, 'description', e.currentTarget.value)}
                    autosize
                    minRows={2}
                    disabled={readOnly}
                  />
                  <Textarea
                    label="Instructions"
                    size="sm"
                    value={selectedStep.instructions ?? ''}
                    onChange={(e) => updateStepField(selectedStep.id, 'instructions', e.currentTarget.value)}
                    autosize
                    minRows={6}
                    placeholder="Enter step instructions... Use {{artifact_name}} for variable references."
                    disabled={readOnly}
                  />
                  <Group grow>
                    <Select
                      label="Agent"
                      size="sm"
                      data={[{ value: '', label: 'No agent' }, ...toSelectData(agents)]}
                      value={selectedStep.agentId ? String(selectedStep.agentId) : ''}
                      onChange={(v) => updateStepField(selectedStep.id, 'agentId', v ? Number(v) : null, true)}
                      disabled={readOnly}
                      clearable
                    />
                    <Select
                      label="Required Runtime"
                      size="sm"
                      data={[{ value: '', label: 'None (default)' }, ...AVAILABLE_RUNTIMES]}
                      value={selectedStep.requiredAgentRuntime ?? ''}
                      onChange={(v) => {
                        const runtime = v || null;
                        if (runtime === selectedStep.requiredAgentRuntime) return;
                        setSteps((prev) =>
                          prev.map((s) =>
                            s.id === selectedStep.id
                              ? { ...s, requiredAgentRuntime: runtime, preferredModel: null }
                              : s,
                          ),
                        );
                        setSaving(true);
                        fetch(stepApi(projectId, workflow.id, selectedStep.id), {
                          method: 'PATCH',
                          headers: jsonHeaders,
                          ...fetchOpts,
                          body: JSON.stringify({ step: { requiredAgentRuntime: runtime, preferredModel: null } }),
                        }).finally(() => setSaving(false));
                      }}
                      disabled={readOnly}
                      clearable
                    />
                  </Group>
                  {selectedStep.requiredAgentRuntime &&
                    (() => {
                      const runtime = selectedStep.requiredAgentRuntime!;
                      const runtimeModels = modelsMap[runtime] ?? [];
                      const current = selectedStep.preferredModel;
                      const options = runtimeModels
                        .filter((m) => m.modelId)
                        .map((m) => ({ value: m.modelId, label: m.displayName || m.modelId }));
                      const modelOptions =
                        current && !options.some((o) => o.value === current)
                          ? [...options, { value: current, label: current }]
                          : options;
                      return (
                        <Select
                          label="Preferred Model"
                          size="sm"
                          data={modelOptions}
                          value={current ?? null}
                          onChange={(v) => updateStepField(selectedStep.id, 'preferredModel', v || null, true)}
                          placeholder="Default (runtime selects)"
                          disabled={readOnly}
                          clearable
                          searchable
                        />
                      );
                    })()}
                </Stack>

                {/* Collapsible sections — Mantine Accordion */}
                <Accordion variant="separated" multiple defaultValue={['execution']}>
                  {/* Execution */}
                  <Accordion.Item value="execution">
                    <Accordion.Control>
                      <AccordionLabel icon={<IconBolt size={16} />} label="Execution" />
                    </Accordion.Control>
                    <Accordion.Panel>
                      <Stack gap="sm">
                        <Switch
                          label="Auto-run available"
                          size="sm"
                          description="Skip user approval in non-interactive/mixed modes"
                          checked={selectedStep.allowNonInteractive}
                          onChange={(e) =>
                            updateStepField(selectedStep.id, 'allowNonInteractive', e.currentTarget.checked, true)
                          }
                          disabled={readOnly}
                        />
                        <Group grow>
                          <Select
                            label="Skip Policy"
                            size="sm"
                            data={SKIP_POLICIES}
                            value={selectedStep.skipPolicy}
                            onChange={(v) => updateStepField(selectedStep.id, 'skipPolicy', v ?? 'never', true)}
                            disabled={readOnly}
                          />
                          <Select
                            label="On Failure"
                            size="sm"
                            data={ON_FAILURE_OPTIONS}
                            value={selectedStep.onFailure}
                            onChange={(v) => updateStepField(selectedStep.id, 'onFailure', v ?? 'fail', true)}
                            disabled={readOnly}
                          />
                          {selectedStep.onFailure === 'retry' && (
                            <NumberInput
                              label="Max Retries"
                              size="sm"
                              value={selectedStep.maxRetries}
                              onChange={(v) => updateStepField(selectedStep.id, 'maxRetries', Number(v) || 0, true)}
                              min={0}
                              max={10}
                              disabled={readOnly}
                            />
                          )}
                        </Group>
                        <Switch
                          label="Mount repositories"
                          size="sm"
                          description="Repositories are selected when running the workflow"
                          checked={selectedStep.mountRepositories}
                          onChange={(e) =>
                            updateStepField(selectedStep.id, 'mountRepositories', e.currentTarget.checked, true)
                          }
                          disabled={readOnly}
                        />
                        <Switch
                          label="BMAD Method"
                          size="sm"
                          description="Enable the BMAD methodology for this step"
                          checked={selectedStep.bmadEnabled}
                          onChange={(e) =>
                            updateStepField(selectedStep.id, 'bmadEnabled', e.currentTarget.checked, true)
                          }
                          disabled={readOnly}
                        />
                      </Stack>
                    </Accordion.Panel>
                  </Accordion.Item>

                  {/* Resources */}
                  <Accordion.Item value="resources">
                    <Accordion.Control>
                      <AccordionLabel icon={<IconTool size={16} />} label="Resources" />
                    </Accordion.Control>
                    <Accordion.Panel>
                      <Stack gap="sm">
                        <MultiSelect
                          label="Tools"
                          size="sm"
                          data={toSelectData(tools)}
                          value={toStringArr(selectedStep.toolIds)}
                          onChange={(v) => updateStepField(selectedStep.id, 'toolIds', toNumberArr(v), true)}
                          placeholder="Select tools..."
                          disabled={readOnly}
                          searchable
                        />
                        <MultiSelect
                          label="MCP Servers"
                          size="sm"
                          data={toSelectData(mcpServers)}
                          value={toStringArr(selectedStep.mcpServerIds)}
                          onChange={(v) => updateStepField(selectedStep.id, 'mcpServerIds', toNumberArr(v), true)}
                          placeholder="Select MCP servers..."
                          disabled={readOnly}
                          searchable
                        />
                        <MultiSelect
                          label="Skills"
                          size="sm"
                          data={toSelectData(skills)}
                          value={toStringArr(selectedStep.skillIds)}
                          onChange={(v) => updateStepField(selectedStep.id, 'skillIds', toNumberArr(v), true)}
                          placeholder="Select skills..."
                          disabled={readOnly}
                          searchable
                        />
                      </Stack>
                    </Accordion.Panel>
                  </Accordion.Item>

                  {/* Dependencies */}
                  <Accordion.Item value="dependencies">
                    <Accordion.Control>
                      <AccordionLabel icon={<IconGitBranch size={16} />} label="Dependencies" />
                    </Accordion.Control>
                    <Accordion.Panel>
                      <MultiSelect
                        size="sm"
                        data={dependencyOptions}
                        value={toStringArr(selectedStep.dependsOnStepIds)}
                        onChange={(v) => updateStepField(selectedStep.id, 'dependsOnStepIds', toNumberArr(v), true)}
                        placeholder="Select steps this step depends on..."
                        disabled={readOnly}
                        searchable
                      />
                      <Text size="xs" c="dimmed" mt={4}>
                        {selectedStep.dependsOnStepIds.length === 0
                          ? 'No dependencies — this step can run in parallel with other root steps'
                          : 'This step will start after all selected steps complete'}
                      </Text>
                    </Accordion.Panel>
                  </Accordion.Item>

                  {/* Sub-steps */}
                  <Accordion.Item value="sub-steps">
                    <Accordion.Control>
                      <AccordionLabel
                        icon={<IconListCheck size={16} />}
                        label={`Sub-steps (${selectedStep.subSteps.length})`}
                      />
                    </Accordion.Control>
                    <Accordion.Panel>
                      <Stack gap="sm">
                        <DndContext
                          sensors={subStepSensors}
                          collisionDetection={closestCenter}
                          onDragEnd={(event) => handleSubStepDragEnd(selectedStep.id, event)}
                        >
                          <SortableContext
                            items={[...selectedStep.subSteps]
                              .sort((a, b) => a.position - b.position)
                              .map((ss) => ss.id)}
                            strategy={verticalListSortingStrategy}
                          >
                            <Stack gap="sm">
                              {[...selectedStep.subSteps]
                                .sort((a, b) => a.position - b.position)
                                .map((ss) => (
                                  <SortableSubStep
                                    key={ss.id}
                                    ss={ss}
                                    stepId={selectedStep.id}
                                    readOnly={readOnly}
                                    onRemove={removeSubStep}
                                    onChange={handleSubStepChange}
                                  />
                                ))}
                            </Stack>
                          </SortableContext>
                        </DndContext>
                        {!readOnly && (
                          <Button
                            size="xs"
                            variant="light"
                            leftSection={<IconPlus size={12} />}
                            onClick={() => addSubStep(selectedStep.id)}
                            w="fit-content"
                          >
                            Add Sub-step
                          </Button>
                        )}
                      </Stack>
                    </Accordion.Panel>
                  </Accordion.Item>

                  {/* Asset Specs — merged into one section */}
                  <Accordion.Item value="asset-specs">
                    <Accordion.Control>
                      <AccordionLabel icon={<IconFileDescription size={16} />} label="Asset Specs" />
                    </Accordion.Control>
                    <Accordion.Panel>
                      <Text size="sm" fw={600} mb="xs">
                        Input
                      </Text>
                      <AssetSpecsEditor
                        specs={selectedStep.inputAssetSpecs ?? []}
                        onChange={(specs) => handleAssetSpecsChange(selectedStep.id, 'inputAssetSpecs', specs)}
                        showNamePattern={false}
                        disabled={readOnly}
                      />
                      <Divider my="md" />
                      <Text size="sm" fw={600} mb="xs">
                        Output
                      </Text>
                      <AssetSpecsEditor
                        specs={selectedStep.outputAssetSpecs ?? []}
                        onChange={(specs) => handleAssetSpecsChange(selectedStep.id, 'outputAssetSpecs', specs)}
                        showNamePattern
                        disabled={readOnly}
                      />
                    </Accordion.Panel>
                  </Accordion.Item>
                </Accordion>
              </div>
            ) : (
              <div className={classes.emptyState}>
                <Text style={{ fontSize: 48 }}>🔧</Text>
                <Text size="lg" fw={600}>
                  {steps.length === 0 ? 'No steps yet' : 'Select a step to configure'}
                </Text>
                <Text size="sm" c="dimmed">
                  {steps.length === 0
                    ? 'Add your first workflow step to get started'
                    : 'Click on a step in the sidebar to edit its configuration'}
                </Text>
                {steps.length === 0 && !readOnly && (
                  <Button onClick={createStep} leftSection={<IconPlus size={14} />} loading={saving} mt="sm">
                    Add First Step
                  </Button>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Delete step confirmation */}
      <Modal
        opened={deleteStepConfirm !== null}
        onClose={() => setDeleteStepConfirm(null)}
        title="Delete Step"
        centered
        size="sm"
      >
        <Text size="sm" mb="md">
          Are you sure you want to delete this step? This action cannot be undone.
        </Text>
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setDeleteStepConfirm(null)}>
            Cancel
          </Button>
          <Button color="red" onClick={() => deleteStepConfirm && deleteStep(deleteStepConfirm)} loading={saving}>
            Delete
          </Button>
        </Group>
      </Modal>

      {project && (
        <RunWorkflowModal
          opened={runModalOpen}
          onClose={() => setRunModalOpen(false)}
          workflowId={workflow.id}
          workflowName={workflow.name}
          steps={steps.map((s) => ({
            id: s.id,
            name: s.name,
            position: s.position,
            allowNonInteractive: s.allowNonInteractive,
            dependsOnStepIds: s.dependsOnStepIds,
          }))}
          projectId={project.id}
          configuredAgents={configuredAgents}
          agentModels={agentModels}
          repositories={repositories}
          assets={assets}
        />
      )}
    </>
  );
};

setPageLayout(BuilderPage, persistentProjectLayout);

export default BuilderPage;
