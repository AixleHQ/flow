import { ActionIcon, Badge, Box, Button, Center, Group, Table, Text, TextInput, Tooltip } from '@mantine/core';
import { IconCopy, IconEdit, IconPlus, IconRobot, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';

import { AgentFormModal } from './AgentFormModal';
import { DeleteAgentModal } from './DeleteAgentModal';

export interface Agent {
  id: number;
  name: string;
  title: string;
  icon: string | null;
  persona: string;
  communicationStyle: string | null;
  principles: string | null;
  source: string;
  scopeType: string;
  scopeId: number;
  scopeIndicator: string;
  createdAt: string;
  updatedAt: string;
}

interface AgentsContentProps {
  agents: Agent[];
  basePath: string;
  title: string;
  subtitle: string;
}

const SCOPE_COLORS: Record<string, string> = {
  company: 'gray',
  project: 'green',
};

export function AgentsContent({ agents, basePath, title, subtitle }: AgentsContentProps) {
  const [search, setSearch] = useState('');
  const [formModalOpen, setFormModalOpen] = useState(false);
  const [editAgent, setEditAgent] = useState<Agent | null>(null);
  const [duplicateAgent, setDuplicateAgent] = useState<Agent | null>(null);
  const [deleteAgent, setDeleteAgent] = useState<Agent | null>(null);
  const { canExecute } = useProjectPermissions();

  const isProjectContext = basePath.includes('projects');

  const filtered = useMemo(() => {
    if (!search.trim()) return agents;
    const q = search.toLowerCase();
    return agents.filter((a) => a.name.toLowerCase().includes(q) || a.title.toLowerCase().includes(q));
  }, [agents, search]);

  const isReadOnly = (agent: Agent) => isProjectContext && agent.scopeIndicator === 'company';

  const handleEdit = (agent: Agent) => {
    setEditAgent(agent);
    setDuplicateAgent(null);
    setFormModalOpen(true);
  };

  const handleDuplicate = (agent: Agent) => {
    setEditAgent(null);
    setDuplicateAgent(agent);
    setFormModalOpen(true);
  };

  const handleFormClose = () => {
    setFormModalOpen(false);
    setEditAgent(null);
    setDuplicateAgent(null);
  };

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle={subtitle}
        actions={
          canExecute && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setFormModalOpen(true)}>
              Add Agent
            </Button>
          )
        }
      />

      <Group gap="md" mb="lg">
        <TextInput
          placeholder="Search by name or title..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        <ResourceCount>
          {agents.length} {agents.length === 1 ? 'agent' : 'agents'}
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
            icon={<IconRobot size={22} />}
            title={search ? 'No agents match your search' : 'No agents yet'}
            description={
              search
                ? undefined
                : 'An agent is a reusable persona — who it is, how it communicates, what principles it follows.'
            }
            action={
              !search &&
              canExecute && (
                <Button variant="outline" onClick={() => setFormModalOpen(true)}>
                  Add your first agent
                </Button>
              )
            }
          />
        </Box>
      ) : (
        <ResourceTableShell>
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <ResourceTh>Agent</ResourceTh>
                <ResourceTh>Persona</ResourceTh>
                {isProjectContext && <ResourceTh>Scope</ResourceTh>}
                <ResourceTh align="right" w={120}>
                  Actions
                </ResourceTh>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((agent) => (
                <Table.Tr key={agent.id}>
                  <Table.Td>
                    <Group gap="sm">
                      <Center
                        w={36}
                        h={36}
                        style={{
                          backgroundColor: 'var(--app-bg-deep)',
                          borderRadius: 'var(--mantine-radius-sm)',
                          fontSize: 24,
                        }}
                      >
                        {agent.icon || '🤖'}
                      </Center>
                      <Box>
                        <Text fz={14} fw={500} c="var(--app-text-primary)">
                          {agent.title}
                        </Text>
                        <Text fz={13} fw={500} c="dimmed" ff="JetBrains Mono, monospace">
                          {agent.name}
                        </Text>
                      </Box>
                    </Group>
                  </Table.Td>
                  <Table.Td>
                    <Tooltip label={agent.persona} position="top" multiline maw={400}>
                      <Text
                        fz={13}
                        c="dimmed"
                        maw={400}
                        style={{
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {agent.persona}
                      </Text>
                    </Tooltip>
                  </Table.Td>
                  {isProjectContext && (
                    <Table.Td>
                      <Badge color={SCOPE_COLORS[agent.scopeIndicator] ?? 'gray'} size="sm" variant="light">
                        {agent.scopeIndicator}
                      </Badge>
                    </Table.Td>
                  )}
                  <Table.Td>
                    {canExecute && (
                      <Group gap={4} justify="flex-end">
                        <Tooltip label="Duplicate">
                          <ActionIcon
                            aria-label="Duplicate"
                            variant="subtle"
                            size="sm"
                            onClick={() => handleDuplicate(agent)}
                          >
                            <IconCopy size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label={isReadOnly(agent) ? 'Company-managed' : 'Edit'}>
                          <ActionIcon
                            aria-label="Edit"
                            variant="subtle"
                            size="sm"
                            disabled={isReadOnly(agent)}
                            onClick={() => handleEdit(agent)}
                          >
                            <IconEdit size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label={isReadOnly(agent) ? 'Company-managed' : 'Delete'}>
                          <ActionIcon
                            aria-label="Delete"
                            variant="subtle"
                            size="sm"
                            color="red"
                            disabled={isReadOnly(agent)}
                            onClick={() => setDeleteAgent(agent)}
                          >
                            <IconTrash size={16} />
                          </ActionIcon>
                        </Tooltip>
                      </Group>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </ResourceTableShell>
      )}

      <AgentFormModal
        opened={formModalOpen}
        onClose={handleFormClose}
        editAgent={editAgent}
        duplicateAgent={duplicateAgent}
        basePath={basePath}
      />

      <DeleteAgentModal
        opened={!!deleteAgent}
        onClose={() => setDeleteAgent(null)}
        agent={deleteAgent}
        basePath={basePath}
      />
    </Box>
  );
}
