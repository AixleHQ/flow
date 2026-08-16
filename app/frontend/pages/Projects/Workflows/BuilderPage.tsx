import { arrayMove } from '@dnd-kit/sortable';
import { Head, router, usePage } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Text, TextInput, Tooltip } from '@mantine/core';
import { IconArrowLeft, IconInfoCircle, IconPlayerPlay } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import type { ConfigItemPicker } from '@/types/generated';

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
  instructions: string | null;
  position: number;
  agentId: number | null;
  requiredAgentRuntime: string | null;
  preferredModel: string | null;
  allowNonInteractive: boolean;
  skipPolicy: string;
  onFailure: string;
  maxRetries: number;
  repositoryIds: number[];
  bmadEnabled: boolean;
  dependsOnStepIds: number[];
  toolIds: number[];
  mcpServerIds: number[];
  skillIds: number[];
  assetIds: number[];
  configItemIds: number[];
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
  baseRepositoryIds: number[];
  baseConfigItemIds: number[];
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
  configItems?: ConfigItemPicker[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  configuredAgents: string[];
  defaultAgentRuntime?: string | null;
  boardColumns?: { id: number; name: string; boundWorkflowName?: string | null }[];
}

const CONFIG_FIELDS = new Set([
  'inheritAllProjectResources',
  'baseToolIds',
  'baseSkillIds',
  'baseMCPServerIds',
  'baseAssetIds',
  'baseRepositoryIds',
  'baseConfigItemIds',
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
    configItems: rawConfigItems,
    agentModels: rawAgentModels,
    readOnly,
    configuredAgents,
    defaultAgentRuntime,
    boardColumns,
  } = usePage<{ props: Props }>().props as unknown as Props;

  const agents = rawAgents ?? [];
  const tools = rawTools ?? [];
  const toolGroups = rawToolGroups ?? [];
  const skills = rawSkills ?? [];
  const mcpServers = rawMcpServers ?? [];
  const assets = rawAssets ?? [];
  const repositories = rawRepositories ?? [];
  const configItems = rawConfigItems ?? [];
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
      try {
        const res = await apiFetch(stepApi(projectId, workflow.id, stepId), { method: 'DELETE' });
        if (!res.ok) {
          console.error('Failed to delete session:', res.statusText);
          return;
        }
        await withSave(Promise.resolve(res));
        setSteps((prev) => prev.filter((s) => s.id !== stepId));
        if (selection?.sessionId === stepId) setSelection(null);
      } catch (error) {
        console.error('Error deleting session:', error);
      } finally {
        setDeleteStepConfirm(null);
      }
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
    async (sessionId: number, stepName?: string) => {
      const step = steps.find((s) => s.id === sessionId);
      if (!step) return;
      const nextPos = step.subSteps.length + 1;
      const name = stepName?.trim() || `Step ${nextPos}`;
      const res = await apiFetch(stepApi(projectId, workflow.id, sessionId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({
          step: {
            subStepsAttributes: [{ name, position: nextPos, required: true }],
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

  // Flush debounced saves on unload to prevent data loss
  useEffect(() => {
    const handleBeforeUnload = () => {
      saveWorkflow.flush();
      saveStepField.flush();
      updateSubStepField.flush();
      debouncedSaveAssetSpecs.flush();
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [saveWorkflow, saveStepField, updateSubStepField, debouncedSaveAssetSpecs]);

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
          {/* The visible title is an editable input, so the document outline
              needs its own h1 — without it the builder has no heading at all. */}
          <h1 className="app-visually-hidden">{workflow.name || 'Untitled workflow'}</h1>
          {/* Row 1: back link | spacer | save chip | run button */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
            <button
              type="button"
              onClick={() => router.visit(backPath)}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 5,
                color: 'var(--text-3)',
                fontSize: 12,
                cursor: 'pointer',
                padding: '3px 6px',
                borderRadius: 4,
                border: '1px solid transparent',
                background: 'transparent',
                transition: 'all 0.12s',
                fontFamily: 'inherit',
              }}
              onMouseEnter={(e) => {
                const b = e.currentTarget;
                b.style.background = 'var(--border-mid, rgba(57,56,55,0.5))';
                b.style.borderColor = 'var(--border)';
                b.style.color = 'var(--text-2)';
              }}
              onMouseLeave={(e) => {
                const b = e.currentTarget;
                b.style.background = 'transparent';
                b.style.borderColor = 'transparent';
                b.style.color = 'var(--text-3)';
              }}
            >
              <IconArrowLeft size={13} /> Workflows
            </button>
            <div style={{ flex: 1 }} />
            <SaveChip saving={saving} />
            {project && !readOnly && (
              <Tooltip label="Add instructions to at least one session to run" disabled={canRun}>
                <button
                  type="button"
                  disabled={!canRun}
                  onClick={() => setRunModalOpen(true)}
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 4,
                    padding: '4px 12px',
                    borderRadius: 4,
                    fontFamily: 'inherit',
                    fontSize: 12,
                    fontWeight: 600,
                    cursor: canRun ? 'pointer' : 'not-allowed',
                    border: canRun ? '1px solid var(--accent-muted)' : '1px solid var(--border)',
                    background: canRun ? 'var(--accent-dim)' : 'var(--bg-card)',
                    color: canRun ? 'var(--accent-text)' : 'var(--text-3)',
                    marginLeft: 8,
                    transition: 'background 0.12s, border-color 0.12s',
                  }}
                >
                  <IconPlayerPlay size={12} /> Run
                </button>
              </Tooltip>
            )}
          </div>

          {/* Row 2: editable title + scope tag */}
          <div style={{ display: 'flex', alignItems: 'flex-start' }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 2 }}>
                {readOnly ? (
                  <span
                    style={{
                      fontSize: 18,
                      fontWeight: 700,
                      color: 'var(--text-1)',
                      letterSpacing: '-0.02em',
                    }}
                  >
                    {workflow.name}
                  </span>
                ) : (
                  <TextInput
                    value={workflow.name}
                    onChange={(e) => updateWorkflowField('name', e.currentTarget.value)}
                    variant="unstyled"
                    classNames={{ input: classes.headerNameInput }}
                    placeholder="Workflow name…"
                    aria-label="Workflow name"
                  />
                )}
                <span
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: '0.05em',
                    textTransform: 'uppercase',
                    padding: '2px 8px',
                    borderRadius: 4,
                    border: '1px solid var(--border)',
                    background: 'var(--bg-card)',
                    color: 'var(--text-2)',
                    flexShrink: 0,
                    whiteSpace: 'nowrap',
                    lineHeight: 1.5,
                  }}
                >
                  {workflow.scopeIndicator}
                </span>
              </div>
              {/* Row 3: editable description */}
              {readOnly ? (
                workflow.description && (
                  <p style={{ margin: 0, fontSize: 13, color: 'var(--text-2)', lineHeight: 1.5 }}>
                    {workflow.description}
                  </p>
                )
              ) : (
                <textarea
                  value={workflow.description ?? ''}
                  onChange={(e) => updateWorkflowField('description', e.currentTarget.value)}
                  placeholder="Add a description…"
                  aria-label="Workflow description"
                  rows={1}
                  className={classes.headerDescInput}
                />
              )}
            </div>
          </div>
        </div>

        {/* ===== TAB BAR (AC4) ===== */}
        <div className={classes.builderTabBar}>
          {(['sessions', 'triggers', 'base-resources'] as const).map((tab) => (
            <button
              key={tab}
              type="button"
              className={`${classes.builderTab} ${activeTab === tab ? classes.builderTabActive : ''}`}
              onClick={() => setActiveTab(tab)}
            >
              {tab === 'sessions' ? 'Sessions' : tab === 'triggers' ? 'Triggers' : 'Base Resources'}
            </button>
          ))}
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
                      assets={assets}
                      repositories={repositories}
                      configItems={configItems}
                      agentModels={agentModels}
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
              repositories={repositories}
              configItems={configItems}
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
          defaultAgentRuntime={defaultAgentRuntime}
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
