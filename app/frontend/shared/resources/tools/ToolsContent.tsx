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

import { DeleteToolModal } from './DeleteToolModal';
import { ToolFormModal } from './ToolFormModal';

type ToolKind = 'custom' | 'system' | 'internal' | 'workflow';
type ScopeIndicator = 'system' | 'company' | 'project' | 'overrides_company';

interface ToolFile {
  id?: number;
  path: string;
  content: string;
  binary: boolean;
  fileName: string | null;
  fileUrl: string | null;
}

export interface Tool {
  id: number;
  name: string;
  displayName: string;
  description: string | null;
  kind: ToolKind;
  scopeType: string | null;
  scopeId: number | null;
  dockerImage: string | null;
  command: string | null;
  requiredConfigItems: string[];
  inputSchema: Record<string, unknown>;
  enabled: boolean;
  platformTool: boolean;
  scopeIndicator: ScopeIndicator;
  toolFiles: ToolFile[];
  createdAt: string;
  updatedAt: string;
}

interface ToolsContentProps {
  tools: Tool[];
  configItemNames: string[];
  basePath: string;
  title: string;
  subtitle: string;
  editableScopeIndicator?: string;
}

const SCOPE_BADGE: Record<ScopeIndicator, { label: string; color: string }> = {
  system: { label: 'System', color: 'violet' },
  company: { label: 'Company', color: 'gray' },
  project: { label: 'Project', color: 'green' },
  overrides_company: { label: 'Overrides', color: 'yellow' },
};

export function ToolsContent({
  tools,
  configItemNames,
  basePath,
  title,
  subtitle,
  editableScopeIndicator = 'company',
}: ToolsContentProps) {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const [kindFilter, setKindFilter] = useState('custom');
  const [formModalOpen, setFormModalOpen] = useState(false);
  const [editTool, setEditTool] = useState<Tool | null>(null);
  const [deleteTool, setDeleteTool] = useState<Tool | null>(null);

  const filtered = useMemo(() => {
    let result = tools;

    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((t) => t.name.toLowerCase().includes(q) || t.displayName.toLowerCase().includes(q));
    }

    if (kindFilter !== 'all') {
      result = result.filter((t) => t.kind === kindFilter);
    }

    return result;
  }, [tools, search, kindFilter]);

  const canEdit = (tool: Tool) => !tool.platformTool && tool.scopeIndicator === editableScopeIndicator;
  const canDelete = canEdit;

  const handleEdit = (tool: Tool) => {
    setEditTool(tool);
    setFormModalOpen(true);
  };

  const handleFormClose = () => {
    setFormModalOpen(false);
    setEditTool(null);
  };

  const hasFilters = !!search || kindFilter !== 'all';

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
            Add Tool
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
            { label: 'System', value: 'system' },
            { label: 'Custom', value: 'custom' },
          ]}
          size="sm"
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
          <Text fz={48}>🔧</Text>
          <Text fz={16} c="dimmed" mt="sm">
            {hasFilters ? 'No tools match your filters' : 'No tools yet'}
          </Text>
          {!hasFilters && canExecute && (
            <Button variant="outline" mt="sm" onClick={() => setFormModalOpen(true)}>
              Add your first tool
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
                    Tool
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Scope
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Docker Image
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Files
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
              {filtered.map((tool) => {
                const scope = SCOPE_BADGE[tool.scopeIndicator];
                return (
                  <Table.Tr key={tool.id}>
                    <Table.Td>
                      <Box>
                        <Text fz={14} fw={500} c="var(--app-text-primary)">
                          {tool.displayName}
                        </Text>
                        <Text fz={13} fw={500} c="dimmed" ff="JetBrains Mono, monospace">
                          {tool.name}
                        </Text>
                      </Box>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={scope.color} size="sm" variant="light">
                        {scope.label}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {tool.dockerImage ? (
                        <Text fz={12} ff="JetBrains Mono, monospace" c="dimmed">
                          {tool.dockerImage}
                        </Text>
                      ) : (
                        <Badge size="sm" variant="outline" color="gray">
                          Built-in
                        </Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {tool.toolFiles.length > 0 ? (
                        <Badge size="sm" variant="outline" color="gray">
                          {tool.toolFiles.length} files
                        </Badge>
                      ) : (
                        <Text fz={13} c="dimmed">
                          —
                        </Text>
                      )}
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} justify="flex-end">
                        {canExecute && canEdit(tool) && (
                          <Tooltip label="Edit">
                            <ActionIcon variant="subtle" size="sm" onClick={() => handleEdit(tool)}>
                              <IconEdit size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {canExecute && canDelete(tool) && (
                          <Tooltip label="Delete">
                            <ActionIcon variant="subtle" size="sm" color="red" onClick={() => setDeleteTool(tool)}>
                              <IconTrash size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {tool.platformTool && (
                          <Text fz={12} c="dimmed">
                            System tool
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

      <ToolFormModal
        opened={formModalOpen}
        onClose={handleFormClose}
        editTool={editTool}
        configItemNames={configItemNames}
        basePath={basePath}
      />

      <DeleteToolModal
        opened={!!deleteTool}
        onClose={() => setDeleteTool(null)}
        tool={deleteTool}
        basePath={basePath}
      />
    </Box>
  );
}
