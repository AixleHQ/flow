import { router, usePage } from '@inertiajs/react';
import { Badge, Box, Button, Card, Group, MultiSelect, Select, Stack, Switch, Text, Textarea } from '@mantine/core';
import { IconAdjustments, IconPlayerPlay, IconRobot, IconSparkles } from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import type { ConfigItemPicker } from '@/types/generated';

import { apiFetch } from 'shared/lib/apiFetch';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { apiV1TerminalSessionsPath } from 'shared/routes';
import { AGENT_BRAND_COLORS } from 'shared/theme/vendorColors';
import { FormSection, ModeCards, RuntimeTiles } from 'shared/ui/sessions';
import type { AgentType, SharedProps } from 'shared/ui/types';

import classes from './SessionNewForm.module.css';

/** Cost context for the commit moment — see sessions_controller#session_cost_hint. */
export interface SessionCostHint {
  avgCostCentsByRuntime: Record<string, number>;
  monthToDateCents: number;
}

export interface NamedItem {
  id: number;
  name: string;
}

/** Picker payload for a project config item — names and types only, never a value. */
export type ConfigItemOption = ConfigItemPicker;

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
  configItems?: ConfigItemOption[];
  /** Where to redirect after session creation */
  onCreatedPath: (sessionId: string, projectId: number) => string;
  /** Fallback redirect if no session id returned */
  fallbackPath: string;
  /** Pre-selected project for company-level form */
  preSelectedProjectId?: number | null;
  /** Typical spend for this runtime + what has already gone this month. */
  costHint?: SessionCostHint;
  /**
   * `page` keeps the bordered card; `drawer` drops it and pins Start to a
   * footer, so the 460px side panel matches the Run Workflow drawer exactly.
   */
  layout?: 'page' | 'drawer';
}

const AVAILABLE_AGENTS = [
  { type: 'claude_code', label: 'Claude Code', color: AGENT_BRAND_COLORS.claude_code },
  { type: 'cursor_cli', label: 'Cursor CLI', color: AGENT_BRAND_COLORS.cursor_cli },
  { type: 'codex', label: 'Codex', color: AGENT_BRAND_COLORS.codex },
  { type: 'gemini_cli', label: 'Gemini CLI', color: AGENT_BRAND_COLORS.gemini_cli },
  { type: 'antigravity_cli', label: 'Antigravity CLI', color: AGENT_BRAND_COLORS.antigravity_cli },
  { type: 'grok', label: 'Grok', color: AGENT_BRAND_COLORS.grok },
];

const AGENT_MANTINE_COLORS: Record<string, string> = {
  claude_code: 'orange',
  cursor_cli: 'violet',
  codex: 'teal',
  gemini_cli: 'blue',
  antigravity_cli: 'indigo',
  grok: 'gray',
};

