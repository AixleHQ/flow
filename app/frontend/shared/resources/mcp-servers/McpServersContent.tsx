import {
  ActionIcon,
  Alert,
  Box,
  Button,
  Group,
  SegmentedControl,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import {
  IconAlertTriangle,
  IconEdit,
  IconPhoto,
  IconPlug,
  IconPlugConnected,
  IconPlus,
  IconSearch,
  IconTrash,
} from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';
import { StatusBadge, type StatusTone } from 'shared/ui/StatusBadge';

import { ConnectorCatalogModal } from '../connectors/ConnectorCatalogModal';
import type { Connector } from '../connectors/types';

import { ConnectorUpdateModal } from './ConnectorUpdateModal';
import { DeleteMcpServerModal } from './DeleteMcpServerModal';
import { McpServerFormModal } from './McpServerFormModal';
import { driftedServers } from './serverHealth';
import { ServerHealthIcons } from './ServerHealthIcons';
import { ToolDriftModal } from './ToolDriftModal';
import type { McpServer } from './types';

export type { McpServer } from './types';

// Maps a server's per-user oauth_status to a connection badge (functional labels,
// not colour alone, so the state reads without relying on hue).
const OAUTH_STATUS_BADGE: Record<string, { tone: StatusTone; color: string; label: string }> = {
  active: { tone: 'success', color: 'green', label: 'Connected' },
  expiring: { tone: 'warning', color: 'yellow', label: 'Expiring' },
  pending: { tone: 'neutral', color: 'gray', label: 'Not connected' },
  error: { tone: 'danger', color: 'red', label: 'Reconnect' },
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
  // Defaults to 'all'. It used to default to 'custom', which silently hid every
  // system server on first paint — the list looked empty when it was not.
  const [kindFilter, setKindFilter] = useState('all');
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
      <PageHeader
        title={title}
        subtitle={subtitle}
        actions={
          canExecute && (
            <>
              <Button variant="default" leftSection={<IconPlus size={16} />} onClick={() => setFormModalOpen(true)}>
                Add manually
              </Button>
              {catalogAvailable && (
                <Button leftSection={<IconPlugConnected size={16} />} onClick={() => setCatalogOpen(true)}>
                  Browse connectors
                </Button>
              )}
            </>
          )
        }
      />

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
          aria-label="Filter by kind"
          onChange={setKindFilter}
          data={[
            { label: 'All', value: 'all' },
            { label: 'System', value: 'internal' },
            { label: 'Custom', value: 'custom' },
          ]}
        />
        <ResourceCount>
          {filtered.length} {filtered.length === 1 ? 'connector' : 'connectors'}
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
            icon={<IconPlug size={22} />}
            title={hasFilters ? 'No MCP servers match your filters' : 'No MCP servers configured'}
            description={hasFilters ? undefined : 'An MCP server exposes a set of tools your agents can call.'}
            action={
              !hasFilters &&
              canExecute && (
                <Button variant="outline" onClick={() => setFormModalOpen(true)}>
                  Add one manually
                </Button>
              )
            }
          />
        </Box>
      ) : (
        <ResourceTableShell>
          <Table highlightOnHover layout="fixed">
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                {/* Fixed layout, with every other column pinned to a width — Name is
                    the one column whose content is genuinely unbounded (long server
                    names, long URLs), so it is the one left to claim the remainder
                    and truncate in place instead of squeezing its neighbors. */}
                <ResourceTh>Name</ResourceTh>
                <ResourceTh w={110}>Transport</ResourceTh>
                <ResourceTh w={110}>Scope</ResourceTh>
                <ResourceTh w={120}>Status</ResourceTh>
                <ResourceTh w={140}>Connection</ResourceTh>
                <ResourceTh align="right" w={100}>
                  Actions
                </ResourceTh>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((server) => {
                const canEdit = canExecute && canEditServer(server);
                // A row installed from the catalog gets the shared placeholder tile —
                // the same frame the browse cards use, until real logos are wired in
                // there too. A hand-authored server gets a plain plug glyph instead,
                // since there is no publisher icon to stand in for.
                const fromCatalog = !!server.connectorName;
                return (
                  <Table.Tr key={server.id}>
                    <Table.Td>
                      <Group gap={11} wrap="nowrap" style={{ minWidth: 0 }}>
                        <Box
                          w={30}
                          h={30}
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            backgroundColor: 'var(--app-bg-deep)',
                            borderRadius: 'var(--mantine-radius-sm)',
                            color: 'var(--app-text-secondary)',
                            flexShrink: 0,
                          }}
                        >
                          {fromCatalog ? <IconPhoto size={15} /> : <IconPlug size={15} />}
                        </Box>
                        <Box style={{ minWidth: 0 }}>
                          <Group gap={6} wrap="nowrap">
                            <Text fz={14} fw={500} c="var(--app-text-primary)" truncate style={{ minWidth: 0 }}>
                              {server.name}
                            </Text>
                            <ServerHealthIcons
                              server={server}
                              onReviewDrift={setDriftServer}
                              onReviewUpdate={canEdit ? setUpdateServer : undefined}
                            />
                          </Group>
                          <Text fz={12} c="var(--app-text-tertiary)" truncate maw={300}>
                            {server.url || '—'}
                          </Text>
                        </Box>
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <StatusBadge tone="neutral" size="sm">
                        {server.transport.toUpperCase()}
                      </StatusBadge>
                    </Table.Td>
                    <Table.Td>
                      <StatusBadge tone="neutral" size="sm">
                        {server.scopeIndicator === 'internal' ? 'System' : 'Project'}
                      </StatusBadge>
                    </Table.Td>
                    {/* Status is what the server IS; Connection is what YOU
                        still have to do about it. They used to share one column,
                        so an "Enabled" green sat next to a "Connected" green
                        meaning two different things. */}
                    <Table.Td>
                      <StatusBadge
                        state={server.enabled ? 'enabled' : 'disabled'}
                        size="sm"
                        leftSection={
                          <Box
                            style={{
                              width: 6,
                              height: 6,
                              borderRadius: '50%',
                              background: 'currentColor',
                              flexShrink: 0,
                            }}
                          />
                        }
                      />
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        {server.authType === 'oauth' ? (
                          server.oauthStatus === 'active' ? (
                            <StatusBadge tone={OAUTH_STATUS_BADGE.active.tone} size="sm">
                              {OAUTH_STATUS_BADGE.active.label}
                            </StatusBadge>
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
                          )
                        ) : (
                          <Text size="xs" c="dimmed">
                            —
                          </Text>
                        )}
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} justify="flex-end">
                        {canEdit ? (
                          <>
                            <Tooltip label="Edit">
                              <ActionIcon
                                aria-label="Edit"
                                variant="subtle"
                                size="sm"
                                onClick={() => handleEdit(server)}
                              >
                                <IconEdit size={16} />
                              </ActionIcon>
                            </Tooltip>
                            <Tooltip label="Delete">
                              <ActionIcon
                                aria-label="Edit"
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
        </ResourceTableShell>
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
