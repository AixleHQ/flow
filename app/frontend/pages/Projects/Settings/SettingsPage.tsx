import type { FormDataConvertible } from '@inertiajs/core';
import { Head, router, usePage } from '@inertiajs/react';
import {
  Avatar,
  Badge,
  Box,
  Button,
  Card,
  CopyButton,
  Divider,
  Group,
  Select,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Textarea,
  Title,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconArchive,
  IconCheck,
  IconChevronRight,
  IconCopy,
  IconLink,
  IconListDetails,
  IconLock,
  IconPlayerPlay,
  IconRoute,
  IconSourceCode,
  IconTrash,
} from '@tabler/icons-react';
import { zodResolver } from 'mantine-form-zod-resolver';
import { z } from 'zod';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './SettingsPage.module.css';

const LANGUAGE_OPTIONS = [
  { value: 'en', label: 'English' },
  { value: 'ru', label: 'Russian' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'pl', label: 'Polish' },
  { value: 'uk', label: 'Ukrainian' },
];

const STATE_CONFIG: Record<string, { label: string; color: string }> = {
  active: { label: 'Active', color: 'green' },
  paused: { label: 'Paused', color: 'yellow' },
  archived: { label: 'Archived', color: 'gray' },
};

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().max(500).optional(),
  preferredArtifactsLanguage: z.string(),
});

interface Member {
  id: number;
  name: string;
  email: string;
  isOwner: boolean;
}

interface Project {
  id: number;
  name: string;
  description: string | null;
  slug: string;
  state: string;
  preferredArtifactsLanguage: string;
  createdAt: string;
  updatedAt: string;
  ownerName: string;
  ownerEmail: string;
  sessionsCount: number;
  workflowsCount: number;
  boardTasksCount: number;
  repositoriesCount: number;
  integrationsCount: number;
}

interface Props {
  project: Project;
  members: Member[];
}

