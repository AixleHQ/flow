import { router, usePage } from '@inertiajs/react';
import { Box, Button, Center, Group, Select, SimpleGrid, Stack, Text, TextInput } from '@mantine/core';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { CreateProjectModal } from './CreateProjectModal';
import { ProjectCard } from './ProjectCard';

interface Project {
  id: number;
  name: string;
  description?: string | null;
  slug: string;
  state: string;
  collaboratorsCount: number;
  membersCount: number;
  sessionsCount: number;
  workflowsCount: number;
  boardTasksCount: number;
  lastActivityAt?: string | null;
  createdAt: string;
}

interface PageProps {
  projects: Project[];
  [key: string]: unknown;
}

type SortKey = 'name' | 'last_activity' | 'newest';

const SORT_OPTIONS = [
  { value: 'name', label: 'Name' },
  { value: 'last_activity', label: 'Last activity' },
  { value: 'newest', label: 'Newest first' },
];

const IndexPage = () => {
  const { projects } = usePage<PageProps>().props;
  const [createOpened, setCreateOpened] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<SortKey>('name');

  const sortedAndFiltered = useMemo(() => {
    const sorted = [...projects];

    switch (sortBy) {
      case 'last_activity':
        sorted.sort((a, b) => {
          if (!a.lastActivityAt && !b.lastActivityAt) return 0;
          if (!a.lastActivityAt) return 1;
          if (!b.lastActivityAt) return -1;
          return new Date(b.lastActivityAt).getTime() - new Date(a.lastActivityAt).getTime();
        });
        break;
      case 'newest':
        sorted.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
        break;
      case 'name':
      default:
        sorted.sort((a, b) => a.name.localeCompare(b.name));
    }

    if (!searchQuery.trim()) return sorted;
    const query = searchQuery.toLowerCase();
    return sorted.filter((p) => p.name.toLowerCase().includes(query) || p.description?.toLowerCase().includes(query));
  }, [projects, searchQuery, sortBy]);

  const handleProjectClick = (projectId: number) => {
    router.visit(`/company/projects/${projectId}`);
  };

  return (
    <AuthLayout>
      <Box mih="100vh" bg="var(--app-bg-default)">
        <Group justify="space-between" align="flex-start" mb={24}>
          <Box>
            <Text fz={32} fw={600} c="white" mb={8}>
              Projects
            </Text>
            <Text fz={16} c="dimmed">
              Select a project to view workflows, assets, and tasks
            </Text>
          </Box>
          <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpened(true)}>
            Create Project
          </Button>
        </Group>

        {projects.length > 0 && (
          <Group gap={16} mb={24}>
            <TextInput
              placeholder="Search projects..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.currentTarget.value)}
              leftSection={<IconSearch size={16} />}
              w={300}
              size="sm"
            />
            <Select
              value={sortBy}
              onChange={(v) => setSortBy((v as SortKey) || 'name')}
              data={SORT_OPTIONS}
              w={180}
              size="sm"
            />
          </Group>
        )}

        {projects.length === 0 ? (
          <Center mih={400}>
            <Stack align="center" gap="md">
              <Text fz={48} opacity={0.5}>
                📁
              </Text>
              <Text fz={20} fw={500} c="white">
                No projects yet
              </Text>
              <Text fz={14} c="dimmed" ta="center" maw={400}>
                Create your first project to start organizing your work and collaborate with your team.
              </Text>
              <Button onClick={() => setCreateOpened(true)}>Create Your First Project</Button>
            </Stack>
          </Center>
        ) : sortedAndFiltered.length === 0 ? (
          <Center mih={400}>
            <Stack align="center" gap="md">
              <Text fz={48} opacity={0.5}>
                🔍
              </Text>
              <Text fz={20} fw={500} c="white">
                No projects found
              </Text>
              <Text fz={14} c="dimmed">
                No projects match your search. Try a different query.
              </Text>
            </Stack>
          </Center>
        ) : (
          <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing={24} mt={24}>
            {sortedAndFiltered.map((project) => (
              <ProjectCard key={project.id} project={project} onClick={() => handleProjectClick(project.id)} />
            ))}
          </SimpleGrid>
        )}

        <CreateProjectModal opened={createOpened} onClose={() => setCreateOpened(false)} />
      </Box>
    </AuthLayout>
  );
};

export default IndexPage;
