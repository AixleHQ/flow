import { Head, router, usePage } from '@inertiajs/react';
import { ActionIcon, Avatar, Badge, Box, Button, Group, Select, Table, Text, TextInput, Tooltip } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconCrown, IconPlus, IconSearch, IconTrash, IconUsers } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface User {
  id: number;
  email: string;
  name: string;
  role: string;
  state: string;
}

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  members: User[];
  companyUsers: User[];
  ownerId: number;
}

const getInitials = (name: string) =>
  name
    .split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);

const MembersPage = () => {
  const { project, members, companyUsers, ownerId } = usePage<{ props: Props }>().props as unknown as Props;
  const [addOpen, setAddOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState('');
  const basePath = `/company/projects/${project.id}/members`;

  const existingIds = new Set(members.map((m) => m.id));
  const availableUsers = companyUsers.filter((u) => !existingIds.has(u.id));

  const selectData = availableUsers.map((u) => ({
    value: String(u.id),
    label: `${u.name} (${u.email})`,
  }));

  const filtered = useMemo(() => {
    if (!search.trim()) return members;
    const q = search.toLowerCase();
    return members.filter((m) => m.name.toLowerCase().includes(q) || m.email.toLowerCase().includes(q));
  }, [members, search]);

  const handleClose = () => {
    setAddOpen(false);
    setSelectedUserId(null);
  };

  const handleAdd = () => {
    if (!selectedUserId) return;
    setLoading(true);
    router.post(
      basePath,
      { collaborator: { userId: Number(selectedUserId) } },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => handleClose(),
      },
    );
  };

  const handleRemove = (user: User) => {
    modals.openConfirmModal({
      title: 'Remove collaborator',
      children: (
        <Text size="sm">
          Remove <b>{user.name}</b> from this project? They lose access to all project resources. This action cannot be
          undone.
        </Text>
      ),
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(`${basePath}/${user.id}`, { preserveScroll: true }),
    });
  };

  return (
    <>
      <Head title={`Members — ${project.name}`} />
      <Box>
        <PageHeader
          title="Project Members"
          actions={
            <Button leftSection={<IconPlus size={16} />} onClick={() => setAddOpen(true)}>
              Add Collaborator
            </Button>
          }
        />

        <Group mb="lg" gap="sm">
          <TextInput
            placeholder="Search by name or email…"
            aria-label="Search members"
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            w={260}
          />
          <ResourceCount>
            {filtered.length} member{filtered.length !== 1 ? 's' : ''}
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
              icon={<IconUsers size={22} />}
              title={search ? 'No members match your search' : 'No members yet'}
            />
          </Box>
        ) : (
          <ResourceTableShell minWidth={480}>
            <Table highlightOnHover>
              <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
                <Table.Tr>
                  <ResourceTh>User</ResourceTh>
                  <ResourceTh align="right" w={100}>
                    Actions
                  </ResourceTh>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {filtered.map((member) => {
                  const isOwner = member.id === ownerId;
                  return (
                    <Table.Tr key={member.id} style={{ height: 60 }}>
                      <Table.Td>
                        <Group gap="sm" wrap="nowrap">
                          <Avatar
                            size={32}
                            radius="xl"
                            styles={{
                              root: {
                                background: 'var(--app-bg-elevated)',
                                border: '1px solid var(--app-border-default)',
                                color: 'var(--app-text-secondary)',
                              },
                            }}
                          >
                            {getInitials(member.name || member.email)}
                          </Avatar>
                          <Box style={{ minWidth: 0 }}>
                            <Group gap={7} wrap="nowrap">
                              <Text fw={500} size="sm" c="var(--app-text-primary)">
                                {member.name || member.email}
                              </Text>
                              {isOwner && (
                                <Badge
                                  size="sm"
                                  variant="default"
                                  leftSection={<IconCrown size={12} />}
                                  styles={{
                                    root: {
                                      color: 'var(--app-warning-fg)',
                                      background: 'var(--app-warning-bg)',
                                      borderColor: 'var(--app-warning-border)',
                                    },
                                  }}
                                >
                                  Owner
                                </Badge>
                              )}
                            </Group>
                            <Text size="xs" c="dimmed">
                              {member.email}
                            </Text>
                          </Box>
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        {!isOwner && (
                          <Group gap={4} justify="flex-end">
                            <Tooltip label="Remove">
                              <ActionIcon
                                aria-label={`Remove ${member.name || member.email}`}
                                variant="subtle"
                                size="sm"
                                color="red"
                                onClick={() => handleRemove(member)}
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

        <ResourceDrawer
          opened={addOpen}
          onClose={handleClose}
          title="Add Collaborator"
          footer={
            <Button fullWidth onClick={handleAdd} loading={loading} disabled={!selectedUserId}>
              Add
            </Button>
          }
        >
          <Select
            label="Select User"
            placeholder="Choose a company member…"
            data={selectData}
            value={selectedUserId}
            onChange={setSelectedUserId}
            searchable
            nothingFoundMessage="No users available"
          />
        </ResourceDrawer>
      </Box>
    </>
  );
};

setPageLayout(MembersPage, persistentProjectLayout);

export default MembersPage;
