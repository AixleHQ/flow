import { Head, router, usePage } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Group,
  Modal,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Textarea,
  Tooltip,
  ActionIcon,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import {
  IconCopy,
  IconEdit,
  IconGlobe,
  IconGlobeOff,
  IconHistory,
  IconPlayerPlay,
  IconPlus,
  IconSearch,
  IconSettings,
  IconSparkles,
  IconTrash,
  IconWand,
} from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useMemo, useState } from 'react';
import { z } from 'zod';

import { RunWorkflowModal } from 'shared/components/RunWorkflowModal';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';

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
        onSuccess: () => {
          setCreateOpen(false);
          createForm.reset();
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

  const getStatusDot = (status: string | null) => {
    if (!status) return null;
    const s = status.toLowerCase();

    let color: string;
    let pulse = false;

    if (s === 'completed' || s === 'finished') {
      color = 'var(--mantine-color-green-6)';
    } else if (s === 'failed') {
      color = 'var(--mantine-color-red-6)';
    } else if (s === 'running') {
      color = 'var(--mantine-color-blue-6)';
      pulse = true;
    } else {
      return null;
    }

    return (
      <Box
        component="span"
        style={{
          display: 'inline-block',
          width: 8,
          height: 8,
          borderRadius: '50%',
          backgroundColor: color,
          flexShrink: 0,
          ...(pulse ? { animation: 'pulse-dot 1.4s ease-in-out infinite' } : {}),
        }}
      />
    );
  };

  return (
    <>
      <Head title={`Workflows — ${project.name}`} />
      <style>{`
        @keyframes pulse-dot {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
      `}</style>
      {/* Aixle Builder Banner */}
      <Card
        withBorder
        p="md"
        mb="md"
        style={{
          borderColor: 'var(--mantine-color-brand-6)',
          backgroundImage: 'linear-gradient(135deg, rgba(99, 102, 241, 0.04) 0%, rgba(168, 85, 247, 0.04) 100%)',
        }}
      >
        <Group justify="space-between" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <IconWand size={24} style={{ color: 'var(--mantine-color-brand-5)', flexShrink: 0 }} />
            <Box>
              <Text fw={600} size="sm">
                Aixle Builder
              </Text>
              <Text size="xs" c="dimmed">
                Build workflows with AI — agents, steps, board automation
              </Text>
            </Box>
          </Group>
          <Button
            size="sm"
            leftSection={<IconSparkles size={14} />}
            onClick={() => router.visit(`/company/projects/${project.id}/aixle_builder`)}
          >
            Open Builder
          </Button>
        </Group>
      </Card>

      <Group justify="space-between" mb="md">
        <Group gap="sm">
          <TextInput
            placeholder="Search workflows..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            w={300}
            size="sm"
          />
        </Group>
        <Group gap="sm">
          <Button
            variant="outline"
            size="sm"
            leftSection={<IconHistory size={16} />}
            onClick={() => router.visit(`/company/projects/${project.id}/workflow_runs`)}
          >
            Run History
          </Button>
          <Button variant="outline" size="sm" onClick={() => router.visit('/company/workflow_catalog')}>
            Catalog
          </Button>
          {canExecute && (
            <Button size="sm" leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
              New Workflow
            </Button>
          )}
        </Group>
      </Group>

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
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          {filtered.map((wf) => {
            const isInherited = wf.scopeIndicator === 'company';

            return (
              <Card key={wf.id} padding="md" withBorder style={{ display: 'flex', flexDirection: 'column' }}>
                <Group gap="xs" mb={4}>
                  {getStatusDot(wf.lastRunStatus)}
                  <Text fw={500} size="md" truncate style={{ flex: 1 }}>
                    {wf.name}
                  </Text>
                  {isInherited && (
                    <Badge size="xs" variant="outline" color="brand">
                      company
                    </Badge>
                  )}
                </Group>
                {wf.descriptionExcerpt && (
                  <Text size="sm" c="dimmed" truncate>
                    {wf.descriptionExcerpt}
                  </Text>
                )}
                <Text size="xs" c="dimmed" mt={4}>
                  {wf.stepsCount} steps
                  {wf.lastRunAt && <> &middot; Last run {new Date(wf.lastRunAt).toLocaleDateString()}</>}
                </Text>

                <Group justify="space-between" mt="auto" pt="sm">
                  <Group gap="xs">
                    {canExecute && (
                      <Tooltip label="Run workflow">
                        <Button
                          size="xs"
                          variant="filled"
                          leftSection={<IconPlayerPlay size={14} />}
                          onClick={() => setRunWorkflow(wf)}
                        >
                          Run
                        </Button>
                      </Tooltip>
                    )}
                    <Tooltip label="Configure">
                      <Button
                        size="xs"
                        variant="outline"
                        leftSection={<IconSettings size={14} />}
                        onClick={(e: React.MouseEvent) => {
                          e.preventDefault();
                          router.visit(`/company/projects/${project.id}/workflows/${wf.id}/builder`);
                        }}
                      >
                        Configure
                      </Button>
                    </Tooltip>
                  </Group>
                  <Group gap={4}>
                    {canExecute && (isInherited ? (
                      <Tooltip label="Copy & Configure">
                        <ActionIcon
                          size="sm"
                          variant="subtle"
                          onClick={() => handleCopyAndConfigure(wf)}
                          loading={loading}
                        >
                          <IconCopy size={16} />
                        </ActionIcon>
                      </Tooltip>
                    ) : (
                      <>
                        <Tooltip label={wf.publishedAt ? 'Unpublish from catalog' : 'Publish to catalog'}>
                          <ActionIcon
                            size="sm"
                            variant="subtle"
                            color={wf.publishedAt ? 'green' : 'gray'}
                            onClick={() =>
                              router.post(
                                `${basePath}/${wf.id}/${wf.publishedAt ? 'unpublish' : 'publish'}`,
                                {},
                                { preserveScroll: true },
                              )
                            }
                          >
                            {wf.publishedAt ? <IconGlobe size={16} /> : <IconGlobeOff size={16} />}
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Edit name & description">
                          <ActionIcon size="sm" variant="subtle" onClick={() => openEdit(wf)}>
                            <IconEdit size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Delete workflow">
                          <ActionIcon size="sm" variant="subtle" color="red" onClick={() => setDeleteWorkflow(wf)}>
                            <IconTrash size={16} />
                          </ActionIcon>
                        </Tooltip>
                      </>
                    ))}
                  </Group>
                </Group>
              </Card>
            );
          })}
        </SimpleGrid>
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
            <Text c="red" size="sm" mt="xs">
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
        <RunWorkflowModal
          opened={!!runWorkflow}
          onClose={() => setRunWorkflow(null)}
          workflowId={runWorkflow.id}
          workflowName={runWorkflow.name}
          steps={runWorkflow.steps}
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

setPageLayout(WorkflowsPage, persistentProjectLayout);

export default WorkflowsPage;
