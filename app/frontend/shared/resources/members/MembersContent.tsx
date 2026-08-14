import { router, usePage } from '@inertiajs/react';
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
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import {
  IconDotsVertical,
  IconEye,
  IconMailForward,
  IconPlus,
  IconSearch,
  IconShieldCheck,
  IconTrash,
  IconUserCheck,
  IconUserOff,
  IconUsers,
} from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import type { SharedProps, UserRole } from 'shared/ui';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { InviteMemberDrawer } from './InviteMemberDrawer';

// A company-membership row: `id` is the user id (member routes are keyed by
// user id), while `role`/`state` are the PER-COMPANY membership role and state
// (invited | active | suspended).
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
  subtitle?: string;
  showRoleActions?: boolean;
}

// Revoked members are never rendered (the index excludes them).
// Admin is the only role with a colored tag — an amber fill + shield icon —
// so role scans instantly without every role competing for attention.
const ROLE_TAG_STYLES: Record<UserRole, { color: string; background: string; borderColor: string }> = {
  admin: {
    color: 'var(--app-warning-fg)',
    background: 'var(--app-warning-bg)',
    borderColor: 'var(--app-warning-border)',
  },
  super_admin: {
    color: 'var(--app-warning-fg)',
    background: 'var(--app-warning-bg)',
    borderColor: 'var(--app-warning-border)',
  },
  employee: {
    color: 'var(--app-text-secondary)',
    background: 'var(--app-action-hover)',
    borderColor: 'var(--app-border-default)',
  },
  viewer: { color: 'var(--app-info-fg)', background: 'var(--app-info-bg)', borderColor: 'var(--app-info-border)' },
};

const ROLE_LABELS: Record<UserRole, string> = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  employee: 'Employee',
  viewer: 'Viewer',
};

const ROLE_ICONS: Partial<Record<UserRole, typeof IconShieldCheck>> = {
  admin: IconShieldCheck,
  super_admin: IconShieldCheck,
  viewer: IconEye,
};

function RoleTag({ role }: { role: UserRole }) {
  const Icon = ROLE_ICONS[role];
  return (
    <Badge
      size="sm"
      variant="default"
      styles={{ root: ROLE_TAG_STYLES[role] }}
      leftSection={Icon ? <Icon size={12} /> : undefined}
    >
      {ROLE_LABELS[role]}
    </Badge>
  );
}

