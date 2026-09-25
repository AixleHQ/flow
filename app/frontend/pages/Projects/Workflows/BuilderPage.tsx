import { arrayMove } from '@dnd-kit/sortable';
import { Head, router, usePage } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Text, TextInput, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArrowLeft, IconDeviceFloppy, IconInfoCircle, IconPlayerPlay } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import type { ConfigItemPicker, Picker, Project, Step, Workflow } from '@/types/generated';

import type { AssetPickerItem } from 'shared/components/AssetPicker';
import { RunWorkflowDrawer } from 'shared/components/RunWorkflowDrawer';
import { HistoryButton } from 'shared/components/versions/HistoryButton';
import { ApiError, apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { useUnsavedChangesGuard } from 'shared/lib/hooks/useUnsavedChangesGuard';
import type { ToolGroup } from 'shared/lib/toolPicker';
import { UnsavedChangesNotice } from 'shared/ui/UnsavedChangesNotice';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import { BaseResourcesTab } from './BaseResourcesTab';
import { aggregatePayload, draftStep, draftSubStep, remapSelection, snapshotOf } from './builderDraft';
import classes from './BuilderPage.module.css';
import { SessionEditorPanel } from './SessionEditorPanel';
import { SessionTreeNav } from './SessionTreeNav';
import type { Selection } from './SessionTreeNav';
import { StepEditorPanel } from './StepEditorPanel';
import { TriggersTab } from './TriggersTab';

type ProjectOrNull = Project | null;
type AssetSpec = Step['outputAssetSpecs'][number];
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
  agents?: Picker[];
  tools?: Picker[];
  toolGroups?: ToolGroup[];
  skills?: Picker[];
  mcpServers?: Picker[];
  assets?: AssetPickerItem[];
  repositories?: Picker[];
  configItems?: ConfigItemPicker[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  configuredAgents: string[];
  defaultAgentRuntime?: string | null;
  boardColumns?: { id: number; name: string; boundWorkflowName?: string | null }[];
}

interface AggregateResponse {
  workflow: Workflow;
  steps: Step[];
  currentVersionNumber: number;
  versionCreated: boolean;
}

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
  // What the server holds: the editor is dirty while its state differs from this.
  const [savedSnapshot, setSavedSnapshot] = useState(() => snapshotOf(initialWorkflow, initialSteps));
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState<string>('sessions');
  const [selection, setSelection] = useState<Selection | null>(() =>
    initialSteps.length > 0 ? { mode: 'session', sessionId: initialSteps[0].id } : null,
  );
  const [deleteStepConfirm, setDeleteStepConfirm] = useState<number | null>(null);
  const [runModalOpen, setRunModalOpen] = useState(false);

  const sortedSteps = useMemo(() => [...steps].sort((a, b) => a.position - b.position), [steps]);
  const dirty = !readOnly && snapshotOf(workflow, steps) !== savedSnapshot;
  useUnsavedChangesGuard(dirty);

  // Run button guard (AC10)
  const canRun = useMemo(() => steps.some((s) => (s.instructions ?? '').trim().length > 0), [steps]);

  const updateWorkflowField = useCallback((field: string, value: unknown) => {
    setWorkflow((w) => ({ ...w, [field]: value }));
  }, []);

  // --- Session (Step) editing: local until Save ---
  const createSession = useCallback(
    (name: string) => {
      const step = draftStep(steps, name);
      setSteps([...steps, step]);
      setSelection({ mode: 'session', sessionId: step.id });
    },
    [steps],
  );

  const deleteSession = useCallback(
    (stepId: number) => {
      setSteps((prev) =>
        prev
          .filter((s) => s.id !== stepId)
          .map((s) => ({ ...s, dependsOnStepIds: s.dependsOnStepIds.filter((id) => id !== stepId) })),
      );
      if (selection?.sessionId === stepId) setSelection(null);
      setDeleteStepConfirm(null);
    },
    [selection],
  );

  const reorderSessions = useCallback(
    (oldIndex: number, newIndex: number) => {
      const reordered = arrayMove(sortedSteps, oldIndex, newIndex);
      setSteps(reordered.map((s, i) => ({ ...s, position: i + 1 })));
    },
    [sortedSteps],
  );

  const updateStepField = useCallback((stepId: number, field: string, value: unknown) => {
    setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: value } : s)));
  }, []);

  // --- Sub-step management ---
  const addSubStep = useCallback(
    (sessionId: number, stepName?: string) => {
      const step = steps.find((s) => s.id === sessionId);
      if (!step) return;
      const sub = draftSubStep(steps, step, stepName);
      setSteps(steps.map((s) => (s.id === sessionId ? { ...s, subSteps: [...s.subSteps, sub] } : s)));
      setSelection({ mode: 'step', sessionId, stepId: sub.id });
    },
    [steps],
  );

  const removeSubStep = useCallback(
    (sessionId: number, subStepId: number) => {
      setSteps((prev) =>
        prev.map((s) => (s.id === sessionId ? { ...s, subSteps: s.subSteps.filter((ss) => ss.id !== subStepId) } : s)),
      );
      if (selection?.mode === 'step' && selection.stepId === subStepId) {
        setSelection({ mode: 'session', sessionId });
      }
    },
    [selection],
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
    },
    [],
  );

  const reorderSubSteps = useCallback((sessionId: number, oldIndex: number, newIndex: number) => {
    setSteps((prev) =>
      prev.map((s) => {
        if (s.id !== sessionId) return s;
        const sorted = [...s.subSteps].sort((a, b) => a.position - b.position);
        return { ...s, subSteps: arrayMove(sorted, oldIndex, newIndex).map((ss, i) => ({ ...ss, position: i + 1 })) };
      }),
    );
  }, []);

  const handleAssetSpecsChange = useCallback(
    (stepId: number, field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => {
      setSteps((prev) => prev.map((s) => (s.id === stepId ? { ...s, [field]: specs } : s)));
    },
    [],
  );

  // --- Save: the whole workflow, one request, one version ---
  const save = useCallback(async () => {
    if (projectId == null) return;
    setSaving(true);
    try {
      const result = await apiRequest<AggregateResponse>(
        `/api/v1/projects/${projectId}/workflows/${workflow.id}/aggregate`,
        {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            baseVersion: workflow.currentVersionNumber,
            aggregate: aggregatePayload(workflow, sortedSteps),
          }),
        },
      );
      setSelection((current) => remapSelection(current, sortedSteps, result.steps));
      setWorkflow(result.workflow);
      setSteps(result.steps);
      setSavedSnapshot(snapshotOf(result.workflow, result.steps));
      notifications.show({
        color: 'green',
        message: result.versionCreated ? `Saved as version ${result.currentVersionNumber}` : 'Nothing to save',
      });
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        notifications.show({
          color: 'red',
          autoClose: false,
          message: `${error.message} Your edits are still here — copy what you need, then reload.`,
        });
      } else {
        notifyApiFailure(error, 'The workflow was not saved');
      }
    } finally {
      setSaving(false);
    }
  }, [projectId, workflow, sortedSteps]);

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
            <UnsavedChangesNotice visible={dirty} />
            {project && (
              <HistoryButton
                projectId={project.id}
                versionableType="Workflow"
                versionableId={workflow.id}
                title={workflow.name}
                canRevert={!readOnly}
              />
            )}
            {project && !readOnly && (
              <Button
                size="compact-sm"
                leftSection={<IconDeviceFloppy size={14} />}
                disabled={!dirty}
                loading={saving}
                onClick={() => void save()}
              >
                Save
              </Button>
            )}
            {project && !readOnly && (
              <Tooltip
                label={
                  dirty
                    ? 'Save first — a run uses the saved workflow'
                    : 'Add instructions to at least one session to run'
                }
                disabled={canRun && !dirty}
              >
                <button
                  type="button"
                  disabled={!canRun || dirty}
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
                    cursor: canRun && !dirty ? 'pointer' : 'not-allowed',
                    border: canRun && !dirty ? '1px solid var(--accent-muted)' : '1px solid var(--border)',
                    background: canRun && !dirty ? 'var(--accent-dim)' : 'var(--bg-card)',
                    color: canRun && !dirty ? 'var(--accent-text)' : 'var(--text-3)',
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
                      onFieldChange={(field, value) => updateStepField(selectedSession.id, field, value)}
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
        title="Remove Session"
        centered
        size="sm"
      >
        <Text size="sm" mb="md">
          Remove this session? It goes when you save, and stays in the workflow&apos;s history.
        </Text>
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setDeleteStepConfirm(null)}>
            Cancel
          </Button>
          <Button color="red" onClick={() => deleteStepConfirm !== null && deleteSession(deleteStepConfirm)}>
            Remove
          </Button>
        </Group>
      </Modal>

      {project && (
        <RunWorkflowDrawer
          opened={runModalOpen}
          onClose={() => setRunModalOpen(false)}
          workflows={[
            {
              id: workflow.id,
              name: workflow.name,
              steps: steps.map((s) => ({
                id: s.id,
                name: s.name,
                position: s.position,
                allowNonInteractive: s.allowNonInteractive,
                dependsOnStepIds: s.dependsOnStepIds,
              })),
            },
          ]}
          initialWorkflowId={workflow.id}
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