const formatCents = (cents: number): string => `$${(cents / 100).toFixed(2)}`;

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
  configItems = [],
  onCreatedPath,
  fallbackPath,
  preSelectedProjectId,
  costHint,
  layout = 'page',
}: SessionNewFormProps) => {
  const { currentUser } = usePage().props as unknown as SharedProps;
  const { canExecute } = useProjectPermissions();
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
  // OAuth session-start preflight (§4.6): MCP servers the user must connect before this
  // session can launch. Populated from the API's 422 { reauth_required } response.
  const [reauthRequired, setReauthRequired] = useState<{ name: string; connectUrl: string }[]>([]);

  const [selectedModel, setSelectedModel] = useState<string | null>(null);
  const [selectedPersona, setSelectedPersona] = useState<string | null>(null);
  const [selectedTools, setSelectedTools] = useState<string[]>([]);
  const [selectedSkills, setSelectedSkills] = useState<string[]>([]);
  const [selectedMcpServers, setSelectedMcpServers] = useState<string[]>([]);
  const [selectedRepos, setSelectedRepos] = useState<string[]>([]);
  const [selectedAssets, setSelectedAssets] = useState<string[]>([]);
  const [selectedConfigItems, setSelectedConfigItems] = useState<string[]>([]);

  const resolvedProjectId = fixedProjectId ? String(fixedProjectId) : projectId;
  const showProjectSelector = !fixedProjectId && projects && projects.length > 0;

  const modelsMap = useMemo(() => {
    const m: Record<string, AgentModel[]> = {};
    for (const entry of agentModels) m[entry.agentType] = entry.models;
    return m;
  }, [agentModels]);

  const models = useMemo(() => (agentType ? (modelsMap[agentType] ?? []) : []), [agentType, modelsMap]);

  const avgCostCents = agentType ? (costHint?.avgCostCentsByRuntime?.[agentType] ?? null) : null;

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
      selectedAssets.length +
      selectedConfigItems.length;
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
    selectedConfigItems,
    bmadEnabled,
  ]);

  const handleStart = useCallback(async () => {
    if (!canSubmit) return;
    setLoading(true);
    setError(null);
    setReauthRequired([]);

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
            requestedModel: selectedModel || undefined,
            configuredAgentId: selectedPersona ? Number(selectedPersona) : undefined,
            toolIds: selectedTools.length > 0 ? selectedTools.map(Number) : undefined,
            skillIds: selectedSkills.length > 0 ? selectedSkills.map(Number) : undefined,
            mcpServerIds: selectedMcpServers.length > 0 ? selectedMcpServers.map(Number) : undefined,
            repositoryIds: selectedRepos.length > 0 ? selectedRepos.map(Number) : undefined,
            inputAssetIds: selectedAssets.length > 0 ? selectedAssets.map(Number) : undefined,
            configItemIds: selectedConfigItems.length > 0 ? selectedConfigItems.map(Number) : undefined,
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
        const reauth = errData?.reauth_required;
        if (res.status === 422 && Array.isArray(reauth) && reauth.length > 0) {
          // Preflight blocked the launch: surface a Connect CTA per server instead of a raw error.
          setReauthRequired(
            reauth.map((r: { name: string; connect_url: string }) => ({ name: r.name, connectUrl: r.connect_url })),
          );
        } else {
          setError(errData?.errors?.[0] ?? errData?.error ?? 'Failed to create session');
        }
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
    selectedConfigItems,
    onCreatedPath,
    fallbackPath,
  ]);

  const agentConfig = agentType ? AVAILABLE_AGENTS.find((a) => a.type === agentType) : null;
  const isDrawer = layout === 'drawer';

  const startButton = canExecute ? (
    <Button
      size="md"
      leftSection={<IconPlayerPlay size={18} />}
      onClick={handleStart}
      loading={loading}
      disabled={!canSubmit}
      fullWidth
      /* No `color` override: the primary action keeps the brand accent
         whichever runtime is selected. Coloring it per vendor meant the
         most expensive button in the app changed color as you picked,
         and its default (Mantine orange) measured 2.57:1. Runtime
         identity stays on the runtime picker above. */
    >
      Start Session
    </Button>
  ) : null;

  const body = (
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

      {/* ── Agent runtime → Execution mode → Configuration: the same order,
             with the same controls, as the Run Workflow drawer. ─────────── */}
      <Box>
        <FormSection icon={<IconRobot size={14} />} first>
          Agent runtime
        </FormSection>
        <RuntimeTiles
          value={agentType || null}
          configured={configuredAgents}
          onChange={(type) => {
            setAgentType(type);
            setSelectedModel(null);
          }}
        />
      </Box>

      <Box>
        <FormSection icon={<IconPlayerPlay size={14} />}>Execution mode</FormSection>
        <ModeCards
          aria-label="Execution mode"
          value={mode}
          onChange={(val) => {
            setMode(val);
            if (val === 'interactive') setInitialPrompt('');
          }}
          options={[
            { value: 'interactive', title: 'Interactive', description: 'You steer each turn' },
            { value: 'non_interactive', title: 'Automatic', description: 'Runs on its own' },
          ]}
        />
      </Box>

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
      <FormSection icon={<IconAdjustments size={14} />}>Configuration</FormSection>

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

      {configItems.length > 0 && (
        <MultiSelect
          label="Secrets & Variables"
          description="The agent can read these with the get_config_item tool instead of asking you to paste a credential."
          placeholder="Select secrets and variables..."
          aria-label="Secrets and variables"
          data={configItems.map((c) => ({
            value: String(c.id),
            label: c.itemType === 'secret' ? `${c.name} (secret)` : c.name,
          }))}
          value={selectedConfigItems}
          onChange={setSelectedConfigItems}
          searchable
          clearable
        />
      )}

      {/* ── Execution ───────────────────────────────── */}
      <FormSection icon={<IconSparkles size={14} />}>Execution</FormSection>

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
            {/* The one number that belongs on this screen. Everything else in
                  the product reports cost after the fact. */}
            {costHint && (
              <Text size="xs" c="var(--app-text-secondary)">
                {avgCostCents != null ? (
                  <>
                    Typically <strong>{formatCents(avgCostCents)}</strong> per session on this runtime
                    {' · '}
                  </>
                ) : null}
                <strong>{formatCents(costHint.monthToDateCents)}</strong> spent by you in this project this month
              </Text>
            )}
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
        <Text c="var(--app-danger-fg)" size="sm">
          {error}
        </Text>
      )}

      {/* ── OAuth preflight: Connect CTA (§4.6) ─────── */}
      {reauthRequired.length > 0 && (
        <Card withBorder padding="sm" styles={{ root: { borderColor: 'var(--mantine-color-yellow-5)' } }}>
          <Text fw={600} size="sm">
            Connect required before launching
          </Text>
          <Text c="dimmed" size="xs" mb="xs">
            These MCP servers need you to connect your account first.
          </Text>
          <Group gap="xs">
            {reauthRequired.map((r) => (
              <Button
                key={r.connectUrl}
                variant="light"
                color="yellow"
                onClick={() => {
                  // A top-level browser navigation, not an Inertia visit. Some connect
                  // URLs already carry a query (the cloud CTA points at the profile page
                  // with the modal to open), so pick the separator rather than always
                  // appending "?".
                  const separator = r.connectUrl.includes('?') ? '&' : '?';
                  window.location.href = `${r.connectUrl}${separator}return_to=${encodeURIComponent(
                    window.location.pathname,
                  )}`;
                }}
              >
                Connect {r.name}
              </Button>
            ))}
          </Group>
        </Card>
      )}

      {/* On a page the primary action closes the form; in a drawer it lives
            in the pinned footer instead, where the design puts it. */}
      {!isDrawer && startButton}
    </Stack>
  );

  if (isDrawer) {
    return (
      <div className={classes.drawerLayout}>
        <div className={classes.drawerBody}>{body}</div>
        <div className={classes.drawerFooter}>{startButton}</div>
      </div>
    );
  }

  return (
    <Card withBorder p="xl">
      {body}
    </Card>
  );
};
