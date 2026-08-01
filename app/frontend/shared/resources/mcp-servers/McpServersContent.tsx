import {
  ActionIcon,
  Alert,
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
import { IconAlertTriangle, IconEdit, IconPlugConnected, IconPlus, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';

import { ConnectorCatalogModal } from '../connectors/ConnectorCatalogModal';
import type { Connector } from '../connectors/types';

import { ConnectorUpdateModal } from './ConnectorUpdateModal';
import { DeleteMcpServerModal } from './DeleteMcpServerModal';
import { McpServerFormModal } from './McpServerFormModal';
import { driftedServers } from './serverHealth';
import { ServerHealthIcons } from './ServerHealthIcons';
import { ToolDriftModal } from './ToolDriftModal';

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
  // Connector provenance and tool-baseline health. Null/false on hand-authored
  // servers — nobody promised anything about a server someone typed in.
  connectorName?: string | null;
  connectorVersion?: string | null;
  connectorStatus?: 'active' | 'deprecated' | 'deleted' | null;
  connectorVersionPinned?: boolean;
  toolBaseline?: boolean;
  toolDrift?: { added?: string[]; removed?: string[]; changed?: string[]; detected_at?: string } | null;
  /** Version the catalog now carries, when it differs from the installed one. */
  connectorUpdateVersion?: string | null;
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

interface McpServersContentProps {
  mcpServers: McpServer[];
  configItemNames: string[];
  basePath: string;
  title: string;
  subtitle: string;
  /**
   * Public connector catalog, when this screen offers it. A connector installs
   * as an ordinary MCP server — the catalog is a second way to fill in the same
   * form, not a separate kind of thing — so it lives here rather than in its own
   * section. Omitted on screens that do not offer one.
   */
  connectors?: Connector[];
  connectorQuery?: string;
  connectorsPath?: string;
  catalogSyncedAt?: string | null;
}

// Connectors are project-scoped; the only other kind is a system connector the
// platform provides, which nobody edits. There is no company scope to consider —
// MCPServer refuses any scope but Project.
function canEditServer(server: McpServer): boolean {
  return server.kind === 'custom';
}

function readOnlyLabel(server: McpServer): string {
  return server.internal ? 'System' : 'Read-only';
}

export function McpServersContent({
  mcpServers,
  configItemNames,
  basePath,
  title,
  subtitle,
  connectors,
  connectorQuery = '',
  connectorsPath,
  catalogSyncedAt = null,
}: McpServersContentProps) {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const [kindFilter, setKindFilter] = useState('custom');
  const [formModalOpen, setFormModalOpen] = useState(false);
  const [editServer, setEditServer] = useState<McpServer | null>(null);
  const [deleteServer, setDeleteServer] = useState<McpServer | null>(null);
  const [catalogOpen, setCatalogOpen] = useState(false);
  const [driftServer, setDriftServer] = useState<McpServer | null>(null);
  // Connecting leaves the app entirely, but not immediately: the server runs
  // OAuth discovery (protected-resource metadata → authorization-server metadata
  // → client registration) before it can redirect. That is seconds of a page
  // that looks like it ignored the click. The state is never cleared on purpose
  // — the browser navigating away is what ends it.
  const [connectingId, setConnectingId] = useState<number | null>(null);
  const [updateServer, setUpdateServer] = useState<McpServer | null>(null);
  const catalogAvailable = !!connectorsPath && !!connectors;

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
  // The only condition that interrupts a scan: a server's declared tools moved
  // after it was approved. Everything else stays a quiet per-row glyph.
  const drifted = driftedServers(mcpServers);

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
          <Group gap="sm">
            {catalogAvailable && (
              <Button leftSection={<IconPlugConnected size={16} />} onClick={() => setCatalogOpen(true)}>
                Browse connectors
              </Button>
            )}
            <Button variant="default" leftSection={<IconPlus size={16} />} onClick={() => setFormModalOpen(true)}>
              Add manually
            </Button>
          </Group>
        )}
      </Group>

      {drifted.length > 0 && (
        <Alert
          color="red"
          variant="light"
          icon={<IconAlertTriangle size={16} />}
          mb="lg"
          title={
            drifted.length === 1
              ? `${drifted[0].name} changed the tools it offers`
              : `${drifted.length} servers changed the tools they offer`
          }
        >
          <Group justify="space-between" align="center" wrap="nowrap">
            <Text fz={13}>
              Tool descriptions are instructions the agent reads. Review what changed before the next session runs.
            </Text>
            <Button size="xs" variant="light" color="red" onClick={() => setDriftServer(drifted[0])}>
              Review
            </Button>
          </Group>
        </Alert>
      )}

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
              Add one manually
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
                const canEdit = canExecute && canEditServer(server);
                return (
                  <Table.Tr key={server.id}>
                    <Table.Td>
                      <Group gap={6} wrap="nowrap">
                        <Text fz={14} fw={500} c="var(--app-text-primary)">
                          {server.name}
                        </Text>
                        <ServerHealthIcons
                          server={server}
                          onReviewDrift={setDriftServer}
                          onReviewUpdate={canEdit ? setUpdateServer : undefined}
                        />
                      </Group>
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
                      <Badge color={server.scopeIndicator === 'internal' ? 'violet' : 'teal'} size="sm" variant="light">
                        {server.scopeIndicator === 'internal' ? 'System' : 'Project'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        <Badge color={server.enabled ? 'green' : 'gray'} size="sm">
                          {server.enabled ? 'Enabled' : 'Disabled'}
                        </Badge>
                        {server.authType === 'oauth' &&
                          (server.oauthStatus === 'active' ? (
                            <Badge color={OAUTH_STATUS_BADGE.active.color} variant="light" size="sm">
                              {OAUTH_STATUS_BADGE.active.label}
                            </Badge>
                          ) : (
                            // The state and the fix for it live in the same place. OAuth needs a
                            // top-level navigation (the authorize entry redirects off-site), so this
                            // is window.location rather than an Inertia visit.
                            <Button
                              size="compact-xs"
                              variant="light"
                              color={OAUTH_STATUS_BADGE[server.oauthStatus ?? 'pending'].color}
                              loading={connectingId === server.id}
                              loaderProps={{ type: 'dots' }}
                              disabled={connectingId !== null && connectingId !== server.id}
                              onClick={() => {
                                setConnectingId(server.id);
                                window.location.href = `/oauth/mcp/${server.id}/connect?return_to=${encodeURIComponent(basePath)}`;
                              }}
                            >
                              {server.oauthStatus === 'error' ? 'Reconnect' : 'Connect'}
                            </Button>
                          ))}
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
                          <Text fz={12} c="dimmed">
                            {readOnlyLabel(server)}
                          </Text>
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
      <ToolDriftModal server={driftServer} basePath={basePath} onClose={() => setDriftServer(null)} />
      <ConnectorUpdateModal server={updateServer} basePath={basePath} onClose={() => setUpdateServer(null)} />
      {catalogAvailable && (
        <ConnectorCatalogModal
          opened={catalogOpen}
          onClose={() => setCatalogOpen(false)}
          connectors={connectors ?? []}
          query={connectorQuery}
          pagePath={basePath}
          installPath={connectorsPath ?? ''}
          configItemNames={configItemNames}
          catalogSyncedAt={catalogSyncedAt}
        />
      )}
    </Box>
  );
}
