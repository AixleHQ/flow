import { router, usePage } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Divider,
  Group,
  MultiSelect,
  Select,
  SegmentedControl,
  Stack,
  Switch,
  Text,
  Textarea,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { IconCheck, IconPlayerPlay, IconRobot } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import { apiV1TerminalSessionsPath } from 'shared/routes';
import { apiFetch } from 'shared/lib/apiFetch';
import type { AgentType, SharedProps } from 'shared/ui/types';

import classes from './SessionNewForm.module.css';

export interface NamedItem {
  id: number;
  name: string;
}

export interface SessionNewFormProps {
  projectId?: number;
  projects?: NamedItem[];
  agentModels?: AgentModelsEntry[];
  agents?: NamedItem[];
  tools?: NamedItem[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  repositories?: NamedItem[];
  assets?: NamedItem[];
  /** Where to redirect after session creation */
  onCreatedPath: (sessionId: string, projectId: number) => string;
  /** Fallback redirect if no session id returned */
  fallbackPath: string;
  /** Pre-selected project for company-level form */
  preSelectedProjectId?: number | null;
}

const AVAILABLE_AGENTS = [
  { type: 'claude_code', label: 'Claude Code', color: '#D97706' },
  { type: 'cursor_cli', label: 'Cursor CLI', color: '#7C3AED' },
  { type: 'codex', label: 'Codex', color: '#10A37F' },
  { type: 'gemini_cli', label: 'Gemini CLI', color: '#3B82F6' },
];

const AGENT_MANTINE_COLORS: Record<string, string> = {
  claude_code: 'orange',
  cursor_cli: 'violet',
  codex: 'teal',
  gemini_cli: 'blue',
};

interface AgentModel {
  modelId: string;
  displayName: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

export const SessionNewForm = ({
  projectId: fixedProjectId,
  projects,
  agentModels = [],
  agents = [],
  tools = [],
  skills = [],
  mcpServers = [],
  repositories = [],
  assets = [],
  onCreatedPath,
  fallbackPath,
  preSelectedProjectId,
}: SessionNewFormProps) => {
  const { currentUser } = usePage().props as unknown as SharedProps;
  const configuredAgents = currentUser?.configuredAgents ?? [];
  const defaultRuntime = currentUser?.defaultAgentRuntime;
  const initialAgent = defaultRuntime && configuredAgents.includes(defaultRuntime) ? defaultRuntime : '';

  const [projectId, setProjectId] = useState<string | null>(
    fixedProjectId ? String(fixedProjectId) : preSelectedProjectId ? String(preSelectedProjectId) : null,
  );
  const [agentType, setAgentType] = useState<string>(initialAgent);
  const [mode, setMode] = useState('interactive');
  const [initialPrompt, setInitialPrompt] = useState('');
  const [bmadEnabled, setBmadEnabled] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [selectedModel, setSelectedModel] = useState<string | null>(null);
  const [selectedPersona, setSelectedPersona] = useState<string | null>(null);
  const [selectedTools, setSelectedTools] = useState<string[]>([]);
  const [selectedSkills, setSelectedSkills] = useState<string[]>([]);
  const [selectedMcpServers, setSelectedMcpServers] = useState<string[]>([]);
  const [selectedRepos, setSelectedRepos] = useState<string[]>([]);
  const [selectedAssets, setSelectedAssets] = useState<string[]>([]);

  const resolvedProjectId = fixedProjectId ? String(fixedProjectId) : projectId;
  const showProjectSelector = !fixedProjectId && projects && projects.length > 0;

  const modelsMap = useMemo(() => {
    const m: Record<string, AgentModel[]> = {};
    for (const entry of agentModels) m[entry.agentType] = entry.models;
    return m;
  }, [agentModels]);

  const models = useMemo(() => (agentType ? (modelsMap[agentType] ?? []) : []), [agentType, modelsMap]);

  const canSubmit =
    !!agentType &&
    configuredAgents.includes(agentType as AgentType) &&
    (mode === 'interactive' || initialPrompt.trim().length > 0);

  const configCount = useMemo(() => {
    let count = 0;
    if (selectedPersona) count++;
    if (selectedModel) count++;
    count +=
      selectedTools.length +
      selectedSkills.length +
      selectedMcpServers.length +
      selectedRepos.length +
      selectedAssets.length;
    if (bmadEnabled) count++;
    return count;
  }, [
    selectedPersona,
    selectedModel,
    selectedTools,
    selectedSkills,
    selectedMcpServers,
    selectedRepos,
    selectedAssets,
    bmadEnabled,
  ]);

  const handleStart = useCallback(async () => {
    if (!canSubmit) return;
    setLoading(true);
    setError(null);

    try {
      const res = await apiFetch(apiV1TerminalSessionsPath(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          terminalSession: {
            projectId: resolvedProjectId ? Number(resolvedProjectId) : undefined,
            sessionType: 'agent_session',
            agentType: agentType,
            mode,
            initialPrompt: mode === 'non_interactive' ? initialPrompt : null,
            model: selectedModel || undefined,
            configuredAgentId: selectedPersona ? Number(selectedPersona) : undefined,
            toolIds: selectedTools.length > 0 ? selectedTools.map(Number) : undefined,
            skillIds: selectedSkills.length > 0 ? selectedSkills.map(Number) : undefined,
            mcpServerIds: selectedMcpServers.length > 0 ? selectedMcpServers.map(Number) : undefined,
            repositoryIds: selectedRepos.length > 0 ? selectedRepos.map(Number) : undefined,
            assetIds: selectedAssets.length > 0 ? selectedAssets.map(Number) : undefined,
            sessionConfig: bmadEnabled ? { bmadEnabled: true } : {},
          },
        }),
      });

      if (res.ok) {
        const data = await res.json();
        const sessionId = data?.data?.id ?? data?.id;
        if (sessionId) {
          router.visit(onCreatedPath(String(sessionId), resolvedProjectId ? Number(resolvedProjectId) : 0));
        } else {
          router.visit(fallbackPath);
        }
      } else {
        const errData = await res.json().catch(() => null);
        setError(errData?.errors?.[0] ?? errData?.error ?? 'Failed to create session');
      }
    } catch {
      setError('Network error');
    }
    setLoading(false);
  }, [
    canSubmit,
    resolvedProjectId,
    agentType,
    mode,
    initialPrompt,
    bmadEnabled,
    selectedModel,
    selectedPersona,
    selectedTools,
    selectedSkills,
    selectedMcpServers,
    selectedRepos,
    selectedAssets,
    onCreatedPath,
    fallbackPath,
  ]);

