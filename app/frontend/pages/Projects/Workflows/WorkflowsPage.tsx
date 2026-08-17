import { Head, router, usePage } from '@inertiajs/react';
import { Box, Button, Group, Modal, Stack, Text, TextInput, Textarea, Tooltip } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import {
  IconArrowUpRight,
  IconCopy,
  IconEdit,
  IconGlobe,
  IconGlobeOff,
  IconHistory,
  IconPlayerPlay,
  IconPlus,
  IconSearch,
  IconStack2,
  IconTrash,
} from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useMemo, useState } from 'react';
import { z } from 'zod';

import { RunWorkflowDrawer } from 'shared/components/RunWorkflowDrawer';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { builderCompanyProjectWorkflowPath } from 'shared/routes';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface NamedItem {
  id: number;
  name: string;
}

interface WorkflowStep {
  id: number;
  name: string;
  position: number;
  allowNonInteractive: boolean;
  dependsOnStepIds: number[];
}

interface Workflow {
  id: number;
  name: string;
  description: string | null;
  scopeType: string;
  scopeId: number;
  scopeIndicator: 'company' | 'project' | 'overrides_company';
  stepsCount: number;
  runsCount: number;
  lastRunAt: string | null;
  lastRunStatus: string | null;
  hasActiveRuns: boolean;
  descriptionExcerpt: string | null;
  publishedAt: string | null;
  createdAt: string;
  updatedAt: string;
  steps: WorkflowStep[];
}

interface Project {
  id: number;
  name: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: { modelId: string; displayName: string }[];
}

interface Props {
  project: Project;
  workflows: Workflow[];
  assets?: NamedItem[];
  repositories?: NamedItem[];
  configuredAgents: string[];
  defaultAgentRuntime?: string | null;
  agentModels?: AgentModelsEntry[];
}

const workflowSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
});

type WorkflowFormValues = z.infer<typeof workflowSchema>;

