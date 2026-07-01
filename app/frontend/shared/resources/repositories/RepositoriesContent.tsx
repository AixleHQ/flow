import { router } from '@inertiajs/react';
import { Badge, Box, Button, Card, Divider, Group, Menu, Stack, Text, ThemeIcon, Title } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconDotsVertical,
  IconEdit,
  IconFolder,
  IconGitBranch,
  IconLock,
  IconPlus,
  IconTrash,
  IconWorld,
} from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';

import { AddRepositoryModal } from './AddRepositoryModal';
import { EditRepositoryModal } from './EditRepositoryModal';

export interface Repository {
  id: number;
  fullName: string;
  cloneUrl: string;
  sourceBranch: string;
  isPrivate: boolean;
  description: string | null;
  purpose: string | null;
  scopeIndicator: string;
  integration: { id: number; name: string; provider: string };
  createdAt: string;
}

interface RepositoriesContentProps {
  repositories: Repository[];
  basePath: string;
  title: string;
  editBranches?: string[];
}

const RepoCard = ({
  repo,
  readOnly,
  canExecute,
  onEdit,
  onDelete,
  showScope,
}: {
  repo: Repository;
  readOnly?: boolean;
  canExecute: boolean;
  onEdit: (r: Repository) => void;
  onDelete: (r: Repository) => void;
  showScope?: boolean;
}) => (
  <Card withBorder p="md" radius="md">
    <Group justify="space-between" wrap="nowrap">
      <Group gap="md" wrap="nowrap">
        <ThemeIcon variant="light" size="lg" radius="md" color={repo.isPrivate ? 'yellow' : 'teal'}>
          {repo.isPrivate ? <IconLock size={18} /> : <IconWorld size={18} />}
        </ThemeIcon>
        <Box style={{ minWidth: 0 }}>
          <Group gap="xs" wrap="nowrap">
            <Text fw={600} size="sm" truncate>
              {repo.fullName}
            </Text>
            <Badge size="xs" variant="light" leftSection={<IconGitBranch size={10} />}>
              {repo.sourceBranch}
            </Badge>
            {showScope && (
              <Badge size="xs" variant="light" color={repo.scopeIndicator === 'project' ? 'green' : 'gray'}>
                {repo.scopeIndicator}
              </Badge>
            )}
          </Group>
          <Text size="xs" c="dimmed" truncate>
            {repo.integration.name}
            {repo.description && ` · ${repo.description}`}
          </Text>
          {repo.purpose && (
            <Text size="xs" c="dimmed" fs="italic" mt={2} lineClamp={1}>
              {repo.purpose}
            </Text>
          )}
        </Box>
      </Group>

      {!readOnly && canExecute && (
        <Menu position="bottom-end" withArrow>
          <Menu.Target>
            <Button variant="subtle" size="xs" p={4} color="gray">
              <IconDotsVertical size={16} />
            </Button>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Item leftSection={<IconEdit size={14} />} onClick={() => onEdit(repo)}>
              Edit
            </Menu.Item>
            <Menu.Item color="red" leftSection={<IconTrash size={14} />} onClick={() => onDelete(repo)}>
              Remove
            </Menu.Item>
          </Menu.Dropdown>
        </Menu>
      )}
    </Group>
  </Card>
);

export const RepositoriesContent = ({ repositories, basePath, title, editBranches }: RepositoriesContentProps) => {
  const { canExecute } = useProjectPermissions();
  const [editRepo, setEditRepo] = useState<Repository | null>(null);
  const [addModalOpen, setAddModalOpen] = useState(false);

  const handleEdit = (repo: Repository) => {
    setEditRepo(repo);
    router.reload({ data: { edit_repo_id: repo.id }, only: ['editBranches'] });
  };

  const isProjectContext = basePath.includes('projects');

  const projectRepos = useMemo(() => repositories.filter((r) => r.scopeIndicator === 'project'), [repositories]);
  const companyRepos = useMemo(() => repositories.filter((r) => r.scopeIndicator === 'company'), [repositories]);

  const handleDelete = (repo: Repository) => {
    modals.openConfirmModal({
      title: 'Remove Repository',
      children: (
        <Text size="sm">
          Remove <b>{repo.fullName}</b> from this {isProjectContext ? 'project' : 'company'}? Agent sessions will no
          longer have access to this repository.
        </Text>
      ),
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => {
        router.delete(`${basePath}/${repo.id}`, {
          preserveScroll: true,
          onSuccess: () => notifications.show({ message: 'Repository removed', color: 'green' }),
          onError: () => notifications.show({ message: 'Failed to remove repository', color: 'red' }),
        });
      },
    });
  };

  const canEdit = (repo: Repository) => !isProjectContext || repo.scopeIndicator === 'project';

  const renderRepoList = (repos: Repository[], readOnly = false) => (
    <Stack gap="sm">
      {repos.map((repo) => (
        <RepoCard
          key={repo.id}
          repo={repo}
          readOnly={readOnly || !canEdit(repo)}
          canExecute={canExecute}
          onEdit={handleEdit}
          onDelete={handleDelete}
          showScope={!isProjectContext}
        />
      ))}
    </Stack>
  );

  const renderSection = (label: string, repos: Repository[], readOnly = false) => (
    <Box>
      <Group gap="xs" mb="sm">
        <Text fw={600} size="sm" tt="uppercase" c="dimmed" lts={0.5}>
          {label}
        </Text>
        <Badge size="xs" variant="light" color="gray">
          {repos.length}
        </Badge>
      </Group>
      {repos.length === 0 ? (
        <Text c="dimmed" size="sm" mb="md">
          {readOnly ? 'No company-wide repositories available.' : 'No repositories in this scope.'}
        </Text>
      ) : (
        <Box mb="md">{renderRepoList(repos, readOnly)}</Box>
      )}
    </Box>
  );

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Box>
          <Title order={2}>{title}</Title>
          <Text size="sm" c="dimmed" mt={2}>
            Repositories available for agent sessions and code context
          </Text>
        </Box>
        {canExecute && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => setAddModalOpen(true)}>
            Add Repository
          </Button>
        )}
      </Group>

      {repositories.length === 0 ? (
        <Card p="xl" withBorder radius="md">
          <Stack align="center" gap="md" py="lg">
            <ThemeIcon size={56} radius="xl" variant="light" color="gray">
              <IconFolder size={28} />
            </ThemeIcon>
            <Box ta="center">
              <Text fw={500} size="lg">
                No repositories added
              </Text>
              <Text size="sm" c="dimmed" mt={4} maw={400}>
                Add repositories to use as code context in agent sessions. Connect a GitHub or GitLab integration first.
              </Text>
            </Box>
            {canExecute && (
              <Button variant="light" leftSection={<IconPlus size={16} />} onClick={() => setAddModalOpen(true)}>
                Add Repository
              </Button>
            )}
          </Stack>
        </Card>
      ) : isProjectContext ? (
        <Stack gap="lg">
          {renderSection('This Project', projectRepos)}
          {companyRepos.length > 0 && (
            <>
              <Divider />
              {renderSection('Company-wide', companyRepos, true)}
            </>
          )}
        </Stack>
      ) : (
        renderRepoList(repositories)
      )}

      <AddRepositoryModal
        opened={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        basePath={basePath}
        existingRepoNames={new Set(repositories.map((r) => r.fullName))}
      />
      <EditRepositoryModal
        repo={editRepo}
        branches={editBranches}
        basePath={basePath}
        onClose={() => setEditRepo(null)}
      />
    </Box>
  );
};
