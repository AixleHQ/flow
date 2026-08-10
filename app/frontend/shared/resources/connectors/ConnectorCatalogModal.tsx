import { router } from '@inertiajs/react';
import {
  Avatar,
  Badge,
  Button,
  Card,
  Center,
  CloseButton,
  Group,
  Loader,
  Modal,
  SimpleGrid,
  Text,
  TextInput,
} from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconPlugConnected, IconSearch } from '@tabler/icons-react';
import { useState, type FC } from 'react';

import { ConnectorInstallModal } from './ConnectorInstallModal';
import type { Connector } from './types';

interface ConnectorCatalogModalProps {
  opened: boolean;
  onClose: () => void;
  connectors: Connector[];
  query: string;
  /** Page path the catalog props live on — searching partial-reloads it. */
  pagePath: string;
  /** Where an install POSTs to. */
  installPath: string;
  catalogSyncedAt: string | null;
  configItemNames: string[];
}

// Initials from the product name, drawn locally. Every icon URL is derived from
// a publisher's own host, so any of them can fail — a missing logo must never
// leave a hole in the grid.
const monogram = (connector: Connector): string => {
  const source = connector.title || connector.name.split('/').pop() || connector.name;
  const words = source
    .replace(/[^\p{L}\p{N} ]/gu, ' ')
    .trim()
    .split(/\s+/);
  if (words.length === 0) return '?';
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
};

const transportSummary = (connector: Connector): string => {
  const supported = connector.targets.filter((t) => t.supported);
  if (supported.length === 0) return 'unavailable';
  return Array.from(
    new Set(supported.map((t) => (t.kind === 'remote' ? 'hosted' : (t.registryType ?? 'package')))),
  ).join(', ');
};

// Browsing the public connector catalog: the same MCP servers the manual form
// builds, pre-described by the registry so the fields can be generated instead
// of typed. Lives on the MCP servers page rather than in its own section —
// a connector IS an MCP server, just one somebody else already documented.
export const ConnectorCatalogModal: FC<ConnectorCatalogModalProps> = ({
  opened,
  onClose,
  connectors,
  query,
  pagePath,
  installPath,
  catalogSyncedAt,
  configItemNames,
}) => {
  const [search, setSearch] = useState(query);
  const [installing, setInstalling] = useState<Connector | null>(null);
  // The results come from a server round trip, so the field has to say that
  // something is happening; a debounced search with no feedback reads as broken.
  const [searching, setSearching] = useState(false);

  // Search runs server-side against the local mirror. The registry API itself
  // can only match server-name substrings, so neither client-side filtering nor
  // a live upstream query would find "issue tracker".
  const runSearch = useDebouncedCallback((value: string) => {
    router.get(
      pagePath,
      { connector_q: value },
      {
        preserveState: true,
        replace: true,
        only: ['connectors', 'connector_query'],
        onFinish: () => setSearching(false),
      },
    );
  }, 300);

  const changeSearch = (value: string) => {
    setSearch(value);
    setSearching(true);
    runSearch(value);
  };

  return (
    <>
      <Modal opened={opened} onClose={onClose} title="Connectors" size="90%">
        <TextInput
          placeholder="Search connectors — try 'issue tracker' or 'database'"
          aria-label="Search connectors"
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => changeSearch(e.currentTarget.value)}
          rightSection={
            searching ? (
              <Loader size="xs" />
            ) : (
              search && <CloseButton size="sm" aria-label="Clear search" onClick={() => changeSearch('')} />
            )
          }
          mb="md"
        />

        {/* Deliberately not "most installed": ordering does use install counts,
            but a cold catalog falls back to a curated list, and a label that
            claims measurement it does not always have is a small lie. */}
        {connectors.length > 0 && !query && (
          <Text fz={12} fw={600} c="dimmed" tt="uppercase" mb="xs" style={{ letterSpacing: 0.5 }}>
            Suggested connectors
          </Text>
        )}

        {connectors.length === 0 ? (
          <Center mih={200} style={{ flexDirection: 'column' }}>
            <IconPlugConnected size={36} color="var(--app-text-secondary)" />
            <Text fz={15} c="dimmed" mt="sm">
              {query ? `No connectors match “${query}”` : 'The catalog is empty'}
            </Text>
            {query ? (
              <Button variant="subtle" size="xs" mt="sm" onClick={() => changeSearch('')}>
                Show suggested connectors
              </Button>
            ) : (
              <Text fz={13} c="dimmed" mt={4} ta="center">
                It fills on the next registry sync. You can always add an MCP server by hand.
              </Text>
            )}
          </Center>
        ) : (
          <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="sm">
            {connectors.map((connector) => (
              <Card
                key={connector.id}
                padding="md"
                radius="md"
                withBorder
                style={{
                  borderColor: 'var(--app-border-default)',
                  backgroundColor: 'var(--app-bg-paper)',
                  display: 'flex',
                  flexDirection: 'column',
                  minHeight: 150,
                }}
              >
                <Group justify="space-between" align="flex-start" wrap="nowrap" mb={6}>
                  <Group gap={8} wrap="nowrap" style={{ minWidth: 0, flex: 1 }}>
                    <Avatar src={connector.iconUrl} alt="" size={26} radius="sm" color="gray">
                      {monogram(connector)}
                    </Avatar>
                    <Text fz={14} fw={600} c="var(--app-text-primary)" truncate style={{ minWidth: 0 }}>
                      {connector.pickerName}
                    </Text>
                  </Group>
                  <Group gap={4} style={{ flexShrink: 0 }}>
                    {connector.status === 'deprecated' && (
                      <Badge size="xs" variant="light" color="yellow">
                        deprecated
                      </Badge>
                    )}
                    <Badge size="xs" variant="light" color={connector.installable ? 'teal' : 'gray'}>
                      {transportSummary(connector)}
                    </Badge>
                  </Group>
                </Group>

                <Group gap={6} wrap="nowrap" mb={4}>
                  {connector.vendorPublished && (
                    <Badge size="xs" variant="light" color="blue" title="Publisher proved they own this domain">
                      vendor
                    </Badge>
                  )}
                  {/* Many entries have no human title, in which case the card
                      heading already IS the registry name — printing it twice
                      just wastes the row. */}
                  {connector.pickerName !== connector.name && (
                    <Text fz={11} c="dimmed" ff="JetBrains Mono, monospace" truncate>
                      {connector.name}
                    </Text>
                  )}
                </Group>

                <Text fz={12} c="dimmed" lineClamp={3} style={{ flex: 1 }}>
                  {connector.description || 'No description available'}
                </Text>

                <Group justify="space-between" mt="sm">
                  <Text fz={11} c="dimmed">
                    {connector.version ? `v${connector.version}` : ''}
                  </Text>
                  <Button
                    size="xs"
                    variant="light"
                    disabled={!connector.installable}
                    onClick={() => setInstalling(connector)}
                  >
                    {connector.installable ? 'Install' : 'Unavailable'}
                  </Button>
                </Group>
              </Card>
            ))}
          </SimpleGrid>
        )}

        {catalogSyncedAt && (
          <Text fz={11} c="dimmed" mt="md">
            Catalog last synced {new Date(catalogSyncedAt).toLocaleString()}
          </Text>
        )}
      </Modal>

      <ConnectorInstallModal
        connector={installing}
        basePath={installPath}
        configItemNames={configItemNames}
        onClose={() => {
          setInstalling(null);
          onClose();
        }}
      />
    </>
  );
};
