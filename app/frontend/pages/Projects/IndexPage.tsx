import { Head, router, usePage } from '@inertiajs/react';
import { Box, Button, Group, SegmentedControl, Select, Text, TextInput } from '@mantine/core';
import { IconArrowsSort, IconFilterOff, IconFolder, IconPlus, IconSearch } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { EmptyState } from 'shared/ui';
import { PageHeader } from 'shared/ui/PageHeader';

import { CreateProjectModal } from './CreateProjectModal';
import classes from './IndexPage.module.css';
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
  members: { id: number; initials: string }[];
}

interface PageProps {
  projects: Project[];
  [key: string]: unknown;
}

type SortKey = 'name' | 'last_activity' | 'newest';
type StateFilter = 'all' | 'active' | 'paused' | 'archived';

const SORT_OPTIONS = [
  { value: 'name', label: 'Name' },
  { value: 'last_activity', label: 'Last activity' },
  { value: 'newest', label: 'Newest first' },
];

const STATE_FILTER_OPTIONS: { value: StateFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'active', label: 'Active' },
  { value: 'paused', label: 'Paused' },
  { value: 'archived', label: 'Archived' },
];

const IndexPage = () => {
  const { projects } = usePage<PageProps>().props;
  const [createOpened, setCreateOpened] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<SortKey>('name');
  // Archived (and paused) projects are noise in the everyday view, so the
  // default view hides everything but active — matching the segmented
  // control's default selection.
  const [stateFilter, setStateFilter] = useState<StateFilter>('active');

  const byState = useMemo(
    () => (stateFilter === 'all' ? projects : projects.filter((p) => p.state === stateFilter)),
    [projects, stateFilter],
  );

  const sortedAndFiltered = useMemo(() => {
    const sorted = [...byState];

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
  }, [byState, searchQuery, sortBy]);

  const handleProjectClick = (projectId: number) => {
    router.visit(`/company/projects/${projectId}`);
  };

  const stateFilterLabel = STATE_FILTER_OPTIONS.find((o) => o.value === stateFilter)?.label ?? stateFilter;

  return (
    <AuthLayout>
      <Head title="Projects" />
      <Box>
        <PageHeader
          title="Projects"
          subtitle="Select a project to view workflows, assets, and tasks"
          mb={24}
          actions={
            <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpened(true)}>
              Create Project
            </Button>
          }
        />

        {projects.length > 0 && (
          <Group gap={12} mb={20} wrap="wrap">
            <TextInput
              placeholder="Search projects..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.currentTarget.value)}
              leftSection={<IconSearch size={16} />}
              w={300}
              size="sm"
            />
            <SegmentedControl
              value={stateFilter}
              onChange={(v) => setStateFilter(v as StateFilter)}
              data={STATE_FILTER_OPTIONS}
              size="sm"
            />
            <Group gap={14} ml="auto" wrap="nowrap">
              <Text className={classes.resultCount}>
                <Text component="span" className={classes.resultCountNum}>
                  {sortedAndFiltered.length}
                </Text>{' '}
                {sortedAndFiltered.length === 1 ? 'project' : 'projects'}
              </Text>
              <Select
                value={sortBy}
                onChange={(v) => setSortBy((v as SortKey) || 'name')}
                data={SORT_OPTIONS}
                leftSection={<IconArrowsSort size={15} />}
                w={180}
                size="sm"
              />
            </Group>
          </Group>
        )}

        {projects.length === 0 ? (
          <EmptyState
            icon={<IconFolder size={22} />}
            title="No projects yet"
            description="Create your first project to start organizing your work and collaborate with your team."
            action={<Button onClick={() => setCreateOpened(true)}>Create Your First Project</Button>}
          />
        ) : byState.length === 0 ? (
          <EmptyState icon={<IconFilterOff size={22} />} title={`No ${stateFilterLabel.toLowerCase()} projects`} />
        ) : sortedAndFiltered.length === 0 ? (
          <EmptyState
            icon={<IconSearch size={22} />}
            title="No projects found"
            description={`No projects match "${searchQuery}".`}
          />
        ) : (
          <Box className={classes.grid}>
            {sortedAndFiltered.map((project) => (
              <ProjectCard key={project.id} project={project} onClick={() => handleProjectClick(project.id)} />
            ))}
          </Box>
        )}

        <CreateProjectModal opened={createOpened} onClose={() => setCreateOpened(false)} />
      </Box>
    </AuthLayout>
  );
};

export default IndexPage;