const formatDate = (d: string | null) => {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

const ROLE_FILTER_OPTIONS = [
  { value: 'all', label: 'All Roles' },
  { value: 'admin', label: 'Admins' },
  { value: 'employee', label: 'Employees' },
  { value: 'viewer', label: 'Viewers' },
];

const STATUS_FILTER_OPTIONS = [
  { value: 'active', label: 'Active' },
  { value: 'invited', label: 'Invited' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'all', label: 'All Statuses' },
];

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

export const MembersContent = ({ users, basePath, title, subtitle, showRoleActions = true }: MembersContentProps) => {
  const { currentUser, permissions } = usePage<SharedProps>().props;
  // Every control this page offers mutates membership, so the whole action surface hangs off one
  // permission. `permissions` is optional on SharedProps — absent means "not permitted", matching
  // what the server would answer. Read access to the page itself stays open by design.
  const canManageMembers = permissions?.canManageMembers ?? false;
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('active');
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
    if (roleFilter !== 'all') {
      result = result.filter((u) => u.role === roleFilter);
    }
    if (statusFilter !== 'all') {
      result = result.filter((u) => u.state === statusFilter);
    }
    return result;
  }, [users, search, roleFilter, statusFilter]);

  const hasFilters = !!search || roleFilter !== 'all' || statusFilter !== 'active';

  const handleRoleChange = (userId: number, role: string) => {
    router.patch(`${basePath}/${userId}`, { user: { role } }, { preserveScroll: true });
  };

  const handleStateEvent = (userId: number, event: string) => {
    router.patch(`${basePath}/${userId}`, { user: { stateEvent: event } }, { preserveScroll: true });
  };

  const handleResend = (userId: number) => {
    router.post(`${basePath}/${userId}/resend`, {}, { preserveScroll: true });
  };

  const handleDelete = (userId: number, name: string) => {
    modals.openConfirmModal({
      title: 'Remove member',
      children: (
        <Text size="sm">
          Remove <b>{name}</b> from this company? They lose access to every project in it. This action cannot be undone.
        </Text>
      ),
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(`${basePath}/${userId}`, { preserveScroll: true }),
    });
  };

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle={subtitle}
        actions={
          canManageMembers ? (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setInviteOpen(true)}>
              Invite Member
            </Button>
          ) : undefined
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
        <Select
          aria-label="Filter by role"
          data={ROLE_FILTER_OPTIONS}
          value={roleFilter}
          onChange={(value) => setRoleFilter(value ?? 'all')}
          allowDeselect={false}
          w={140}
        />
        <Select
          aria-label="Filter by status"
          data={STATUS_FILTER_OPTIONS}
          value={statusFilter}
          onChange={(value) => setStatusFilter(value ?? 'active')}
          allowDeselect={false}
          w={150}
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
            title={hasFilters ? 'No members match your filters' : 'No members yet'}
          />
        </Box>
      ) : (
        <ResourceTableShell>
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <ResourceTh>User</ResourceTh>
                <ResourceTh>Role</ResourceTh>
                <ResourceTh>Status</ResourceTh>
                <ResourceTh>Invited</ResourceTh>
                {canManageMembers && (
                  <ResourceTh align="right" w={60}>
                    Actions
                  </ResourceTh>
                )}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((user) => {
                const isSelf = currentUser != null && user.id === currentUser.id;
                return (
                  <Table.Tr
                    key={user.id}
                    style={{
                      height: 60,
                      opacity: user.state === 'suspended' ? 0.52 : undefined,
                    }}
                  >
                    <Table.Td>
                      <Group gap="sm" wrap="nowrap">
                        <Avatar
                          size={32}
                          radius="xl"
                          styles={{
                            root: isSelf
                              ? {
                                  background: 'var(--app-action-selected)',
                                  border: '1px solid var(--app-primary)',
                                  color: 'var(--app-primary)',
                                }
                              : {
                                  background: 'var(--app-bg-elevated)',
                                  border: '1px solid var(--app-border-default)',
                                  color: 'var(--app-text-secondary)',
                                },
                          }}
                        >
                          {getInitials(user.name)}
                        </Avatar>
                        <Box style={{ minWidth: 0 }}>
                          <Group gap={7} wrap="nowrap">
                            <Text fw={500} size="sm" c="var(--app-text-primary)">
                              {user.name}
                            </Text>
                            {isSelf && (
                              <Badge
                                size="xs"
                                variant="default"
                                styles={{
                                  root: {
                                    color: 'var(--app-primary)',
                                    background: 'var(--app-action-selected)',
                                    borderColor: 'var(--app-primary)',
                                  },
                                }}
                              >
                                You
                              </Badge>
                            )}
                          </Group>
                          <Text size="xs" c="dimmed">
                            {user.email}
                          </Text>
                        </Box>
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <RoleTag role={user.role} />
                    </Table.Td>
                    <Table.Td>
                      <StatusBadge state={user.state} size="sm" />
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm" c="var(--app-text-primary)">
                        {formatDate(user.invitedAt ?? user.createdAt)}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {user.invitedBy ? `by ${user.invitedBy.name}` : 'Self-registered'}
                      </Text>
                    </Table.Td>
                    {/* The row menu holds only membership-mutating items, so without the
                        permission there is nothing left for it to offer — the column goes with it. */}
                    {canManageMembers && (
                      <Table.Td>
                        {isSelf ? null : (
                          <Group gap={4} justify="flex-end">
                            <Menu position="bottom-end" withArrow>
                              <Menu.Target>
                                <ActionIcon variant="subtle" size="sm" aria-label={`Actions for ${user.name}`}>
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
                                {user.state === 'invited' && (
                                  <Menu.Item
                                    leftSection={<IconMailForward size={14} />}
                                    onClick={() => handleResend(user.id)}
                                  >
                                    Resend Invitation
                                  </Menu.Item>
                                )}
                                {user.state === 'active' && (
                                  <Tooltip label="Cannot modify the last admin" disabled={!isLastAdmin(user)}>
                                    <Menu.Item
                                      disabled={isLastAdmin(user)}
                                      onClick={() => handleStateEvent(user.id, 'suspend')}
                                    >
                                      Suspend
                                    </Menu.Item>
                                  </Tooltip>
                                )}
                                {user.state === 'suspended' && (
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
                          </Group>
                        )}
                      </Table.Td>
                    )}
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </ResourceTableShell>
      )}

      {canManageMembers && (
        <InviteMemberDrawer opened={inviteOpen} onClose={() => setInviteOpen(false)} basePath={basePath} />
      )}
    </Box>
  );
};
