import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Group,
  SegmentedControl,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconEdit,
  IconFolder,
  IconGitBranch,
  IconLock,
  IconPlus,
  IconSearch,
  IconTrash,
  IconWorld,
} from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';

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
  integration: { id: number; name: string; provider: string } | null;
  publicSource?: boolean;
  createdAt: string;
}

interface RepositoriesContentProps {
  repositories: Repository[];
  basePath: string;
  title: string;
  editBranches?: string[];
}

const SCOPE_COLORS: Record<string, string> = {
  company: 'gray',
  project: 'green',
};

export const RepositoriesContent = ({ repositories, basePath, title, editBranches }: RepositoriesContentProps) => {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const [scopeFilter, setScopeFilter] = useState('all');
  const [editRepo, setEditRepo] = useState<Repository | null>(null);
  const [addModalOpen, setAddModalOpen] = useState(false);

  const isProjectContext = basePath.includes('projects');

  const filtered = useMemo(() => {
    let result = repositories;

    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((r) => r.fullName.toLowerCase().includes(q));
    }

    if (scopeFilter !== 'all') {
      result = result.filter((r) => r.scopeIndicator === scopeFilter);
    }

    return result;
  }, [repositories, search, scopeFilter]);

  const hasFilters = !!search || scopeFilter !== 'all';

  const canEdit = (repo: Repository) => !isProjectContext || repo.scopeIndicator === 'project';

  const handleEdit = (repo: Repository) => {
    setEditRepo(repo);
    router.reload({ data: { edit_repo_id: repo.id }, only: ['editBranches'] });
  };

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

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle="Repositories available for agent sessions and code context"
        actions={
          canExecute && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setAddModalOpen(true)}>
              Add Repository
            </Button>
          )
        }
      />

      <Group gap="md" mb="lg">
        <TextInput
          placeholder="Search repositories..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        {isProjectContext && (
          <SegmentedControl
            value={scopeFilter}
            onChange={setScopeFilter}
            data={[
              { label: 'All', value: 'all' },
              { label: 'Project', value: 'project' },
              { label: 'Company', value: 'company' },
            ]}
            size="sm"
          />
        )}
        <ResourceCount>
          {filtered.length} {filtered.length === 1 ? 'repository' : 'repositories'}
        </ResourceCount>
      </Group>

      {filtered.length === 0 ? (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
          }}
        >
          <EmptyState
            icon={<IconFolder size={22} />}
            title={
              hasFilters
                ? scopeFilter !== 'all' && !search
                  ? 'No repositories in this scope'
                  : 'No repositories match your filters'
                : 'No repositories added'
            }
            description={
              hasFilters
                ? undefined
                : 'Add repositories to use as code context in agent sessions. Connect a GitHub or GitLab integration first.'
            }
            action={
              !hasFilters &&
              canExecute && (
                <Button variant="outline" onClick={() => setAddModalOpen(true)}>
                  Add Repository
                </Button>
              )
            }
          />
        </Box>
      ) : (
        <ResourceTableShell>
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <ResourceTh>Repository</ResourceTh>
                <ResourceTh>Source</ResourceTh>
                {isProjectContext && <ResourceTh>Scope</ResourceTh>}
                <ResourceTh align="right" w={90}>
                  Actions
                </ResourceTh>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((repo) => {
                const readOnly = !canEdit(repo);
                return (
                  <Table.Tr key={repo.id}>
                    <Table.Td>
                      <Group gap="sm" wrap="nowrap">
                        <Box
                          w={36}
                          h={36}
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            backgroundColor: 'var(--app-bg-deep)',
                            borderRadius: 'var(--mantine-radius-sm)',
                            color: repo.isPrivate ? 'var(--app-warning-fg)' : 'var(--app-text-secondary)',
                            flexShrink: 0,
                          }}
                        >
                          {repo.isPrivate ? <IconLock size={16} /> : <IconWorld size={16} />}
                        </Box>
                        <Box style={{ minWidth: 0 }}>
                          <Group gap={6} wrap="nowrap">
                            <Text fz={14} fw={500} c="var(--app-text-primary)" truncate>
                              {repo.fullName}
                            </Text>
                            <Badge size="xs" variant="light" leftSection={<IconGitBranch size={10} />}>
                              {repo.sourceBranch}
                            </Badge>
                          </Group>
                          {repo.purpose && (
                            <Text fz={12} c="dimmed" truncate maw={340}>
                              {repo.purpose}
                            </Text>
                          )}
                        </Box>
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <Text fz={13} c="dimmed">
                        {repo.integration?.name ?? (repo.publicSource ? 'Public (read-only)' : 'No integration')}
                      </Text>
                    </Table.Td>
                    {isProjectContext && (
                      <Table.Td>
                        <Badge color={SCOPE_COLORS[repo.scopeIndicator] ?? 'gray'} size="sm" variant="light">
                          {repo.scopeIndicator}
                        </Badge>
                      </Table.Td>
                    )}
                    <Table.Td>
                      {canExecute && (
                        <Group gap={4} justify="flex-end">
                          <Tooltip label={readOnly ? 'Company-managed' : 'Edit'}>
                            <ActionIcon
                              aria-label="Edit"
                              variant="subtle"
                              size="sm"
                              disabled={readOnly}
                              onClick={() => handleEdit(repo)}
                            >
                              <IconEdit size={16} />
                            </ActionIcon>
                          </Tooltip>
                          <Tooltip label={readOnly ? 'Company-managed' : 'Remove'}>
                            <ActionIcon
                              aria-label="Remove"
                              variant="subtle"
                              size="sm"
                              color="red"
                              disabled={readOnly}
                              onClick={() => handleDelete(repo)}
                            >
                              <IconTrash size={16} />
                            </ActionIcon>
                          </Tooltip>
                        </Group>
                      )}
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </ResourceTableShell>
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
