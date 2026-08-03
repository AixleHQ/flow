import { Head, router, usePage } from '@inertiajs/react';
import { Box, Button, Card, Group, Modal, Select, SimpleGrid, Stack, Text, TextInput } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { IconSearch } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { PageHeader } from 'shared/ui/PageHeader';

interface CatalogWorkflow {
  id: number;
  name: string;
  description: string | null;
  scopeType: string;
  stepsCount: number;
  publishedAt: string;
  publishedByName: string | null;
}

interface ProjectOption {
  id: number;
  name: string;
}

interface Props {
  workflows: CatalogWorkflow[];
  projects: ProjectOption[];
}

const IndexPage = () => {
  const { workflows, projects } = usePage<{ props: Props }>().props as unknown as Props;

  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [duplicateWorkflow, setDuplicateWorkflow] = useState<CatalogWorkflow | null>(null);
  const [selectedProjectId, setSelectedProjectId] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const filtered = useMemo(() => {
    if (!debouncedSearch) return workflows;
    const lower = debouncedSearch.toLowerCase();
    return workflows.filter(
      (w) => w.name.toLowerCase().includes(lower) || w.description?.toLowerCase().includes(lower),
    );
  }, [workflows, debouncedSearch]);

  const projectOptions = useMemo(() => projects.map((p) => ({ value: String(p.id), label: p.name })), [projects]);

  const handleDuplicate = () => {
    if (!duplicateWorkflow || !selectedProjectId) return;
    setLoading(true);
    router.post(
      `/company/workflow_catalog/${duplicateWorkflow.id}/duplicate`,
      { project_id: selectedProjectId },
      {
        onFinish: () => setLoading(false),
        onSuccess: () => {
          setDuplicateWorkflow(null);
          setSelectedProjectId('');
        },
      },
    );
  };

  return (
    <AuthLayout>
      <Head title="Workflow Catalog" />
      <Box mih="100vh" bg="var(--app-bg-default)">
        <PageHeader
          title="Workflow Catalog"
          subtitle="Published workflows your team can duplicate into their projects."
          mb={24}
        />

        <TextInput
          placeholder="Search workflows..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          mb="lg"
          maw={400}
        />

        {filtered.length === 0 ? (
          <Stack align="center" py={60}>
            <Text c="dimmed">{search ? 'No workflows match your search' : 'No workflows published yet'}</Text>
          </Stack>
        ) : (
          <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="md">
            {filtered.map((wf) => (
              <Card
                key={wf.id}
                withBorder
                padding="lg"
                radius="md"
                style={{ display: 'flex', flexDirection: 'column' }}
              >
                <Stack gap="sm" style={{ flex: 1 }}>
                  <Text fw={600}>{wf.name}</Text>
                  {wf.description && (
                    <Text size="sm" c="dimmed" lineClamp={3}>
                      {wf.description}
                    </Text>
                  )}
                  <Text size="xs" c="dimmed">
                    {wf.stepsCount} steps
                  </Text>
                  <Group gap="xs" mt="auto">
                    {wf.publishedByName && (
                      <Text size="xs" c="dimmed">
                        Published by {wf.publishedByName}
                      </Text>
                    )}
                    <Text size="xs" c="dimmed">
                      &middot; {new Date(wf.publishedAt).toLocaleDateString()}
                    </Text>
                  </Group>
                  <Button fullWidth variant="light" onClick={() => setDuplicateWorkflow(wf)}>
                    Duplicate to project
                  </Button>
                </Stack>
              </Card>
            ))}
          </SimpleGrid>
        )}
      </Box>

      <Modal
        opened={!!duplicateWorkflow}
        onClose={() => setDuplicateWorkflow(null)}
        title="Duplicate to project"
        centered
      >
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Choose a project for <strong>{duplicateWorkflow?.name}</strong>.
          </Text>
          {projects.length === 0 ? (
            <Text size="sm" c="dimmed">
              You do not have access to any projects yet.
            </Text>
          ) : (
            <Select
              label="Project"
              placeholder="Select project"
              data={projectOptions}
              value={selectedProjectId}
              onChange={(value) => setSelectedProjectId(value ?? '')}
              searchable
            />
          )}
          <Group justify="flex-end">
            <Button variant="outline" onClick={() => setDuplicateWorkflow(null)}>
              Cancel
            </Button>
            <Button onClick={handleDuplicate} disabled={!selectedProjectId} loading={loading}>
              Duplicate
            </Button>
          </Group>
        </Stack>
      </Modal>
    </AuthLayout>
  );
};

export default IndexPage;
