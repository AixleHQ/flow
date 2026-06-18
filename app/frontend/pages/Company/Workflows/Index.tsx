import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
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
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { IconEdit, IconPlus, IconSearch, IconSettings, IconTrash } from '@tabler/icons-react';
import { zodResolver } from 'mantine-form-zod-resolver';
import { useMemo, useState } from 'react';
import { z } from 'zod';

import { AuthLayout } from 'layouts/AuthLayout';

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
  createdAt: string;
  updatedAt: string;
}

interface Props {
  workflows: Workflow[];
}

const workflowSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
});

type WorkflowFormValues = z.infer<typeof workflowSchema>;

const basePath = '/company/workflows';

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

const WorkflowsIndex = () => {
  const { workflows } = usePage<{ props: Props }>().props as unknown as Props;

  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [createOpen, setCreateOpen] = useState(false);
  const [editWorkflow, setEditWorkflow] = useState<Workflow | null>(null);
  const [deleteWorkflow, setDeleteWorkflow] = useState<Workflow | null>(null);
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

  const openEdit = (wf: Workflow) => {
    editForm.setValues({ name: wf.name, description: wf.description ?? '' });
    setEditWorkflow(wf);
  };

  return (
    <AuthLayout>
      <Head title="Company Workflows" />
      <style>{`
        @keyframes pulse-dot {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
      `}</style>

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
          <Button variant="outline" size="sm" onClick={() => router.visit('/company/workflow_catalog')}>
            Catalog
          </Button>
          <Button size="sm" leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
            New Workflow
          </Button>
        </Group>
      </Group>

      {filtered.length === 0 ? (
        <Box py={60} ta="center" style={{ border: '1px solid var(--mantine-color-dark-4)', borderRadius: 8 }}>
          <Text size="xl">&#128736;</Text>
          <Text c="dimmed" mt="sm">
            {search ? 'No workflows match your search' : 'No workflows yet'}
          </Text>
          {!search && (
            <Button variant="outline" mt="md" onClick={() => setCreateOpen(true)}>
              Create your first workflow
            </Button>
          )}
        </Box>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
          {filtered.map((wf) => (
            <Card key={wf.id} padding="md" withBorder style={{ display: 'flex', flexDirection: 'column' }}>
              <Group gap="xs" mb={4}>
                {getStatusDot(wf.lastRunStatus)}
                <Text fw={500} size="md" truncate style={{ flex: 1 }}>
                  {wf.name}
                </Text>
                {wf.hasActiveRuns && (
                  <Badge size="xs" color="blue" variant="filled">
                    Active
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
                <Tooltip label="Configure in Builder">
                  <Button
                    size="xs"
                    variant="outline"
                    leftSection={<IconSettings size={14} />}
                    onClick={() => router.visit(`${basePath}/${wf.id}/builder`)}
                  >
                    Configure
                  </Button>
                </Tooltip>
                <Group gap={4}>
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
                </Group>
              </Group>
            </Card>
          ))}
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
    </AuthLayout>
  );
};

export default WorkflowsIndex;