function avatarInitials(name: string): string {
  return name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

const SettingsPage = () => {
  const { project, members } = usePage<{ props: Props }>().props as unknown as Props;
  const basePath = `/company/projects/${project.id}`;

  const form = useForm({
    initialValues: {
      name: project.name,
      description: project.description || '',
      preferredArtifactsLanguage: project.preferredArtifactsLanguage || 'en',
    },
    validate: zodResolver(schema),
  });

  const handleSubmit = (values: typeof form.values) => {
    router.patch(
      `${basePath}/settings`,
      {
        project: {
          name: values.name.trim(),
          description: values.description.trim(),
          preferredArtifactsLanguage: values.preferredArtifactsLanguage,
        },
      } as Record<string, FormDataConvertible>,
      {
        preserveScroll: true,
        onSuccess: () => {
          notifications.show({ message: 'Project settings saved', color: 'green' });
        },
        onError: () => {
          notifications.show({ message: 'Failed to save settings', color: 'red' });
        },
      },
    );
  };

  const handleArchive = () => {
    modals.openConfirmModal({
      title: 'Archive Project',
      children: (
        <Text size="sm">
          Are you sure you want to archive <b>{project.name}</b>? The project will be hidden from the sidebar but its
          data will be preserved. You can restore it later.
        </Text>
      ),
      labels: { confirm: 'Archive', cancel: 'Cancel' },
      confirmProps: { color: 'orange' },
      onConfirm: () => {
        router.patch(
          `${basePath}/settings`,
          {
            project: { state: 'archived' },
          } as Record<string, FormDataConvertible>,
          {
            onSuccess: () => {
              notifications.show({ message: 'Project archived', color: 'orange' });
              router.visit('/company/projects');
            },
            onError: () => {
              notifications.show({ message: 'Failed to archive project', color: 'red' });
            },
          },
        );
      },
    });
  };

  const handleDelete = () => {
    modals.openConfirmModal({
      title: 'Delete Project',
      children: (
        <Text size="sm">
          Are you sure you want to permanently delete <b>{project.name}</b>? This action cannot be undone and all
          project data — including sessions, assets, and workflow runs — will be lost.
        </Text>
      ),
      labels: { confirm: 'Delete Project', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => {
        router.delete(`/company/projects/${project.id}`, {
          onSuccess: () => {
            notifications.show({ message: 'Project deleted', color: 'red' });
            router.visit('/company/projects');
          },
          onError: () => {
            notifications.show({ message: 'Failed to delete project', color: 'red' });
          },
        });
      },
    });
  };

  const stateConfig = STATE_CONFIG[project.state] ?? { label: project.state, color: 'gray' };

  return (
    <>
      <Head title={`Settings — ${project.name}`} />
      <Box className={classes.container}>
        <Text className={classes.pageTitle}>Project Settings</Text>
        <Text className={classes.pageSubtitle}>Manage project configuration and preferences</Text>

        {/* General */}
        <Card p={24} withBorder mb="lg" radius="md">
          <Title order={4} mb={4}>
            General
          </Title>
          <Divider mb="md" />

          <form onSubmit={form.onSubmit(handleSubmit)}>
            <Stack gap="md">
              <TextInput label="Project Name" placeholder="Enter project name" {...form.getInputProps('name')} />

              <Textarea
                label="Description"
                placeholder="Enter project description"
                minRows={3}
                {...form.getInputProps('description')}
              />

              <Select
                label="Artifacts Language"
                description="Language AI agents will use when generating artifacts and summaries"
                data={LANGUAGE_OPTIONS}
                {...form.getInputProps('preferredArtifactsLanguage')}
              />

              <Group justify="flex-end" mt="xs">
                <Button type="submit" disabled={!form.isDirty() || !form.values.name.trim()}>
                  Save Changes
                </Button>
              </Group>
            </Stack>
          </form>
        </Card>

        {/* Quick Links */}
        <Card p={24} withBorder mb="lg" radius="md">
          <Title order={4} mb={4}>
            Connections
          </Title>
          <Divider mb="md" />

          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
            <UnstyledButton className={classes.quickLinkCard} onClick={() => router.visit(`${basePath}/integrations`)}>
              <Group justify="space-between" wrap="nowrap">
                <Group gap="md" wrap="nowrap">
                  <IconLink size={22} color="var(--mantine-color-blue-5)" />
                  <Box>
                    <Text fw={600} size="sm">
                      Integrations
                    </Text>
                    <Text size="xs" c="dimmed">
                      {(project.integrationsCount ?? 0) > 0
                        ? `${project.integrationsCount} connected`
                        : 'Not configured'}
                    </Text>
                  </Box>
                </Group>
                <IconChevronRight size={16} color="var(--mantine-color-dimmed)" />
              </Group>
            </UnstyledButton>

            <UnstyledButton className={classes.quickLinkCard} onClick={() => router.visit(`${basePath}/repositories`)}>
              <Group justify="space-between" wrap="nowrap">
                <Group gap="md" wrap="nowrap">
                  <IconSourceCode size={22} color="var(--mantine-color-teal-5)" />
                  <Box>
                    <Text fw={600} size="sm">
                      Repositories
                    </Text>
                    <Text size="xs" c="dimmed">
                      {project.repositoriesCount > 0
                        ? `${project.repositoriesCount} repo${project.repositoriesCount !== 1 ? 's' : ''}`
                        : 'No repos added'}
                    </Text>
                  </Box>
                </Group>
                <IconChevronRight size={16} color="var(--mantine-color-dimmed)" />
              </Group>
            </UnstyledButton>
          </SimpleGrid>
        </Card>

        {/* Project Info */}
        <Card p={24} withBorder mb="lg" radius="md">
          <Title order={4} mb={4}>
            Project Info
          </Title>
          <Divider mb="md" />

          <Stack gap="md">
            <Box>
              <Box className={classes.fieldLabel}>
                <Text size="sm" fw={500} c="dimmed">
                  Status
                </Text>
              </Box>
              <Badge color={stateConfig.color} size="sm" variant="filled">
                {stateConfig.label}
              </Badge>
            </Box>

            <Box>
              <Box className={classes.fieldLabel}>
                <Text size="sm" fw={500} c="dimmed">
                  Slug
                </Text>
                <Tooltip label="Used in URLs and API. Cannot be changed.">
                  <IconLock size={14} color="var(--mantine-color-dimmed)" />
                </Tooltip>
              </Box>
              <Group gap="xs">
                <Text size="sm" ff="monospace">
                  {project.slug}
                </Text>
                <CopyButton value={project.slug}>
                  {({ copied, copy }) => (
                    <Tooltip label={copied ? 'Copied' : 'Copy slug'}>
                      <Button variant="subtle" size="compact-xs" p={4} onClick={copy}>
                        {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                      </Button>
                    </Tooltip>
                  )}
                </CopyButton>
              </Group>
            </Box>

            <Box>
              <Text size="sm" fw={500} c="dimmed" mb={4}>
                Owner
              </Text>
              <Group gap="sm">
                <Avatar size={28} radius="xl" color="blue">
                  {avatarInitials(project.ownerName)}
                </Avatar>
                <Box>
                  <Text size="sm" lh={1.2}>
                    {project.ownerName}
                  </Text>
                  <Text size="xs" c="dimmed" lh={1.2}>
                    {project.ownerEmail}
                  </Text>
                </Box>
              </Group>
            </Box>

            <Box>
              <Text size="sm" fw={500} c="dimmed" mb={4}>
                Created
              </Text>
              <Text size="sm">
                {new Date(project.createdAt).toLocaleDateString('en-US', {
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric',
                })}
              </Text>
            </Box>

            <Divider />

            <Box className={classes.statsGrid}>
              <Box className={classes.statItem}>
                <Group gap={4} justify="center" mb={2}>
                  <IconPlayerPlay size={14} color="var(--mantine-color-blue-5)" />
                </Group>
                <Text className={classes.statValue}>{project.sessionsCount}</Text>
                <Text className={classes.statLabel}>Sessions</Text>
              </Box>
              <Box className={classes.statItem}>
                <Group gap={4} justify="center" mb={2}>
                  <IconRoute size={14} color="var(--mantine-color-indigo-5)" />
                </Group>
                <Text className={classes.statValue}>{project.workflowsCount}</Text>
                <Text className={classes.statLabel}>Workflows</Text>
              </Box>
              <Box className={classes.statItem}>
                <Group gap={4} justify="center" mb={2}>
                  <IconSourceCode size={14} color="var(--mantine-color-teal-5)" />
                </Group>
                <Text className={classes.statValue}>{project.repositoriesCount}</Text>
                <Text className={classes.statLabel}>Repos</Text>
              </Box>
              <Box className={classes.statItem}>
                <Group gap={4} justify="center" mb={2}>
                  <IconListDetails size={14} color="var(--mantine-color-yellow-5)" />
                </Group>
                <Text className={classes.statValue}>{project.boardTasksCount}</Text>
                <Text className={classes.statLabel}>Tasks</Text>
              </Box>
            </Box>
          </Stack>
        </Card>

        {/* Members */}
        <Card p={24} withBorder mb="lg" radius="md">
          <Group justify="space-between" mb={4}>
            <Title order={4}>Members</Title>
            <Text size="xs" c="dimmed">
              {members.length} member{members.length !== 1 ? 's' : ''}
            </Text>
          </Group>
          <Divider mb="md" />

          <Stack gap="sm">
            {members.map((member) => (
              <Group key={member.id} justify="space-between">
                <Group gap="sm">
                  <Avatar size={32} radius="xl" color="blue">
                    {avatarInitials(member.name)}
                  </Avatar>
                  <Box>
                    <Text size="sm" fw={500} lh={1.2}>
                      {member.name}
                    </Text>
                    <Text size="xs" c="dimmed" lh={1.2}>
                      {member.email}
                    </Text>
                  </Box>
                </Group>
                <Badge
                  size="xs"
                  variant={member.isOwner ? 'filled' : 'outline'}
                  color={member.isOwner ? 'blue' : 'gray'}
                >
                  {member.isOwner ? 'Owner' : 'Member'}
                </Badge>
              </Group>
            ))}
          </Stack>
        </Card>

        {/* Danger Zone */}
        <Card p={24} className={classes.dangerCard} mb="lg">
          <Title order={4} mb={4} c="red">
            Danger Zone
          </Title>
          <Divider mb="md" color="red.9" />

          <Stack gap="lg">
            <Group justify="space-between" align="flex-start" wrap="nowrap">
              <Box>
                <Text size="sm" fw={500}>
                  Archive this project
                </Text>
                <Text size="xs" c="dimmed">
                  Hide from the sidebar and prevent new sessions. Data will be preserved.
                </Text>
              </Box>
              <Button
                variant="outline"
                color="orange"
                size="compact-sm"
                leftSection={<IconArchive size={14} />}
                onClick={handleArchive}
                style={{ flexShrink: 0 }}
              >
                Archive
              </Button>
            </Group>

            <Divider color="red.9" />

            <Group justify="space-between" align="flex-start" wrap="nowrap">
              <Box>
                <Text size="sm" fw={500}>
                  Delete this project
                </Text>
                <Text size="xs" c="dimmed">
                  Permanently remove this project and all of its data. This action cannot be undone.
                </Text>
              </Box>
              <Button
                variant="outline"
                color="red"
                size="compact-sm"
                leftSection={<IconTrash size={14} />}
                onClick={handleDelete}
                style={{ flexShrink: 0 }}
              >
                Delete
              </Button>
            </Group>
          </Stack>
        </Card>
      </Box>
    </>
  );
};

setPageLayout(SettingsPage, persistentProjectLayout);

export default SettingsPage;
