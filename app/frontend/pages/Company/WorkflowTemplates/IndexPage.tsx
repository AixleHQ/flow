import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Card,
  Group,
  Modal,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Textarea,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { IconChevronLeft, IconEdit, IconSearch } from '@tabler/icons-react';
import { zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState } from 'react';
import { z } from 'zod';

import { AuthLayout } from 'layouts/AuthLayout';

import {
  companyWorkflowTemplatePath,
  companyWorkflowTemplatesPath,
  companyWorkflowsPath,
  fromTemplateCompanyProjectWorkflowsPath,
} from 'shared/routes';

interface WorkflowTemplate {
  id: number;
  name: string;
  description: string | null;
  useCase: string | null;
  visibility: string;
  ownerName: string;
  ownerId: number;
  latestVersionNumber: number | null;
  currentVersionId: number | null;
  lastUpdatedAt: string;
  projectsCount: number;
  stepsCount: number;
}

interface Props {
  templates: WorkflowTemplate[];
  filters?: { nameCont?: string };
  returnTo?: string | null;
  projectId?: number | null;
  projects?: { id: number; name: string }[];
  currentUserId?: number;
  isAdmin?: boolean;
}

const editSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
  useCase: z.string().optional(),
  visibility: z.enum(['company', 'private']),
});

type EditFormValues = z.infer<typeof editSchema>;

