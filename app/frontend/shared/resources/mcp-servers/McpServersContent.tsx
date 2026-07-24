import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Center,
  Group,
  SegmentedControl,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { IconEdit, IconPlus, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';

import { DeleteMcpServerModal } from './DeleteMcpServerModal';
import { McpServerFormModal } from './McpServerFormModal';

type McpServerKind = 'internal' | 'custom';
type Transport = 'http' | 'sse' | 'stdio';

export interface McpServer {
  id: number;
  name: string;
  url: string | null;
  transport: Transport;
  headers: Record<string, string> | null;
  description: string | null;
  kind: McpServerKind;
  scopeType: string | null;
  scopeId: number | null;
  scopeIndicator: string;
  enabled: boolean;
  internal: boolean;
  command: string | null;
  env: Record<string, string> | null;
  // OAuth (oauth-unification §4.3/§4.6). oauthStatus is per-current-user and read-only.
  authType?: 'none' | 'static' | 'oauth';
  credentialScope?: 'shared' | 'per_user';
  oauthStatus?: 'pending' | 'active' | 'expiring' | 'error' | null;
  createdAt: string;
  updatedAt: string;
}

// Maps a server's per-user oauth_status to a connection badge (functional labels,
// not colour alone, so the state reads without relying on hue).
const OAUTH_STATUS_BADGE: Record<string, { color: string; label: string }> = {
  active: { color: 'green', label: 'Connected' },
  expiring: { color: 'yellow', label: 'Expiring' },
  pending: { color: 'gray', label: 'Not connected' },
  error: { color: 'red', label: 'Reconnect' },
};

type EditableScope = 'company' | 'project';

interface McpServersContentProps {
  mcpServers: McpServer[];
  configItemNames: string[];
  basePath: string;
  title: string;
  subtitle: string;
  editableScope?: EditableScope;
}

function canEditServer(server: McpServer, editableScope?: EditableScope): boolean {
  if (server.kind !== 'custom') return false;
  if (!editableScope) return true;
  return server.scopeIndicator === editableScope;
}

function readOnlyLabel(server: McpServer, editableScope?: EditableScope): string {
  if (server.internal) return 'System';
  if (editableScope === 'project' && server.scopeIndicator === 'company') return 'Company';
  return 'Read-only';
}

export function McpServersContent({
  mcpServers,
  configItemNames,
  basePath,
  title,
  subtitle,
  editableScope,
}: McpServersContentProps) {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const [kindFilter, setKindFilter] = useState('custom');
  const [formModalOpen, setFormModalOpen] = useState(false);
  const [editServer, setEditServer] = useState<McpServer | null>(null);
  const [deleteServer, setDeleteServer] = useState<McpServer | null>(null);

  const filtered = useMemo(() => {
    let result = mcpServers;

    if (kindFilter !== 'all') {
      result = result.filter((s) => s.kind === kindFilter);
    }

    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((s) => s.name.toLowerCase().includes(q));
    }

    return result;
  }, [mcpServers, search, kindFilter]);

  const handleEdit = (server: McpServer) => {
    setEditServer(server);
    setFormModalOpen(true);
  };

  const handleFormClose = () => {
    setFormModalOpen(false);
    setEditServer(null);
  };

  const hasFilters = !!search.trim() || kindFilter !== 'all';

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Box>
          <Text fz={24} fw={600} c="var(--app-text-primary)">
            {title}
          </Text>
          <Text fz={14} c="dimmed" mt={4}>
            {subtitle}
          </Text>
        </Box>
        {canExecute && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => setFormModalOpen(true)}>
            Add MCP Server
          </Button>
        )}
      </Group>

      <Group gap="md" mb="lg">
        <TextInput
          placeholder="Search by name..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        <SegmentedControl
          value={kindFilter}
          onChange={setKindFilter}
          data={[
            { label: 'All', value: 'all' },
            { label: 'System', value: 'internal' },
            { label: 'Custom', value: 'custom' },
          ]}
        />
      </Group>

      {filtered.length === 0 ? (
        <Center
          mih={300}
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
            flexDirection: 'column',
          }}
        >
          <Text fz={48}>🔌</Text>
          <Text fz={16} c="dimmed" mt="sm">
            {hasFilters ? 'No MCP servers match your filters' : 'No MCP servers configured'}
          </Text>
          {!hasFilters && canExecute && (
            <Button variant="outline" mt="sm" onClick={() => setFormModalOpen(true)}>
              Add your first MCP server
            </Button>
          )}
        </Center>
      ) : (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            overflow: 'hidden',
          }}
        >
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Name
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    URL
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Transport
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Scope
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Status
                  </Text>
                </Table.Th>
                <Table.Th w={100}>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" ta="right" style={{ letterSpacing: 0.5 }}>
                    Actions
                  </Text>
                </Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((server) => {
                const canEdit = canExecute && canEditServer(server, editableScope);
                return (
                  <Table.Tr key={server.id}>
                    <Table.Td>
                      <Text fz={14} fw={500} c="var(--app-text-primary)">
                        {server.name}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Text
                        fz={13}
                        c="dimmed"
                        maw={300}
                        style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                      >
                        {server.url || '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge variant="outline" size="sm">
                        {server.transport.toUpperCase()}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge
                        color={
                          server.scopeIndicator === 'internal'
                            ? 'violet'
                            : server.scopeIndicator === 'project'
                              ? 'teal'
                              : 'blue'
                        }
                        size="sm"
                        variant="light"
                      >
                        {server.scopeIndicator === 'internal'
                          ? 'System'
                          : server.scopeIndicator === 'project'
                            ? 'Project'
                            : 'Company'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        <Badge color={server.enabled ? 'green' : 'gray'} size="sm">
                          {server.enabled ? 'Enabled' : 'Disabled'}
                        </Badge>
                        {server.authType === 'oauth' && (
                          <Badge
                            color={OAUTH_STATUS_BADGE[server.oauthStatus ?? 'pending'].color}
                            variant="light"
                            size="sm"
                          >
                            {OAUTH_STATUS_BADGE[server.oauthStatus ?? 'pending'].label}
                          </Badge>
                        )}
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} justify="flex-end">
                        {canEdit ? (
                          <>
                            <Tooltip label="Edit">
                              <ActionIcon variant="subtle" size="sm" onClick={() => handleEdit(server)}>
                                <IconEdit size={16} />
                              </ActionIcon>
                            </Tooltip>
                            <Tooltip label="Delete">
                              <ActionIcon
                                variant="subtle"
                                size="sm"
                                color="red"
                                onClick={() => setDeleteServer(server)}
                              >
                                <IconTrash size={16} />
                              </ActionIcon>
                            </Tooltip>
                          </>
                        ) : (
                          <Tooltip
                            label={
                              editableScope === 'project' && server.scopeIndicator === 'company'
                                ? 'Edit in Company MCP Servers'
                                : undefined
                            }
                            disabled={editableScope !== 'project' || server.scopeIndicator !== 'company'}
                          >
                            <Text fz={12} c="dimmed">
                              {readOnlyLabel(server, editableScope)}
                            </Text>
                          </Tooltip>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </Box>
      )}

      <McpServerFormModal
        opened={formModalOpen}
        onClose={handleFormClose}
        editServer={editServer}
        configItemNames={configItemNames}
        basePath={basePath}
      />
      <DeleteMcpServerModal
        opened={!!deleteServer}
        onClose={() => setDeleteServer(null)}
        server={deleteServer}
        basePath={basePath}
      />
    </Box>
  );
}
