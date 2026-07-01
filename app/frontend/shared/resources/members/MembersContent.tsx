import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Avatar,
  Badge,
  Box,
  Button,
  Group,
  Menu,
  Select,
  Table,
  Text,
  TextInput,
  Title,
  Tooltip,
} from '@mantine/core';
import { IconDotsVertical, IconPlus, IconSearch, IconTrash, IconUserCheck, IconUserOff } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import type { UserRole } from 'shared/ui';

import { InviteUserModal } from './InviteUserModal';

export interface MemberUser {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  state: string;
  position: string | null;
  invitedAt: string | null;
  createdAt: string;
  invitedBy: { id: number; name: string } | null;
}

interface MembersContentProps {
  users: MemberUser[];
  basePath: string;
  title: string;
  showRoleActions?: boolean;
}

const STATE_COLORS: Record<string, string> = {
  active: 'green',
  pending: 'yellow',
  suspended: 'orange',
  archived: 'gray',
};

const ROLE_COLORS: Record<UserRole, string> = {
  super_admin: 'grape',
  admin: 'blue',
  employee: 'gray',
  viewer: 'teal',
};

const ROLE_LABELS: Record<UserRole, string> = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  employee: 'Employee',
  viewer: 'Viewer',
};

const formatDate = (d: string | null) => {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

const ROLE_FILTER_OPTIONS = [
  { value: 'admin', label: 'Admin' },
  { value: 'employee', label: 'Employee' },
  { value: 'viewer', label: 'Viewer' },
];

const STATUS_FILTER_OPTIONS = [
  { value: 'active', label: 'Active' },
  { value: 'pending', label: 'Pending' },
  { value: 'archived', label: 'Archived' },
  { value: 'suspended', label: 'Suspended' },
];

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

export const MembersContent = ({ users, basePath, title, showRoleActions = true }: MembersContentProps) => {
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);

  const activeAdminCount = useMemo(
    () => users.filter((u) => (u.role === 'admin' || u.role === 'super_admin') && u.state === 'active').length,
    [users],
  );

  const isLastAdmin = (user: MemberUser) =>
    (user.role === 'admin' || user.role === 'super_admin') && user.state === 'active' && activeAdminCount <= 1;

  const filtered = useMemo(() => {
    let result = users;
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((u) => u.name.toLowerCase().includes(q) || u.email.toLowerCase().includes(q));
    }
    if (roleFilter) {
      result = result.filter((u) => u.role === roleFilter);
    }
    if (statusFilter) {
      result = result.filter((u) => u.state === statusFilter);
    }
    return result;
  }, [users, search, roleFilter, statusFilter]);

  const handleRoleChange = (userId: number, role: string) => {
    router.patch(`${basePath}/${userId}`, { user: { role } }, { preserveScroll: true });
  };

  const handleStateEvent = (userId: number, event: string) => {
    router.patch(`${basePath}/${userId}`, { user: { stateEvent: event } }, { preserveScroll: true });
  };

  const handleDelete = (userId: number, name: string) => {
    if (confirm(`Are you sure you want to remove ${name}?`)) {
      router.delete(`${basePath}/${userId}`, { preserveScroll: true });
    }
  };

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Title order={2}>{title}</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setInviteOpen(true)}>
          Invite Member
        </Button>
      </Group>

      <Group mb="lg" gap="sm">
        <TextInput
          placeholder="Search by name or email..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        <Select
          placeholder="All Roles"
          data={ROLE_FILTER_OPTIONS}
          value={roleFilter}
          onChange={setRoleFilter}
          clearable
          w={140}
        />
        <Select
          placeholder="All Statuses"
          data={STATUS_FILTER_OPTIONS}
          value={statusFilter}
          onChange={setStatusFilter}
          clearable
          w={150}
        />
        <Text size="xs" c="dimmed">
          {filtered.length} member{filtered.length !== 1 ? 's' : ''}
        </Text>
      </Group>

      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>User</Table.Th>
            <Table.Th>Role</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th>Invited</Table.Th>
            <Table.Th w={60} />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {filtered.map((user) => (
            <Table.Tr key={user.id}>
              <Table.Td>
                <Group gap="sm" wrap="nowrap">
                  <Avatar size={32} radius="xl" color="blue">
                    {getInitials(user.name)}
                  </Avatar>
                  <Box>
                    <Text fw={500} size="sm">
                      {user.name}
                    </Text>
                    <Text size="xs" c="dimmed">
                      {user.email}
                    </Text>
                  </Box>
                </Group>
              </Table.Td>
              <Table.Td>
                <Badge color={ROLE_COLORS[user.role]} size="sm" variant="light">
                  {ROLE_LABELS[user.role]}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Badge color={STATE_COLORS[user.state] ?? 'gray'} size="sm" variant="light">
                  {user.state}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Text size="sm">{formatDate(user.invitedAt ?? user.createdAt)}</Text>
                {user.invitedBy && (
                  <Text size="xs" c="dimmed">
                    by {user.invitedBy.name}
                  </Text>
                )}
                {!user.invitedBy && (
                  <Text size="xs" c="dimmed">
                    Self-registered
                  </Text>
                )}
              </Table.Td>
              <Table.Td>
                <Menu position="bottom-end" withArrow>
                  <Menu.Target>
                    <ActionIcon variant="subtle" size="sm">
                      <IconDotsVertical size={16} />
                    </ActionIcon>
                  </Menu.Target>
                  <Menu.Dropdown>
                    {showRoleActions && user.role === 'employee' && (
                      <Menu.Item
                        leftSection={<IconUserCheck size={14} />}
                        onClick={() => handleRoleChange(user.id, 'admin')}
                      >
                        Make Admin
                      </Menu.Item>
                    )}
                    {showRoleActions && user.role === 'admin' && (
                      <Tooltip label="Cannot modify the last admin" disabled={!isLastAdmin(user)}>
                        <Menu.Item
                          leftSection={<IconUserOff size={14} />}
                          disabled={isLastAdmin(user)}
                          onClick={() => handleRoleChange(user.id, 'employee')}
                        >
                          Make Employee
                        </Menu.Item>
                      </Tooltip>
                    )}
                    {showRoleActions && <Menu.Divider />}
                    {user.state === 'active' && (
                      <Tooltip label="Cannot modify the last admin" disabled={!isLastAdmin(user)}>
                        <Menu.Item disabled={isLastAdmin(user)} onClick={() => handleStateEvent(user.id, 'archive')}>
                          Archive
                        </Menu.Item>
                      </Tooltip>
                    )}
                    {user.state === 'archived' && (
                      <Menu.Item onClick={() => handleStateEvent(user.id, 'activate')}>Activate</Menu.Item>
                    )}
                    {user.state === 'pending' && (
                      <Menu.Item onClick={() => handleStateEvent(user.id, 'activate')}>Activate</Menu.Item>
                    )}
                    <Menu.Divider />
                    <Tooltip label="Cannot modify the last admin" disabled={!isLastAdmin(user)}>
                      <Menu.Item
                        color="red"
                        leftSection={<IconTrash size={14} />}
                        disabled={isLastAdmin(user)}
                        onClick={() => handleDelete(user.id, user.name)}
                      >
                        Remove
                      </Menu.Item>
                    </Tooltip>
                  </Menu.Dropdown>
                </Menu>
              </Table.Td>
            </Table.Tr>
          ))}
          {filtered.length === 0 && (
            <Table.Tr>
              <Table.Td colSpan={5}>
                <Text ta="center" c="dimmed" py="xl">
                  No members found
                </Text>
              </Table.Td>
            </Table.Tr>
          )}
        </Table.Tbody>
      </Table>

      <InviteUserModal opened={inviteOpen} onClose={() => setInviteOpen(false)} basePath={basePath} />
    </Box>
  );
};