const IndexPage = () => {
  const {
    templates,
    filters,
    returnTo,
    projectId,
    projects = [],
    currentUserId,
    isAdmin = false,
  } = usePage<{ props: Props }>().props as unknown as Props;

  const [search, setSearch] = useState(filters?.nameCont ?? '');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [creatingVersionId, setCreatingVersionId] = useState<number | null>(null);
  const [editTemplate, setEditTemplate] = useState<WorkflowTemplate | null>(null);
  const [createTemplate, setCreateTemplate] = useState<WorkflowTemplate | null>(null);
  const [selectedProjectId, setSelectedProjectId] = useState<string>(projectId ? String(projectId) : '');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const term = debouncedSearch.trim();
    const current = (filters?.nameCont ?? '').trim();
    if (term === current) return;

    const params = new URLSearchParams();
    if (term) {
      params.set('q[name_cont]', term);
    }
    if (returnTo) {
      params.set('return_to', returnTo);
    }
    const query = params.toString();
    const path = query ? `${companyWorkflowTemplatesPath()}?${query}` : companyWorkflowTemplatesPath();

    router.get(path, {}, { preserveState: true, replace: true, only: ['templates', 'filters'] });
  }, [debouncedSearch, filters?.nameCont, returnTo]);

  const editForm = useForm<EditFormValues>({
    validate: zodResolver(editSchema),
    initialValues: { name: '', description: '', useCase: '', visibility: 'company' },
  });

  const canManage = (template: WorkflowTemplate) =>
    isAdmin || (currentUserId != null && template.ownerId === currentUserId);

  const handleCreateFromTemplate = (template: WorkflowTemplate) => {
    if (!template.currentVersionId) return;

    const defaultProjectId = projectId && projects.some((p) => p.id === projectId) ? String(projectId) : '';
    setSelectedProjectId(defaultProjectId);
    setCreateTemplate(template);
  };

  const handleConfirmCreateInProject = () => {
    if (!createTemplate || !selectedProjectId) return;

    const template = createTemplate;
    setCreateTemplate(null);
    setCreatingVersionId(template.currentVersionId);
    router.post(
      fromTemplateCompanyProjectWorkflowsPath(Number(selectedProjectId)),
      { workflowTemplateVersionId: template.currentVersionId },
      {
        onFinish: () => setCreatingVersionId(null),
      },
    );
  };

  const handleBack = () => {
    router.visit(returnTo || companyWorkflowsPath());
  };

  const openEdit = (template: WorkflowTemplate) => {
    editForm.setValues({
      name: template.name,
      description: template.description ?? '',
      useCase: template.useCase ?? '',
      visibility: template.visibility as 'company' | 'private',
    });
    setEditTemplate(template);
  };

  const handleEdit = (values: EditFormValues) => {
    if (!editTemplate) return;
    setLoading(true);
    router.patch(
      companyWorkflowTemplatePath(editTemplate.id),
      { workflowTemplate: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => setEditTemplate(null),
      },
    );
  };

  return (
    <AuthLayout>
      <Head title="Workflow Templates" />
      <Box mih="100vh" bg="var(--app-bg-default)">
        <Button variant="subtle" size="sm" leftSection={<IconChevronLeft size={16} />} onClick={handleBack} mb="md">
          Back
        </Button>
        <Group justify="space-between" align="flex-start" mb={24}>
          <Box>
            <Text fz={32} fw={600} c="white" mb={8}>
              Workflow Templates
            </Text>
            <Text c="dimmed" size="sm">
              Published workflows your team can reuse when starting new projects or adding workflows.
            </Text>
          </Box>
        </Group>

        <TextInput
          placeholder="Search templates..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          mb="lg"
          maw={400}
        />

        {templates.length === 0 ? (
          <Stack align="center" py={60}>
            <Text c="dimmed">{search ? 'No templates match your search' : 'No templates published yet'}</Text>
          </Stack>
        ) : (
          <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="md">
            {templates.map((template) => (
              <Card
                key={template.id}
                withBorder
                padding="lg"
                radius="md"
                style={{ display: 'flex', flexDirection: 'column' }}
              >
                <Stack gap="sm" style={{ flex: 1 }}>
                  <Group justify="space-between" align="flex-start">
                    <Text fw={600}>{template.name}</Text>
                    <Group gap={4}>
                      {template.latestVersionNumber && (
                        <Badge variant="light" size="sm">
                          v{template.latestVersionNumber}
                        </Badge>
                      )}
                      {canManage(template) && (
                        <ActionIcon size="sm" variant="subtle" onClick={() => openEdit(template)}>
                          <IconEdit size={16} />
                        </ActionIcon>
                      )}
                    </Group>
                  </Group>
                  {template.useCase && (
                    <Badge variant="outline" color="gray" size="sm" w="fit-content">
                      {template.useCase}
                    </Badge>
                  )}
                  {template.description && (
                    <Text size="sm" c="dimmed" lineClamp={3}>
                      {template.description}
                    </Text>
                  )}
                  <Text size="xs" c="dimmed">
                    {template.stepsCount} steps
                  </Text>
                  <Group gap="xs" mt="auto">
                    <Text size="xs" c="dimmed">
                      By {template.ownerName}
                    </Text>
                    <Text size="xs" c="dimmed">
                      &middot; Updated {new Date(template.lastUpdatedAt).toLocaleDateString()}
                    </Text>
                  </Group>
                  <Text size="xs" c="dimmed">
                    Started from template in {template.projectsCount}{' '}
                    {template.projectsCount === 1 ? 'project' : 'projects'}
                  </Text>
                  {template.currentVersionId ? (
                    <Button
                      fullWidth
                      variant="light"
                      loading={creatingVersionId === template.currentVersionId}
                      disabled={creatingVersionId !== null && creatingVersionId !== template.currentVersionId}
                      onClick={() => handleCreateFromTemplate(template)}
                    >
                      Create workflow in project
                    </Button>
                  ) : (
                    <Text size="xs" c="dimmed">
                      No published version available.
                    </Text>
                  )}
                </Stack>
              </Card>
            ))}
          </SimpleGrid>
        )}
      </Box>

      <Modal
        opened={!!createTemplate}
        onClose={() => setCreateTemplate(null)}
        title="Create workflow in project"
        centered
      >
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Choose a project for <strong>{createTemplate?.name}</strong>.
          </Text>
          {projects.length === 0 ? (
            <Text size="sm" c="dimmed">
              You do not have access to any projects yet.
            </Text>
          ) : (
            <Select
              label="Project"
              placeholder="Select project"
              data={projects.map((p) => ({ value: String(p.id), label: p.name }))}
              value={selectedProjectId}
              onChange={(value) => setSelectedProjectId(value ?? '')}
              searchable
            />
          )}
          <Group justify="flex-end">
            <Button variant="outline" onClick={() => setCreateTemplate(null)}>
              Cancel
            </Button>
            <Button onClick={handleConfirmCreateInProject} disabled={!selectedProjectId}>
              Create workflow
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={!!editTemplate} onClose={() => setEditTemplate(null)} title="Edit template" centered>
        <form onSubmit={editForm.onSubmit(handleEdit)}>
          <Stack gap="md">
            <TextInput label="Name" required {...editForm.getInputProps('name')} />
            <Textarea label="Description" autosize minRows={2} {...editForm.getInputProps('description')} />
            <TextInput label="Use case" {...editForm.getInputProps('useCase')} />
            <Select
              label="Visibility"
              data={[
                { value: 'company', label: 'Entire company' },
                { value: 'private', label: 'Only me' },
              ]}
              {...editForm.getInputProps('visibility')}
            />
            <Group justify="flex-end">
              <Button variant="outline" onClick={() => setEditTemplate(null)}>
                Cancel
              </Button>
              <Button type="submit" loading={loading}>
                Save
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </AuthLayout>
  );
};

export default IndexPage;