  const agentConfig = agentType ? AVAILABLE_AGENTS.find((a) => a.type === agentType) : null;

  return (
    <Card withBorder p="xl">
      <Stack gap="lg">
        {/* ── Project Selector (company-level only) ──── */}
        {showProjectSelector && (
          <Select
            label="Project"
            placeholder="No project (optional)"
            data={projects!.map((p) => ({ value: String(p.id), label: p.name }))}
            value={projectId}
            onChange={setProjectId}
            searchable
            clearable
            size="md"
          />
        )}

        {/* ── Agent Runtime ───────────────────────────── */}
        <Box>
          <Text size="sm" fw={600} mb={8}>
            Agent Runtime
          </Text>
          <div className={classes.agentGrid}>
            {AVAILABLE_AGENTS.map((a) => {
              const isConfigured = configuredAgents.includes(a.type as AgentType);
              const isSelected = agentType === a.type;
              return (
                <Tooltip key={a.type} label="Not configured — complete Onboarding first" disabled={isConfigured}>
                  <UnstyledButton
                    className={`${classes.agentCard} ${isSelected ? classes.agentSelected : ''} ${!isConfigured ? classes.agentDisabled : ''}`}
                    onClick={() => {
                      if (isConfigured) {
                        setAgentType(a.type);
                        setSelectedModel(null);
                      }
                    }}
                  >
                    {isSelected && (
                      <IconCheck
                        size={14}
                        style={{ position: 'absolute', top: 6, right: 6, color: 'var(--mantine-color-blue-5)' }}
                      />
                    )}
                    <div className={classes.agentColorBar} style={{ backgroundColor: a.color }} />
                    <Text size="sm" fw={isSelected ? 600 : 400}>
                      {a.label}
                    </Text>
                    {!isConfigured && (
                      <Badge size="xs" color="yellow" variant="light">
                        Setup needed
                      </Badge>
                    )}
                  </UnstyledButton>
                </Tooltip>
              );
            })}
          </div>
        </Box>

        {/* ── Execution Mode ──────────────────────────── */}
        <Divider label="Execution Mode" labelPosition="center" />

        <SegmentedControl
          value={mode}
          onChange={(val) => {
            setMode(val);
            if (val === 'interactive') setInitialPrompt('');
          }}
          data={[
            { value: 'interactive', label: 'Interactive' },
            { value: 'non_interactive', label: 'Automatic' },
          ]}
          size="md"
        />

        {mode === 'non_interactive' && (
          <Box>
            <Textarea
              label="Initial Prompt"
              placeholder="Describe the task for the agent..."
              value={initialPrompt}
              onChange={(e) => setInitialPrompt(e.currentTarget.value)}
              autosize
              minRows={3}
              maxRows={10}
              required
              error={initialPrompt.trim().length === 0 ? 'Prompt is required for automatic mode' : undefined}
              size="md"
            />
            {initialPrompt.length > 0 && (
              <Text size="xs" c="dimmed" ta="right" mt={2} className={classes.promptCharCount}>
                {initialPrompt.length} chars
              </Text>
            )}
          </Box>
        )}

        {/* ── Configuration ───────────────────────────── */}
        <Divider label="Configuration" labelPosition="center" />

        <Select
          label="Model"
          placeholder="Default (runtime selects)"
          value={selectedModel}
          onChange={setSelectedModel}
          data={models.filter((m) => m.modelId).map((m) => ({ value: m.modelId, label: m.displayName || m.modelId }))}
          searchable
          clearable
          disabled={!agentType}
        />

        {agents.length > 0 && (
          <Select
            label="Agent Persona"
            placeholder="Default (no persona)"
            leftSection={<IconRobot size={16} />}
            data={agents.map((a) => ({ value: String(a.id), label: a.name }))}
            value={selectedPersona}
            onChange={setSelectedPersona}
            searchable
            clearable
          />
        )}

        {tools.length > 0 && (
          <MultiSelect
            label="Tools"
            placeholder="Select tools..."
            data={tools.map((t) => ({ value: String(t.id), label: t.name }))}
            value={selectedTools}
            onChange={setSelectedTools}
            searchable
            clearable
          />
        )}

        {skills.length > 0 && (
          <MultiSelect
            label="Skills"
            placeholder="Select skills..."
            data={skills.map((s) => ({ value: String(s.id), label: s.name }))}
            value={selectedSkills}
            onChange={setSelectedSkills}
            searchable
            clearable
          />
        )}

        {mcpServers.length > 0 && (
          <MultiSelect
            label="MCP Servers"
            placeholder="Select MCP servers..."
            data={mcpServers.map((s) => ({ value: String(s.id), label: s.name }))}
            value={selectedMcpServers}
            onChange={setSelectedMcpServers}
            searchable
            clearable
          />
        )}

        {repositories.length > 0 && (
          <MultiSelect
            label="Repositories"
            placeholder="Select repositories..."
            data={repositories.map((r) => ({ value: String(r.id), label: r.name }))}
            value={selectedRepos}
            onChange={setSelectedRepos}
            searchable
            clearable
          />
        )}

        {assets.length > 0 && (
          <MultiSelect
            label="Assets"
            placeholder="Select assets..."
            data={assets.map((a) => ({ value: String(a.id), label: a.name }))}
            value={selectedAssets}
            onChange={setSelectedAssets}
            searchable
            clearable
          />
        )}

        {/* ── Execution ───────────────────────────────── */}
        <Divider label="Execution" labelPosition="center" />

        <Switch
          label="Use BMAD Method"
          description="Enable BMAD methodology modules for this session"
          checked={bmadEnabled}
          onChange={(e) => setBmadEnabled(e.currentTarget.checked)}
        />

        {/* ── Summary Preview ─────────────────────────── */}
        {(agentType || configCount > 0) && (
          <Card withBorder p="sm" bg="var(--app-bg-elevated)">
            <Stack gap={6}>
              <Text size="xs" fw={600} c="dimmed" tt="uppercase">
                Session Summary
              </Text>
              <div className={classes.summaryRow}>
                {agentConfig && (
                  <Badge color={AGENT_MANTINE_COLORS[agentType] ?? 'gray'} size="sm" variant="filled">
                    {agentConfig.label}
                  </Badge>
                )}
                <Badge size="sm" variant="outline">
                  {mode === 'interactive' ? 'Interactive' : 'Automatic'}
                </Badge>
                {selectedModel && (
                  <Badge size="xs" variant="light">
                    {models.find((m) => m.modelId === selectedModel)?.displayName ?? selectedModel}
                  </Badge>
                )}
                {selectedPersona && (
                  <Badge size="xs" variant="light" leftSection={<IconRobot size={10} />}>
                    {agents.find((a) => String(a.id) === selectedPersona)?.name ?? 'Persona'}
                  </Badge>
                )}
                {selectedTools.length > 0 && (
                  <Badge size="xs" variant="outline" color="yellow">
                    {selectedTools.length} tool{selectedTools.length > 1 ? 's' : ''}
                  </Badge>
                )}
                {selectedSkills.length > 0 && (
                  <Badge size="xs" variant="outline" color="grape">
                    {selectedSkills.length} skill{selectedSkills.length > 1 ? 's' : ''}
                  </Badge>
                )}
                {selectedMcpServers.length > 0 && (
                  <Badge size="xs" variant="outline" color="cyan">
                    {selectedMcpServers.length} MCP
                  </Badge>
                )}
                {selectedRepos.length > 0 && (
                  <Badge size="xs" variant="outline" color="green">
                    {selectedRepos.length} repo{selectedRepos.length > 1 ? 's' : ''}
                  </Badge>
                )}
                {selectedAssets.length > 0 && (
                  <Badge size="xs" variant="outline">
                    {selectedAssets.length} asset{selectedAssets.length > 1 ? 's' : ''}
                  </Badge>
                )}
                {bmadEnabled && (
                  <Badge size="xs" variant="light" color="blue">
                    BMAD
                  </Badge>
                )}
              </div>
            </Stack>
          </Card>
        )}

        {error && (
          <Text c="red" size="sm">
            {error}
          </Text>
        )}

        {/* ── Start Button ────────────────────────────── */}
        <Group>
          <Button
            size="lg"
            leftSection={<IconPlayerPlay size={20} />}
            onClick={handleStart}
            loading={loading}
            disabled={!canSubmit}
            flex={1}
            color={agentType ? (AGENT_MANTINE_COLORS[agentType] ?? undefined) : undefined}
          >
            Start Session
          </Button>
        </Group>
      </Stack>
    </Card>
  );
};
