import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Alert,
  Badge,
  Box,
  Button,
  Card,
  Group,
  MultiSelect,
  Select,
  Stack,
  Table,
  Text,
  ThemeIcon,
  Tooltip,
} from '@mantine/core';
import { IconAlertCircle, IconExternalLink, IconSparkles, IconWand } from '@tabler/icons-react';
import { formatDistanceToNow } from 'date-fns';
import { useCallback, useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}
interface AssetOption {
  id: number;
  name: string;
}
interface Session {
  id: number;
  state: string;
  agentType: string | null;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
}

interface AgentModel {
  modelId: string;
  displayName: string;
  description?: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface Props {
  project: Project;
  sessions: Session[];
  activeSessionId: number | null;
  configuredAgents: string[];
  defaultAgentRuntime?: string | null;
  assets: AssetOption[];
  agentModels?: AgentModelsEntry[];
}

const AGENT_OPTIONS = [
  { value: 'claude_code', label: 'Claude Code', color: 'orange' },
  { value: 'cursor_cli', label: 'Cursor CLI', color: 'violet' },
  { value: 'codex', label: 'Codex', color: 'teal' },
  { value: 'gemini_cli', label: 'Gemini CLI', color: 'blue' },
  { value: 'grok', label: 'Grok', color: 'gray' },
];

const LandingPage = () => {
  const {
    project,
    sessions,
    activeSessionId,
    configuredAgents,
    defaultAgentRuntime,
    assets,
    agentModels = [],
  } = usePage<{ props: Props }>().props as unknown as Props;
  const { canExecute } = useProjectPermissions();

  // The member's default agent for this company wins; the first configured
  // credential is only a fallback (its order is whatever Postgres returns).
  const [runtime, setRuntime] = useState<string | null>(
    defaultAgentRuntime && configuredAgents.includes(defaultAgentRuntime)
      ? defaultAgentRuntime
      : (configuredAgents[0] ?? null),
  );
  const [selectedModel, setSelectedModel] = useState<string | null>(null);
  const [selectedAssets, setSelectedAssets] = useState<string[]>([]);
  const [starting, setStarting] = useState(false);

  const hasActive = activeSessionId !== null;

  const modelsMap = useMemo(() => {
    const m: Record<string, AgentModel[]> = {};
    for (const entry of agentModels) m[entry.agentType] = entry.models;
    return m;
  }, [agentModels]);

  const models = useMemo(() => (runtime ? (modelsMap[runtime] ?? []) : []), [runtime, modelsMap]);

  const handleStart = useCallback(() => {
    if (!runtime) return;
    setStarting(true);
    router.post(
      `/company/projects/${project.id}/aixle_builder/start`,
      {
        agentRuntime: runtime,
        preferredModel: selectedModel || undefined,
        inputAssetIds: selectedAssets.map(Number),
      },
      {
        onFinish: () => setStarting(false),
      },
    );
  }, [runtime, selectedModel, selectedAssets, project.id]);

  const handleContinue = useCallback(() => {
    if (activeSessionId) {
      router.visit(`/company/projects/${project.id}/aixle_builder/${activeSessionId}/session`);
    }
  }, [activeSessionId, project.id]);

  const assetData = assets.map((a) => ({ value: String(a.id), label: a.name }));

  const modelData = models.map((m) => ({
    value: m.modelId,
    label: m.displayName,
  }));

  return (
    <>
      <Head title={`Aixle Builder — ${project.name}`} />
      <Card withBorder p="xl" mb="lg" style={{ textAlign: 'center' }}>
        <Stack align="center" gap="sm">
          <ThemeIcon size="xl" radius="xl" variant="light" color="blue">
            <IconWand size={28} />
          </ThemeIcon>
          <Text size="xl" fw={700}>
            Aixle Builder
          </Text>
          <Text size="sm" c="dimmed" maw={480}>
            AI-powered workflow automation builder. Describe what you want to automate and the AI will create workflows,
            steps, tools, and board configurations for you.
          </Text>

          <Stack gap="sm" mt="md" w="100%" maw={420}>
            {configuredAgents.length === 0 && (
              <Alert icon={<IconAlertCircle size={16} />} color="orange" variant="light">
                No agent runtimes configured. Go to{' '}
                <Text component="a" href="/profile" size="sm" c="var(--app-warning-fg)" td="underline" span>
                  Profile
                </Text>{' '}
                to set up an agent credential.
              </Alert>
            )}
            <Group gap="sm" grow>
              <Select
                label="Agent Runtime"
                data={AGENT_OPTIONS.map((a) => ({
                  value: a.value,
                  label: a.label,
                  disabled: !configuredAgents.includes(a.value),
                }))}
                value={runtime}
                onChange={setRuntime}
                size="sm"
              />
              {models.length > 0 && (
                <Select
                  label="Model (optional)"
                  data={modelData}
                  value={selectedModel}
                  onChange={setSelectedModel}
                  placeholder="Default"
                  clearable
                  size="sm"
                  disabled={models.length === 0}
                />
              )}
            </Group>
            {assets.length > 0 && (
              <MultiSelect
                label="Project Assets"
                data={assetData}
                value={selectedAssets}
                onChange={setSelectedAssets}
                placeholder="Select assets to include..."
                searchable
                size="sm"
              />
            )}
          </Stack>

          {canExecute && (
            <Group mt="md">
              {hasActive ? (
                <Button size="md" leftSection={<IconSparkles size={16} />} onClick={handleContinue}>
                  Continue Active Session
                </Button>
              ) : (
                <Tooltip label="No agent runtime configured" disabled={!!runtime}>
                  <Button
                    size="md"
                    leftSection={<IconSparkles size={16} />}
                    onClick={handleStart}
                    loading={starting}
                    disabled={!runtime}
                  >
                    Start Builder
                  </Button>
                </Tooltip>
              )}
            </Group>
          )}
        </Stack>
      </Card>

      {sessions.length > 0 && (
        <Box>
          <Text size="lg" fw={600} mb="sm">
            Previous Sessions
          </Text>
          <Table striped highlightOnHover verticalSpacing={6} fz="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Session</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Runtime</Table.Th>
                <Table.Th>Started</Table.Th>
                <Table.Th w={40} />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {sessions.map((s) => {
                const agent = AGENT_OPTIONS.find((a) => a.value === s.agentType);
                return (
                  <Table.Tr key={s.id}>
                    <Table.Td>
                      <Text size="xs" ff="monospace" c="dimmed">
                        #{s.id}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <StatusBadge state={s.state} size="sm" />
                    </Table.Td>
                    <Table.Td>
                      {agent && (
                        <Badge color={agent.color} size="sm" variant="filled">
                          {agent.label}
                        </Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label={s.startedAt ? new Date(s.startedAt).toLocaleString() : s.createdAt}>
                        <Text size="xs" c="dimmed">
                          {formatDistanceToNow(new Date(s.startedAt ?? s.createdAt), { addSuffix: true })}
                        </Text>
                      </Tooltip>
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label="Open session">
                        <ActionIcon
                          aria-label="Open session"
                          variant="subtle"
                          size="sm"
                          onClick={() => router.visit(`/company/projects/${project.id}/aixle_builder/${s.id}/session`)}
                        >
                          <IconExternalLink size={14} />
                        </ActionIcon>
                      </Tooltip>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </Box>
      )}
    </>
  );
};

setPageLayout(LandingPage, persistentProjectLayout);

export default LandingPage;
