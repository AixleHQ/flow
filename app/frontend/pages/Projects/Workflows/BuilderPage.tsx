import { arrayMove } from '@dnd-kit/sortable';
import { Head, router, usePage } from '@inertiajs/react';
import { ActionIcon, Alert, Box, Button, Group, Modal, Tabs, Text, Textarea, TextInput, Tooltip } from '@mantine/core';
import { IconBolt, IconChevronLeft, IconInfoCircle, IconPlayerPlay } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { RunWorkflowModal } from 'shared/components/RunWorkflowModal';
import { apiFetch } from 'shared/lib/apiFetch';
import {
  apiV1ProjectWorkflowPath,
  apiV1ProjectWorkflowStepsPath,
  apiV1ProjectWorkflowStepPath,
  reorderApiV1ProjectWorkflowStepsPath,
} from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import { BaseResourcesTab } from './BaseResourcesTab';
import classes from './BuilderPage.module.css';
import { SaveChip } from './SaveChip';
import { SessionEditorPanel } from './SessionEditorPanel';
import { SessionTreeNav } from './SessionTreeNav';
import type { Selection } from './SessionTreeNav';
import { StepEditorPanel } from './StepEditorPanel';
import { TriggersTab } from './TriggersTab';
import { useSavingState } from './useSavingState';

interface Project {
  id: number;
  name: string;
}
type ProjectOrNull = Project | null;
interface NamedItem {
  id: number;
  name: string;
}

interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
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
  assetIds: number[];
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
  toolGroups?: ToolGroup[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  assets?: NamedItem[];
  repositories?: NamedItem[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  configuredAgents: string[];
  boardColumns?: { id: number; name: string; boundWorkflowName?: string | null }[];
}

const CONFIG_FIELDS = new Set([
  'inheritAllProjectResources',
  'baseToolIds',
  'baseSkillIds',
  'baseMCPServerIds',
  'baseAssetIds',
]);

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

const jsonHeaders = { 'Content-Type': 'application/json' };

const BuilderPage = () => {
  const {
    project,
    workflow: initialWorkflow,
    steps: initialSteps,
    agents: rawAgents,
    tools: rawTools,
    toolGroups: rawToolGroups,
    skills: rawSkills,
    mcpServers: rawMcpServers,
    assets: rawAssets,
    repositories: rawRepositories,
    agentModels: rawAgentModels,
    readOnly,
    configuredAgents,
    boardColumns,
  } = usePage<{ props: Props }>().props as unknown as Props;

  const agents = rawAgents ?? [];
  const tools = rawTools ?? [];
  const toolGroups = rawToolGroups ?? [];
  const skills = rawSkills ?? [];
  const mcpServers = rawMcpServers ?? [];
  const assets = rawAssets ?? [];
  const repositories = rawRepositories ?? [];
  const agentModels = rawAgentModels ?? [];

  const projectId = project?.id ?? null;
  const backPath = projectId ? `/company/projects/${projectId}/workflows` : '/company/projects';

  const [workflow, setWorkflow] = useState(initialWorkflow);
  const [steps, setSteps] = useState(initialSteps);
  const [activeTab, setActiveTab] = useState<string>('sessions');
  const [selection, setSelection] = useState<Selection | null>(() =>
    initialSteps.length > 0 ? { mode: 'session', sessionId: initialSteps[0].id } : null,
  );
  const [deleteStepConfirm, setDeleteStepConfirm] = useState<number | null>(null);
  const [runModalOpen, setRunModalOpen] = useState(false);

  const { saving, withSave } = useSavingState();

  const sortedSteps = useMemo(() => [...steps].sort((a, b) => a.position - b.position), [steps]);

  // Run button guard (AC10)
  const canRun = useMemo(() => steps.some((s) => (s.instructions ?? '').trim().length > 0), [steps]);

  // --- Workflow autosave ---
  const saveWorkflow = useDebouncedCallback(async (field: string, value: unknown) => {
    const payload = CONFIG_FIELDS.has(field)
      ? { workflow: { config: { [field]: value } } }
      : { workflow: { [field]: value } };
    await withSave(
      apiFetch(workflowApi(projectId, workflow.id), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify(payload),
      }),
    );
  }, 500);

  const updateWorkflowField = useCallback(
    (field: string, value: unknown) => {
      setWorkflow((w) => ({ ...w, [field]: value }));
      saveWorkflow(field, value);
    },
    [saveWorkflow],
  );

  // --- Session (Step) CRUD ---
  const createSession = useCallback(
    async (name: string) => {
      const nextPos = steps.length > 0 ? Math.max(...steps.map((s) => s.position)) + 1 : 1;
      const res = await apiFetch(stepsCollectionApi(projectId, workflow.id), {
        method: 'POST',
        headers: jsonHeaders,
        body: JSON.stringify({ step: { name: name || `Session ${nextPos}`, position: nextPos } }),
      });
      await withSave(Promise.resolve(res));
      if (res.ok) {
        const data = await res.json();
        const newStep: Step = {
          ...data,
          subSteps: data.subSteps ?? [],
          toolIds: data.toolIds ?? [],
          mcpServerIds: data.mcpServerIds ?? [],
          skillIds: data.skillIds ?? [],
          assetIds: data.assetIds ?? [],
          dependsOnStepIds: data.dependsOnStepIds ?? [],
          inputAssetSpecs: data.inputAssetSpecs ?? [],
          outputAssetSpecs: data.outputAssetSpecs ?? [],
        };
        setSteps((prev) => [...prev, newStep]);
        setSelection({ mode: 'session', sessionId: newStep.id });
      }
    },
    [steps, projectId, workflow.id, withSave],
  );

  const deleteSession = useCallback(
    async (stepId: number) => {
      await withSave(apiFetch(stepApi(projectId, workflow.id, stepId), { method: 'DELETE' }));
      setSteps((prev) => prev.filter((s) => s.id !== stepId));
      if (selection?.sessionId === stepId) setSelection(null);
      setDeleteStepConfirm(null);
    },
    [projectId, workflow.id, selection, withSave],
  );

  const reorderSessions = useCallback(
    async (oldIndex: number, newIndex: number) => {
      const reordered = arrayMove(sortedSteps, oldIndex, newIndex);
      const updated = reordered.map((s, i) => ({ ...s, position: i + 1 }));
      setSteps(updated);

      const positions: Record<string, number> = {};
      updated.forEach((s) => (positions[s.id] = s.position));
      await withSave(
        apiFetch(stepsReorderApi(projectId, workflow.id), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ positions }),
        }),
      );
    },
    [sortedSteps, projectId, workflow.id, withSave],
  );

  // --- Step field save ---
  const saveStepField = useDebouncedCallback(async (stepId: number, field: string, value: unknown) => {
    await withSave(
      apiFetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({ step: { [field]: value } }),
      }),
    );
  }, 500);

  const saveStepFieldImmediate = useCallback(
    async (stepId: number, field: string, value: unknown) => {
      await withSave(
        apiFetch(stepApi(projectId, workflow.id, stepId), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({ step: { [field]: value } }),
        }),
      );
    },
    [projectId, workflow.id, withSave],
  );

  const updateStepField = useCallback(
    (stepId: number, field: string, value: unknown, immediate = false) => {
      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: value } : s)));
      if (immediate) saveStepFieldImmediate(stepId, field, value);
      else saveStepField(stepId, field, value);
    },
    [saveStepField, saveStepFieldImmediate],
  );

  // --- Sub-step (Step) management ---
  const addSubStep = useCallback(
    async (sessionId: number) => {
      const step = steps.find((s) => s.id === sessionId);
      if (!step) return;
      const nextPos = step.subSteps.length + 1;
      const res = await apiFetch(stepApi(projectId, workflow.id, sessionId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({
          step: {
            subStepsAttributes: [{ name: `Step ${nextPos}`, position: nextPos, required: true }],
          },
        }),
      });
      await withSave(Promise.resolve(res));
      if (res.ok) {
        const json = await res.json();
        const stepData = json.data ?? json;
        const newSubStep = (stepData.subSteps ?? []).at(-1);
        setSteps((prev) => prev.map((s) => (s.id === sessionId ? { ...s, subSteps: stepData.subSteps ?? [] } : s)));
        if (newSubStep) {
          setSelection({ mode: 'step', sessionId, stepId: newSubStep.id });
        }
      }
    },
    [steps, projectId, workflow.id, withSave],
  );

  const removeSubStep = useCallback(
    async (sessionId: number, subStepId: number) => {
      await withSave(
        apiFetch(stepApi(projectId, workflow.id, sessionId), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({
            step: { subStepsAttributes: [{ id: subStepId, _destroy: true }] },
          }),
        }),
      );
      setSteps((prev) =>
        prev.map((s) => (s.id === sessionId ? { ...s, subSteps: s.subSteps.filter((ss) => ss.id !== subStepId) } : s)),
      );
      if (selection?.mode === 'step' && selection.stepId === subStepId) {
        setSelection({ mode: 'session', sessionId });
      }
    },
    [projectId, workflow.id, selection, withSave],
  );

  const updateSubStepField = useDebouncedCallback(
    async (sessionId: number, subStepId: number, field: string, value: unknown) => {
      await withSave(
        apiFetch(stepApi(projectId, workflow.id, sessionId), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({
            step: { subStepsAttributes: [{ id: subStepId, [field]: value }] },
          }),
        }),
      );
    },
    500,
  );

  const handleSubStepFieldChange = useCallback(
    (sessionId: number, subStepId: number, field: string, value: unknown) => {
      setSteps((prev) =>
        prev.map((s) =>
          s.id === sessionId
            ? { ...s, subSteps: s.subSteps.map((ss) => (ss.id === subStepId ? { ...ss, [field]: value } : ss)) }
            : s,
        ),
      );
      updateSubStepField(sessionId, subStepId, field, value);
    },
    [updateSubStepField],
  );

  const reorderSubSteps = useCallback(
    async (sessionId: number, oldIndex: number, newIndex: number) => {
      const step = steps.find((s) => s.id === sessionId);
      if (!step) return;
      const sorted = [...step.subSteps].sort((a, b) => a.position - b.position);
      const reordered = arrayMove(sorted, oldIndex, newIndex);
      const updated = reordered.map((ss, i) => ({ ...ss, position: i + 1 }));
      setSteps((prev) => prev.map((s) => (s.id === sessionId ? { ...s, subSteps: updated } : s)));
      await withSave(
        apiFetch(stepApi(projectId, workflow.id, sessionId), {
          method: 'PATCH',
          headers: jsonHeaders,
          body: JSON.stringify({
            step: { subStepsAttributes: updated.map((ss) => ({ id: ss.id, position: ss.position })) },
          }),
        }),
      );
    },
    [steps, projectId, workflow.id, withSave],
  );

  const debouncedSaveAssetSpecs = useDebouncedCallback(async (stepId: number, field: string, specs: AssetSpec[]) => {
    await withSave(
      apiFetch(stepApi(projectId, workflow.id, stepId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({ step: { [field]: specs } }),
      }),
    );
  }, 500);

  const handleAssetSpecsChange = useCallback(
    (stepId: number, field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => {
      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: specs } : s)));
      debouncedSaveAssetSpecs(stepId, field, specs);
    },
    [debouncedSaveAssetSpecs],
  );

  // Derive selected session and step from selection state
  const selectedSession = useMemo(
    () => (selection ? (steps.find((s) => s.id === selection.sessionId) ?? null) : null),
    [steps, selection],
  );

  const selectedSubStep = useMemo(() => {
    if (!selection || selection.mode !== 'step' || !selectedSession) return null;
    return selectedSession.subSteps.find((ss) => ss.id === selection.stepId) ?? null;
  }, [selection, selectedSession]);

  return (
    <>
      <Head title={project ? `${workflow.name} — ${project.name}` : `${workflow.name}`} />

      {readOnly && (
        <Alert
          icon={<IconInfoCircle size={16} />}
          color="blue"
          mb={0}
          radius={0}
          style={{ margin: '-24px -32px 0', borderBottom: '1px solid var(--app-border-default)' }}
        >
          This is a company-level workflow. Copy it to your project to customize.
        </Alert>
      )}

      <div className={classes.builderLayout}>
        {/* ===== HEADER (AC3) ===== */}
        <div className={classes.builderHeader}>
          <Group justify="space-between" wrap="nowrap">
            <Group gap="sm" style={{ flex: 1, minWidth: 0 }}>
              <ActionIcon
                variant="subtle"
                size="sm"
                style={{ color: 'var(--text-2)', flexShrink: 0 }}
                onClick={() => router.visit(backPath)}
              >
                <IconChevronLeft size={16} />
              </ActionIcon>
              <Box style={{ flex: 1, minWidth: 0 }}>
                {readOnly ? (
                  <Text fw={700} size="lg" style={{ color: 'var(--text-1)' }}>
                    {workflow.name}
                  </Text>
                ) : (
                  <TextInput
                    value={workflow.name}
                    onChange={(e) => updateWorkflowField('name', e.currentTarget.value)}
                    variant="unstyled"
                    classNames={{ input: classes.headerNameInput }}
                    placeholder="Workflow name…"
                  />
                )}
                {!readOnly && (
                  <Textarea
                    value={workflow.description ?? ''}
                    onChange={(e) => updateWorkflowField('description', e.currentTarget.value)}
                    placeholder="Add a description…"
                    autosize
                    minRows={1}
                    maxRows={2}
                    variant="unstyled"
                    size="xs"
                    styles={{ input: { color: 'var(--text-2)', padding: '1px 0' } }}
                  />
                )}
              </Box>
              <Box
                px={8}
                py={2}
                style={{
                  background: 'var(--bg-card)',
                  border: '1px solid var(--border)',
                  borderRadius: 4,
                  flexShrink: 0,
                }}
              >
                <Text size="xs" style={{ color: 'var(--text-2)' }}>
                  {workflow.scopeIndicator}
                </Text>
              </Box>
            </Group>

            <Group gap="sm" style={{ flexShrink: 0 }}>
              <SaveChip saving={saving} />
              {project && !readOnly && (
                <Tooltip label="Add instructions to at least one session to run" disabled={canRun}>
                  <Button
                    size="sm"
                    leftSection={<IconPlayerPlay size={14} />}
                    disabled={!canRun}
                    onClick={() => setRunModalOpen(true)}
                    style={{ background: canRun ? 'var(--accent)' : undefined }}
                  >
                    Run
                  </Button>
                </Tooltip>
              )}
            </Group>
          </Group>
        </div>

        {/* ===== TAB BAR (AC4) ===== */}
        <div className={classes.builderTabBar}>
          <Tabs
            value={activeTab}
            onChange={(v) => setActiveTab(v ?? 'sessions')}
            styles={{
              tab: {
                color: 'var(--text-2)',
                borderBottom: '2px solid transparent',
                '&[dataActive]': {
                  color: 'var(--accent)',
                  borderBottomColor: 'var(--accent)',
                },
              },
            }}
          >
            <Tabs.List style={{ borderBottom: 'none' }}>
              <Tabs.Tab value="sessions">Sessions</Tabs.Tab>
              <Tabs.Tab value="triggers" leftSection={<IconBolt size={14} />}>
                Triggers
              </Tabs.Tab>
              <Tabs.Tab value="base-resources">Base Resources</Tabs.Tab>
            </Tabs.List>
          </Tabs>
        </div>

        {/* ===== TAB CONTENT ===== */}
        <div className={classes.builderTabContent}>
          {/* Sessions Tab (AC5) */}
          {activeTab === 'sessions' && (
            <div className={classes.sessionsLayout}>
              {/* Tree nav */}
              <SessionTreeNav
                steps={sortedSteps}
                selection={selection}
                readOnly={readOnly}
                onSelectSession={(id) => setSelection({ mode: 'session', sessionId: id })}
                onSelectStep={(sessionId, stepId) => setSelection({ mode: 'step', sessionId, stepId })}
                onDeleteSession={(id) => setDeleteStepConfirm(id)}
                onDeleteStep={removeSubStep}
                onAddSession={createSession}
                onAddStep={addSubStep}
                onReorderSessions={reorderSessions}
                onReorderSteps={reorderSubSteps}
              />

              {/* Editor area */}
              <div className={classes.editorArea}>
                {selection && selectedSession ? (
                  selection.mode === 'session' ? (
                    <SessionEditorPanel
                      key={selectedSession.id}
                      step={selectedSession}
                      allSteps={sortedSteps}
                      agents={agents}
                      tools={tools}
                      toolGroups={toolGroups}
                      skills={skills}
                      mcpServers={mcpServers}
                      readOnly={readOnly}
                      onFieldChange={(field, value, immediate) =>
                        updateStepField(selectedSession.id, field, value, immediate)
                      }
                      onAssetSpecsChange={(field, specs) => handleAssetSpecsChange(selectedSession.id, field, specs)}
                    />
                  ) : selectedSubStep ? (
                    <StepEditorPanel
                      key={selectedSubStep.id}
                      step={selectedSubStep}
                      readOnly={readOnly}
                      onFieldChange={(field, value) =>
                        handleSubStepFieldChange(selectedSession.id, selectedSubStep.id, field, value)
                      }
                    />
                  ) : null
                ) : (
                  <div className={classes.emptyState}>
                    <Text style={{ fontSize: 48 }}>🔧</Text>
                    <Text size="lg" fw={600} style={{ color: 'var(--text-1)' }}>
                      {steps.length === 0 ? 'No sessions yet' : 'Select a session to configure'}
                    </Text>
                    <Text size="sm" style={{ color: 'var(--text-2)' }}>
                      {steps.length === 0
                        ? 'Add your first session to get started'
                        : 'Click on a session in the sidebar to edit its configuration'}
                    </Text>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Triggers Tab (AC6) */}
          {activeTab === 'triggers' && project && (
            <TriggersTab
              projectId={project.id}
              workflowId={workflow.id}
              columns={boardColumns ?? []}
              sessions={sortedSteps.map((s) => ({ id: s.id, name: s.name }))}
              readOnly={readOnly}
            />
          )}

          {/* Base Resources Tab (AC7) */}
          {activeTab === 'base-resources' && (
            <BaseResourcesTab
              workflow={workflow}
              tools={tools}
              toolGroups={toolGroups}
              skills={skills}
              mcpServers={mcpServers}
              assets={assets}
              readOnly={readOnly}
              onWorkflowChange={updateWorkflowField}
            />
          )}
        </div>
      </div>

      {/* Delete session confirmation */}
      <Modal
        opened={deleteStepConfirm !== null}
        onClose={() => setDeleteStepConfirm(null)}
        title="Delete Session"
        centered
        size="sm"
      >
        <Text size="sm" mb="md">
          Are you sure you want to delete this session? This action cannot be undone.
        </Text>
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setDeleteStepConfirm(null)}>
            Cancel
          </Button>
          <Button color="red" onClick={() => deleteStepConfirm && deleteSession(deleteStepConfirm)}>
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