const WorkflowsPage = () => {
  const {
    project,
    workflows,
    assets: rawAssets,
    repositories: rawRepositories,
    configuredAgents,
    defaultAgentRuntime,
    agentModels,
  } = usePage<{ props: Props }>().props as unknown as Props;
  const { canExecute } = useProjectPermissions();
  const assets = rawAssets ?? [];
  const repositories = rawRepositories ?? [];
  const basePath = `/company/projects/${project.id}/workflows`;

  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [createOpen, setCreateOpen] = useState(false);
  const [editWorkflow, setEditWorkflow] = useState<Workflow | null>(null);
  const [deleteWorkflow, setDeleteWorkflow] = useState<Workflow | null>(null);
  const [runWorkflow, setRunWorkflow] = useState<Workflow | null>(null);
  const [loading, setLoading] = useState(false);

  const filtered = useMemo(() => {
    if (!debouncedSearch) return workflows;
    const lower = debouncedSearch.toLowerCase();
    return workflows.filter(
      (w) => w.name.toLowerCase().includes(lower) || w.description?.toLowerCase().includes(lower),
    );
  }, [workflows, debouncedSearch]);

  const createForm = useForm<WorkflowFormValues>({
    validate: zodResolver(workflowSchema),
    initialValues: { name: '', description: '' },
  });

  const editForm = useForm<WorkflowFormValues>({
    validate: zodResolver(workflowSchema),
    initialValues: { name: '', description: '' },
  });

  const handleCreate = (values: WorkflowFormValues) => {
    setLoading(true);
    router.post(
      basePath,
      { workflow: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: (page) => {
          setCreateOpen(false);
          createForm.reset();
          // AC2: redirect to builder after successful create
          try {
            const newWorkflows = (page.props as { workflows?: { id: number }[] }).workflows;
            if (newWorkflows && newWorkflows.length > 0) {
              const latest = newWorkflows[newWorkflows.length - 1];
              if (latest) {
                router.visit(builderCompanyProjectWorkflowPath(project.id, latest.id));
              }
            }
          } catch (error) {
            console.error('Error redirecting to builder:', error);
          }
        },
        onError: (errors) => {
          console.error('Error creating workflow:', errors);
        },
      },
    );
  };

  const handleEdit = (values: WorkflowFormValues) => {
    if (!editWorkflow) return;
    setLoading(true);
    router.patch(
      `${basePath}/${editWorkflow.id}`,
      { workflow: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => {
          setEditWorkflow(null);
          editForm.reset();
        },
      },
    );
  };

  const handleDelete = () => {
    if (!deleteWorkflow) return;
    setLoading(true);
    router.delete(`${basePath}/${deleteWorkflow.id}`, {
      preserveScroll: true,
      onFinish: () => setLoading(false),
      onSuccess: () => setDeleteWorkflow(null),
      onError: (errors) => {
        console.error('Error deleting workflow:', errors);
      },
    });
  };

  const handleCopyAndConfigure = (wf: Workflow) => {
    setLoading(true);
    router.post(
      basePath,
      { workflow: { name: wf.name, description: wf.description } },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
      },
    );
  };

  const openEdit = (wf: Workflow) => {
    editForm.setValues({ name: wf.name, description: wf.description ?? '' });
    setEditWorkflow(wf);
  };

  return (
    <>
      <Head title={`Workflows — ${project.name}`} />
      <style>{`
        @keyframes pulse-dot {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        .wf-card { background: var(--app-bg-paper); border: 1px solid var(--app-border-default); border-radius: 8px; display: flex; flex-direction: column; transition: border-color 0.15s; }
        .wf-card:hover { border-color: var(--app-border-active); }
        .wf-card-body { padding: 18px 18px 14px; flex: 1; display: flex; flex-direction: column; }
        .wf-card-name { font-size: 14px; font-weight: 600; color: var(--app-text-primary); letter-spacing: -0.01em; margin-bottom: 6px; }
        .wf-card-desc { font-size: 13px; color: var(--app-text-secondary); line-height: 1.55; margin-bottom: 14px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; flex: 1; }
        .wf-card-meta { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
        .wf-meta-item { display: flex; align-items: center; gap: 4px; font-size: 12px; color: var(--app-text-secondary); }
        .wf-status-label { font-size: 10px; font-weight: 600; letter-spacing: 0.05em; text-transform: uppercase; padding: 2px 8px; border-radius: 4px; border: 1px solid transparent; white-space: nowrap; flex-shrink: 0; margin-top: 1px; }
        .wf-status-label-active { background: rgba(209,207,205,0.05); color: var(--app-text-primary); border-color: rgba(209,207,205,0.12); }
        .wf-status-label-draft { background: var(--app-action-hover); color: var(--app-text-secondary); border-color: var(--app-border-default); }
        .wf-card-foot { display: flex; align-items: center; gap: 6px; padding: 11px 18px; border-top: 1px solid var(--app-border-default); }
        .wf-foot-left { display: flex; align-items: center; gap: 6px; flex: 1; }
        .wf-foot-right { display: flex; gap: 2px; }
        .wf-btn { display: inline-flex; align-items: center; gap: 5px; padding: 5px 12px; border-radius: 5px; font-family: inherit; font-size: 12px; font-weight: 500; cursor: pointer; transition: background 0.12s, border-color 0.12s, color 0.12s; border: 1px solid var(--app-border-default); background: transparent; color: var(--app-text-secondary); white-space: nowrap; }
        .wf-btn:hover { background: var(--app-bg-hover, rgba(255,255,255,0.04)); color: var(--app-text-primary); border-color: var(--app-border-active); }
        .wf-btn-run { background: var(--app-action-selected); color: var(--app-primary-strong); border-color: var(--app-accent-muted); font-weight: 600; }
        .wf-btn-run:hover { background: var(--app-action-selected); color: var(--app-primary-strong); border-color: var(--app-primary); }
        .wf-icon-btn { width: 28px; height: 28px; border-radius: 4px; border: none; background: transparent; color: var(--app-text-tertiary); cursor: pointer; display: flex; align-items: center; justify-content: center; transition: background 0.12s, color 0.12s; }
        .wf-icon-btn:hover { background: var(--app-bg-hover, rgba(255,255,255,0.04)); color: var(--app-text-secondary); }
        .wf-icon-btn-danger:hover { background: var(--app-danger-bg); color: var(--app-danger-fg); }
        .run-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; background: var(--app-text-tertiary); }
        .run-dot-ok { background: var(--app-text-tertiary); }
        .run-dot-idle { background: var(--app-text-tertiary); }
      `}</style>

      {/* Page heading */}
      <div style={{ maxWidth: 680 }}>
        <PageHeader
          title="Workflows"
          subtitle="Reusable automations your agents run end-to-end — a sequence of sessions with instructions, tools, and resources, triggered on a schedule or event. Create one manually, or describe what you want and let AI build it for you."
          mb={18}
        />
      </div>

      {/* Toolbar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 20 }}>
        <div style={{ position: 'relative', maxWidth: 260 }}>
          <IconSearch
            size={14}
            style={{
              position: 'absolute',
              left: 9,
              top: '50%',
              transform: 'translateY(-50%)',
              color: 'var(--app-text-tertiary)',
              pointerEvents: 'none',
            }}
          />
          <input
            type="text"
            placeholder="Search workflows..."
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            style={{
              width: '100%',
              background: 'var(--app-bg-paper)',
              border: '1px solid var(--app-border-default)',
              borderRadius: 5,
              color: 'var(--app-text-primary)',
              fontFamily: 'inherit',
              fontSize: 13,
              padding: '7px 10px 7px 30px',
              outline: 'none',
              transition: 'border-color 0.12s',
            }}
            onFocus={(e) => (e.currentTarget.style.borderColor = 'rgba(207,107,74,0.30)')}
            onBlur={(e) => (e.currentTarget.style.borderColor = 'var(--app-border-default)')}
          />
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
          <button
            type="button"
            className="wf-btn"
            onClick={() => router.visit(`/company/projects/${project.id}/workflow_runs`)}
          >
            <IconHistory size={13} /> Run History
          </button>
          <button type="button" className="wf-btn" onClick={() => router.visit('/company/workflow_catalog')}>
            Catalog
          </button>
          {canExecute && (
            <button
              type="button"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 5,
                padding: '6px 14px',
                borderRadius: 5,
                fontFamily: 'inherit',
                fontSize: 12,
                fontWeight: 600,
                cursor: 'pointer',
                border: '1px solid transparent',
                background: 'var(--app-primary)',
                color: 'var(--app-on-primary)',
                transition: 'background 0.12s',
              }}
              onClick={() => setCreateOpen(true)}
            >
              <IconPlus size={13} /> New Workflow
            </button>
          )}
        </div>
      </div>

      {/* Card grid / empty state */}
      {filtered.length === 0 ? (
        <Box py={60} ta="center" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
          <Text size="xl">&#128736;</Text>
          <Text c="dimmed" mt="sm">
            {search ? 'No workflows match your search' : 'No workflows yet'}
          </Text>
          {!search && canExecute && (
            <Button variant="outline" mt="md" onClick={() => setCreateOpen(true)}>
              Create your first workflow
            </Button>
          )}
        </Box>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 10, alignContent: 'start' }}>
          {filtered.map((wf) => {
            const isInherited = wf.scopeIndicator === 'company';
            const isPublished = !!wf.publishedAt;
            const lastRunDot = wf.lastRunStatus
              ? (() => {
                  const s = wf.lastRunStatus.toLowerCase();
                  let bg = 'var(--app-text-tertiary)';
                  let pulse = false;
                  if (s === 'completed' || s === 'finished') bg = 'var(--mantine-color-green-6)';
                  else if (s === 'failed') bg = 'var(--mantine-color-red-6)';
                  else if (s === 'running') {
                    bg = 'var(--mantine-color-blue-6)';
                    pulse = true;
                  }
                  return (
                    <span
                      className="run-dot"
                      style={{ background: bg, ...(pulse ? { animation: 'pulse-dot 1.4s ease-in-out infinite' } : {}) }}
                    />
                  );
                })()
              : null;

            return (
              <div key={wf.id} className="wf-card">
                <div className="wf-card-body">
                  {/* Name row + status badge */}
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'flex-start',
                      justifyContent: 'space-between',
                      gap: 8,
                      marginBottom: 6,
                    }}
                  >
                    <div className="wf-card-name">{wf.name}</div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0, marginTop: 1 }}>
                      {isInherited && <span className="wf-status-label wf-status-label-draft">company</span>}
                      {/* published_at only means "shared to the company
                          catalog so other projects can duplicate it". It says
                          nothing about whether the workflow is finished or
                          runnable, so labelling its absence "Draft" was wrong.
                          Only the shared state is worth a badge. */}
                      {isPublished && <span className="wf-status-label wf-status-label-active">In catalog</span>}
                    </div>
                  </div>
                  {/* Description */}
                  {wf.descriptionExcerpt && <div className="wf-card-desc">{wf.descriptionExcerpt}</div>}
                  {/* Meta row */}
                  <div className="wf-card-meta">
                    <div className="wf-meta-item">
                      <IconStack2 size={13} style={{ color: 'var(--app-text-tertiary)' }} />
                      <span>
                        {wf.stepsCount} {wf.stepsCount === 1 ? 'session' : 'sessions'}
                      </span>
                    </div>
                    <div className="wf-meta-item">
                      {lastRunDot}
                      <span>
                        {wf.lastRunAt ? `Last run ${new Date(wf.lastRunAt).toLocaleDateString()}` : 'Never run'}
                      </span>
                    </div>
                    <div className="wf-meta-item">
                      <IconPlayerPlay size={13} style={{ color: 'var(--app-text-tertiary)' }} />
                      <span>
                        {wf.runsCount} {wf.runsCount === 1 ? 'run' : 'runs'}
                      </span>
                    </div>
                  </div>
                </div>

                {/* Footer */}
                <div className="wf-card-foot">
                  <div className="wf-foot-left">
                    {canExecute && (
                      <Tooltip label="Run workflow">
                        <button type="button" className="wf-btn wf-btn-run" onClick={() => setRunWorkflow(wf)}>
                          <IconPlayerPlay size={12} /> Run
                        </button>
                      </Tooltip>
                    )}
                    <button
                      type="button"
                      className="wf-btn"
                      onClick={() => router.visit(`/company/projects/${project.id}/workflows/${wf.id}/builder`)}
                    >
                      <IconArrowUpRight size={12} /> Configure
                    </button>
                  </div>
                  <div className="wf-foot-right">
                    {canExecute &&
                      (isInherited ? (
                        <Tooltip label="Copy & Configure">
                          <button
                            type="button"
                            className="wf-icon-btn"
                            aria-label="Copy & Configure"
                            onClick={() => handleCopyAndConfigure(wf)}
                          >
                            <IconCopy size={14} />
                          </button>
                        </Tooltip>
                      ) : (
                        <>
                          <Tooltip label={wf.publishedAt ? 'Unpublish from catalog' : 'Publish to catalog'}>
                            <button
                              type="button"
                              className="wf-icon-btn"
                              aria-label={wf.publishedAt ? 'Unpublish from catalog' : 'Publish to catalog'}
                              style={wf.publishedAt ? { color: 'var(--app-success-fg)' } : {}}
                              onClick={() =>
                                router.post(
                                  `${basePath}/${wf.id}/${wf.publishedAt ? 'unpublish' : 'publish'}`,
                                  {},
                                  {
                                    preserveScroll: true,
                                    onError: (errors) => {
                                      console.error('Error publishing/unpublishing workflow:', errors);
                                    },
                                  },
                                )
                              }
                            >
                              {wf.publishedAt ? <IconGlobe size={14} /> : <IconGlobeOff size={14} />}
                            </button>
                          </Tooltip>
                          <Tooltip label="Edit name & description">
                            <button
                              type="button"
                              className="wf-icon-btn"
                              aria-label="Edit name & description"
                              onClick={() => openEdit(wf)}
                            >
                              <IconEdit size={14} />
                            </button>
                          </Tooltip>
                          <Tooltip label="Delete workflow">
                            <button
                              type="button"
                              className="wf-icon-btn wf-icon-btn-danger"
                              aria-label="Delete workflow"
                              onClick={() => setDeleteWorkflow(wf)}
                            >
                              <IconTrash size={14} />
                            </button>
                          </Tooltip>
                        </>
                      ))}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Create Modal */}
      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="New Workflow" centered>
        <form onSubmit={createForm.onSubmit(handleCreate)}>
          <Stack gap="md">
            <TextInput label="Name" required {...createForm.getInputProps('name')} />
            <Textarea label="Description" autosize minRows={2} {...createForm.getInputProps('description')} />
            <Group justify="flex-end">
              <Button variant="outline" onClick={() => setCreateOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" loading={loading}>
                Create
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {/* Edit Modal */}
      <Modal opened={!!editWorkflow} onClose={() => setEditWorkflow(null)} title="Edit Workflow" centered>
        <form onSubmit={editForm.onSubmit(handleEdit)}>
          <Stack gap="md">
            <TextInput label="Name" required {...editForm.getInputProps('name')} />
            <Textarea label="Description" autosize minRows={2} {...editForm.getInputProps('description')} />
            <Group justify="flex-end">
              <Button variant="outline" onClick={() => setEditWorkflow(null)}>
                Cancel
              </Button>
              <Button type="submit" loading={loading}>
                Save
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {/* Delete Confirmation */}
      <Modal opened={!!deleteWorkflow} onClose={() => setDeleteWorkflow(null)} title="Delete Workflow" centered>
        <Text size="sm" mb="md">
          Are you sure you want to delete <strong>{deleteWorkflow?.name}</strong>?
          {deleteWorkflow?.hasActiveRuns && (
            <Text c="var(--app-danger-fg)" size="sm" mt="xs">
              This workflow has active runs. Stop them first.
            </Text>
          )}
        </Text>
        <Group justify="flex-end">
          <Button variant="outline" onClick={() => setDeleteWorkflow(null)}>
            Cancel
          </Button>
          <Button color="red" onClick={handleDelete} loading={loading} disabled={deleteWorkflow?.hasActiveRuns}>
            Delete
          </Button>
        </Group>
      </Modal>

      {runWorkflow && (
        <RunWorkflowDrawer
          opened={!!runWorkflow}
          onClose={() => setRunWorkflow(null)}
          workflows={[{ id: runWorkflow.id, name: runWorkflow.name, steps: runWorkflow.steps }]}
          initialWorkflowId={runWorkflow.id}
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

setPageLayout(WorkflowsPage, persistentProjectLayout);

export default WorkflowsPage;
