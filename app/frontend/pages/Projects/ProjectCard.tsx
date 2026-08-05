import { router } from '@inertiajs/react';
import { Avatar, Box, Button, Group, Text, Tooltip, UnstyledButton } from '@mantine/core';
import { IconArrowRight, IconClock, IconSettings } from '@tabler/icons-react';

import { Identicon, StatusBadge } from 'shared/ui';

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
  members: { id: number; initials: string }[];
}

interface ProjectCardProps {
  project: Project;
  onClick?: () => void;
}

const formatRelativeTime = (dateString?: string | null): string => {
  if (!dateString) return 'Not yet active';

  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffDays >= 7) return `Updated ${date.toLocaleDateString()}`;
  if (diffDays >= 1) return `Updated ${diffDays}d ago`;
  if (diffHours >= 1) return `Updated ${diffHours}h ago`;
  if (diffMins >= 1) return `Updated ${diffMins}m ago`;
  return 'Updated just now';
};

const pluralize = (count: number, singular: string) => (count === 1 ? singular : `${singular}s`);

const StatItem = ({ value, label }: { value: number; label: string }) => (
  <Box className={classes.stat}>
    <Group gap={5} align="baseline">
      <Text className={classes.statNum}>{value}</Text>
      <Text className={classes.statLabel}> {pluralize(value, label)}</Text>
    </Group>
  </Box>
);

const MemberAvatars = ({ members, total }: { members: { id: number; initials: string }[]; total: number }) => {
  const overflow = total - members.length;
  return (
    <Group gap={0} aria-label={`${total} ${pluralize(total, 'member')}`}>
      {members.map((member) => (
        <Avatar key={member.id} size={24} radius="xl" className={classes.memberAvatar}>
          {member.initials}
        </Avatar>
      ))}
      {overflow > 0 && (
        <Avatar size={24} radius="xl" className={classes.memberAvatar}>
          +{overflow}
        </Avatar>
      )}
    </Group>
  );
};

export const ProjectCard = ({ project, onClick }: ProjectCardProps) => {
  const isArchived = project.state === 'archived';

  return (
    <Box className={`${classes.card} ${isArchived ? classes.archived : ''}`}>
      <UnstyledButton onClick={onClick} className={classes.clickArea}>
        <Group gap={12} align="center" wrap="nowrap">
          <Box className={classes.avatar}>
            <Identicon seed={project.name} size={24} />
          </Box>
          <Tooltip label={project.description} disabled={!project.description} openDelay={300}>
            <Text className={classes.name} title={project.name}>
              {project.name}
            </Text>
          </Tooltip>
          <StatusBadge state={project.state} className={classes.statusBadge} />
        </Group>

        <Box className={classes.statsGrid}>
          <StatItem value={project.sessionsCount} label="session" />
          <StatItem value={project.workflowsCount} label="workflow" />
          <StatItem value={project.boardTasksCount} label="task" />
        </Box>

        <Group justify="space-between" align="center" wrap="nowrap" gap={12}>
          <Group gap={6} wrap="nowrap" className={classes.activity}>
            <IconClock size={13} style={{ flexShrink: 0 }} />
            <Text className={classes.activityText}>{formatRelativeTime(project.lastActivityAt)}</Text>
          </Group>
          <MemberAvatars members={project.members} total={project.membersCount} />
        </Group>
      </UnstyledButton>

      <Group gap={8} className={classes.actions}>
        <Button
          variant="light"
          color="brand"
          leftSection={<IconArrowRight size={14} />}
          size="sm"
          className={classes.openButton}
          onClick={(e) => {
            e.stopPropagation();
            onClick?.();
          }}
        >
          Open
        </Button>
        <Button
          variant="default"
          leftSection={<IconSettings size={14} />}
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            router.visit(`/company/projects/${project.id}/settings`);
          }}
        >
          Settings
        </Button>
      </Group>
    </Box>
  );
};
