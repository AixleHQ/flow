import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  CopyButton,
  Group,
  Menu,
  Select,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconCheck, IconCopy, IconDotsVertical, IconEdit, IconPlus, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { PageHeader } from 'shared/ui/PageHeader';

import { ConfigItemFormModal } from './ConfigItemFormModal';

export interface ConfigItem {
  id: number;
  name: string;
  value: string;
  description: string | null;
  itemType: string;
  scopeType: string;
  scopeIndicator: string;
  createdAt: string;
}

interface ConfigItemsContentProps {
  configItems: ConfigItem[];
  basePath: string;
  title: string;
}

const TYPE_COLORS: Record<string, string> = {
  secret: 'red',
  variable: 'blue',
};

export const ConfigItemsContent = ({ configItems, basePath, title }: ConfigItemsContentProps) => {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<string | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [editItem, setEditItem] = useState<ConfigItem | null>(null);

  const filtered = useMemo(() => {
    let result = configItems;
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((i) => i.name.toLowerCase().includes(q));
    }
    if (typeFilter) {
      result = result.filter((i) => i.itemType === typeFilter);
    }
    return result;
  }, [configItems, search, typeFilter]);

  const handleDelete = (item: ConfigItem) => {
    modals.openConfirmModal({
      title: 'Delete secret',
      children: (
        <Text size="sm">
          Delete <b>{item.name}</b>? Anything injecting it — tools, MCP servers, running workflows — stops resolving it
          immediately. This action cannot be undone.
        </Text>
      ),
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(`${basePath}/${item.id}`, { preserveScroll: true }),
    });
  };

  const handleEdit = (item: ConfigItem) => {
    setEditItem(item);
    setModalOpen(true);
  };

  const handleCloseModal = () => {
    setModalOpen(false);
    setEditItem(null);
  };

  return (
    <Box>
      <PageHeader
        title={title}
        actions={
          <Button
            leftSection={<IconPlus size={16} />}
            onClick={() => {
              setEditItem(null);
              setModalOpen(true);
            }}
          >
            Add secret
          </Button>
        }
      />

      <Group mb="lg">
        <TextInput
          placeholder="Search by name..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        <Select
          placeholder="All Types"
          value={typeFilter}
          onChange={setTypeFilter}
          data={[
            { value: 'secret', label: 'Secret' },
            { value: 'variable', label: 'Variable' },
          ]}
          clearable
          maw={160}
        />
      </Group>

      <Table highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Name</Table.Th>
            <Table.Th>Type</Table.Th>
            <Table.Th>Value</Table.Th>
            <Table.Th>Description</Table.Th>
            <Table.Th w={60} />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {filtered.map((item) => (
            <Table.Tr key={item.id}>
              <Table.Td>
                <Text fw={500} size="sm" ff="monospace">
                  {item.name}
                </Text>
              </Table.Td>
              <Table.Td>
                <Badge color={TYPE_COLORS[item.itemType] ?? 'gray'} size="sm" variant="light">
                  {item.itemType}
                </Badge>
              </Table.Td>
              <Table.Td>
                <Group gap={4} wrap="nowrap">
                  <Text size="sm" ff="monospace" c={item.itemType === 'secret' ? 'dimmed' : undefined}>
                    {item.itemType === 'secret' ? '••••••••' : item.value}
                  </Text>
                  {item.itemType !== 'secret' && (
                    <CopyButton value={item.value}>
                      {({ copied, copy }) => (
                        <Tooltip label={copied ? 'Copied' : 'Copy'}>
                          <ActionIcon variant="subtle" size="xs" color={copied ? 'teal' : 'gray'} onClick={copy}>
                            {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                          </ActionIcon>
                        </Tooltip>
                      )}
                    </CopyButton>
                  )}
                </Group>
              </Table.Td>
              <Table.Td>
                <Text size="sm" c="dimmed" lineClamp={1}>
                  {item.description ?? '—'}
                </Text>
              </Table.Td>
              <Table.Td>
                <Menu position="bottom-end" withArrow>
                  <Menu.Target>
                    <ActionIcon variant="subtle" size="sm">
                      <IconDotsVertical size={16} />
                    </ActionIcon>
                  </Menu.Target>
                  <Menu.Dropdown>
                    <Menu.Item leftSection={<IconEdit size={14} />} onClick={() => handleEdit(item)}>
                      Edit
                    </Menu.Item>
                    <Menu.Item color="red" leftSection={<IconTrash size={14} />} onClick={() => handleDelete(item)}>
                      Delete
                    </Menu.Item>
                  </Menu.Dropdown>
                </Menu>
              </Table.Td>
            </Table.Tr>
          ))}
          {filtered.length === 0 && (
            <Table.Tr>
              <Table.Td colSpan={5}>
                <Text ta="center" c="dimmed" py="xl">
                  No config items found
                </Text>
              </Table.Td>
            </Table.Tr>
          )}
        </Table.Tbody>
      </Table>

      <ConfigItemFormModal opened={modalOpen} onClose={handleCloseModal} item={editItem} basePath={basePath} />
    </Box>
  );
};
