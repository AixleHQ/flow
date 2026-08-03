import { Head, router, usePage } from '@inertiajs/react';
import { Avatar, Badge, Box, Button, Group, List, Modal, Select, Text, TextInput, Title } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconPlus, IconSearch, IconTrash, IconCrown } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

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

  const handleAdd = () => {
    if (!selectedUserId) return;
    setLoading(true);
    router.post(
      basePath,
      { collaborator: { userId: Number(selectedUserId) } },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => {
          setAddOpen(false);
          setSelectedUserId(null);
        },
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
      <Box maw={800}>
        <Group justify="space-between" mb="lg">
          <Title order={2}>Project Members ({members.length})</Title>
          <Button leftSection={<IconPlus size={16} />} onClick={() => setAddOpen(true)}>
            Add Collaborator
          </Button>
        </Group>

        <TextInput
          placeholder="Search by name or email..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          mb="lg"
          maw={400}
        />

        <List spacing="xs" listStyleType="none">
          {filtered.map((member) => {
            const isOwner = member.id === ownerId;
            return (
              <List.Item
                key={member.id}
                styles={{
                  itemWrapper: { width: '100%' },
                  itemLabel: { width: '100%' },
                }}
              >
                <Group
                  justify="space-between"
                  wrap="nowrap"
                  p="sm"
                  style={{ borderBottom: '1px solid var(--mantine-color-default-border)' }}
                >
                  <Group gap="md" wrap="nowrap">
                    <Avatar color="blue" radius="xl" size="md">
                      {getInitials(member.name || member.email)}
                    </Avatar>
                    <Box>
                      <Group gap="xs">
                        <Text fw={500} size="sm">
                          {member.name || member.email}
                        </Text>
                        {isOwner && (
                          <Badge size="xs" color="blue" leftSection={<IconCrown size={10} />}>
                            Owner
                          </Badge>
                        )}
                      </Group>
                      <Text size="xs" c="dimmed">
                        {member.email}
                      </Text>
                    </Box>
                  </Group>
                  {!isOwner && (
                    <Button
                      variant="subtle"
                      color="red"
                      size="xs"
                      leftSection={<IconTrash size={14} />}
                      onClick={() => handleRemove(member)}
                    >
                      Remove
                    </Button>
                  )}
                </Group>
              </List.Item>
            );
          })}
          {filtered.length === 0 && (
            <Text ta="center" c="dimmed" py="xl">
              No members found
            </Text>
          )}
        </List>

        <Modal opened={addOpen} onClose={() => setAddOpen(false)} title="Add Collaborator" centered>
          <Select
            label="Select User"
            placeholder="Choose a company member..."
            data={selectData}
            value={selectedUserId}
            onChange={setSelectedUserId}
            searchable
            nothingFoundMessage="No users available"
            mb="xl"
          />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setAddOpen(false)} disabled={loading}>
              Cancel
            </Button>
            <Button onClick={handleAdd} loading={loading} disabled={!selectedUserId}>
              Add
            </Button>
          </Group>
        </Modal>
      </Box>
    </>
  );
};

setPageLayout(MembersPage, persistentProjectLayout);

export default MembersPage;
