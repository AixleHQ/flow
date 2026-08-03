import { router } from '@inertiajs/react';
import { ActionIcon, Avatar, Badge, Box, Group, Text, UnstyledButton } from '@mantine/core';
import { IconExternalLink, IconRoute, IconSettings, IconSubtask, IconTerminal2 } from '@tabler/icons-react';

import classes from './ProjectCard.module.css';

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

interface ProjectCardProps {
  project: Project;
  onClick?: () => void;
}

const AVATAR_COLORS = [
  'blue',
  'cyan',
  'teal',
  'green',
  'lime',
  'yellow',
  'orange',
  'red',
  'pink',
  'grape',
  'violet',
  'indigo',
] as const;

const formatRelativeTime = (dateString?: string | null): string => {
  if (!dateString) return '';

  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
};

const pluralize = (count: number, singular: string) => (count === 1 ? singular : `${singular}s`);

const StatItem = ({ icon: Icon, value, label }: { icon: typeof IconTerminal2; value: number; label: string }) => (
  <Group gap={6} wrap="nowrap">
    <Icon size={16} style={{ opacity: 0.45, flexShrink: 0 }} />
    <Text fz={13} c="dimmed">
      {value} {pluralize(value, label)}
    </Text>
  </Group>
);

export const ProjectCard = ({ project, onClick }: ProjectCardProps) => {
  const avatarColor = AVATAR_COLORS[project.id % AVATAR_COLORS.length];
  const isActive = project.state === 'active';

  return (
    <Box className={classes.card} pos="relative">
      <Box className={classes.cardActions}>
        <ActionIcon
          variant="subtle"
          color="gray"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            onClick?.();
          }}
          title="Open project"
        >
          <IconExternalLink size={16} />
        </ActionIcon>
        <ActionIcon
          variant="subtle"
          color="gray"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            router.visit(`/company/projects/${project.id}/settings`);
          }}
          title="Project settings"
        >
          <IconSettings size={16} />
        </ActionIcon>
      </Box>

      <UnstyledButton
        onClick={onClick}
        p={20}
        display="flex"
        w="100%"
        style={{ flexDirection: 'column', alignItems: 'flex-start', flex: 1, borderRadius: 12 }}
      >
        <Group gap={12} align="center" w="100%" wrap="nowrap" mb={12}>
          <Avatar color={avatarColor} variant="filled" radius="xl" size="md">
            {project.name.charAt(0).toUpperCase()}
          </Avatar>
          <Group gap={8} wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
            <Box
              w={8}
              h={8}
              style={{
                borderRadius: '50%',
                backgroundColor: isActive ? 'var(--mantine-color-green-6)' : 'var(--mantine-color-gray-6)',
                flexShrink: 0,
              }}
            />
            <Text fz={18} fw={600} c="var(--app-text-primary)" lh={1.4} truncate style={{ flex: 1, minWidth: 0 }}>
              {project.name}
            </Text>
          </Group>
        </Group>

        <Box className={classes.descriptionSlot}>
          {project.description && (
            <Text fz={14} c="dimmed" className={classes.description}>
              {project.description}
            </Text>
          )}
        </Box>

        <Box mt="auto" w="100%">
          <Box className={classes.statsGrid}>
            <StatItem icon={IconTerminal2} value={project.sessionsCount} label="session" />
            <StatItem icon={IconRoute} value={project.workflowsCount} label="workflow" />
            <StatItem icon={IconSubtask} value={project.boardTasksCount} label="task" />
          </Box>
          <Group justify="space-between" align="center" mt={8}>
            <Text
              fz={12}
              c="dimmed"
              mih={18}
              lh="18px"
              style={{ visibility: project.lastActivityAt ? 'visible' : 'hidden' }}
            >
              Last activity {formatRelativeTime(project.lastActivityAt)}
            </Text>
            <Badge variant="default" size="xs" styles={{ root: { color: 'var(--app-text-secondary)' } }}>
              {project.membersCount} {pluralize(project.membersCount, 'member')}
            </Badge>
          </Group>
        </Box>
      </UnstyledButton>
    </Box>
  );
};
