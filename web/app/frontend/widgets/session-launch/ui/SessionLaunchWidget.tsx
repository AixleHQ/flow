import {
  Autocomplete,
  Box,
  Button,
  Chip,
  CircularProgress,
  Divider,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Tooltip,
  Typography,
} from '@mui/material';
import { enqueueSnackbar } from 'notistack';
import { useCallback, useEffect, useState } from 'react';

import type { McpServer } from 'entities/mcp-server';
import { useGetMcpServersQuery, useGetProjectMcpServersQuery } from 'entities/mcp-server';
import type { AgentType, ITerminalSession, SessionMode } from 'entities/terminal-session';
import { useGetCurrentUserQuery } from 'entities/user';
import type { Agent } from 'features/agents-management';
import { useGetCompanyAgentsQuery, useGetProjectAgentsQuery } from 'features/agents-management';
import type { Skill } from 'features/skills-management';
import { useGetCompanySkillsQuery, useGetProjectSkillsQuery } from 'features/skills-management';
import type { Tool } from 'features/tools-management';
import { useGetCompanyToolsQuery, useGetProjectToolsQuery } from 'features/tools-management';
import { useCreateTerminalSessionMutation, useCancelSessionMutation, useGetTerminalSessionQuery } from 'shared/api';
import { useTerminalSessionChannel } from 'shared/lib';
import { TerminalSessionWidget } from 'widgets/terminal-session';

export interface SessionLaunchWidgetProps {
  projectId?: number;
  /** Pre-load an existing session by ID (from URL param) */
  initialSessionId?: number;
  /** Called when active session changes — parent can update URL */
  onSessionChange?: (sessionId: number | null) => void;
}

const AGENT_TYPES: { type: AgentType; label: string; color: string }[] = [
  { type: 'claude_code', label: 'Claude Code', color: '#D97706' },
  { type: 'cursor_cli', label: 'Cursor CLI', color: '#7C3AED' },
  { type: 'codex', label: 'Codex', color: '#059669' },
  { type: 'gemini_cli', label: 'Gemini CLI', color: '#2563EB' },
];

export const SessionLaunchWidget: React.FC<SessionLaunchWidgetProps> = ({
  projectId,
  initialSessionId,
  onSessionChange,
}) => {
  const { data: currentUser } = useGetCurrentUserQuery();
  const configuredAgents = currentUser?.configuredAgents ?? [];

  // Form state
  const [selectedAgent, setSelectedAgent] = useState<AgentType | null>(null);
  const [selectedPersona, setSelectedPersona] = useState<Agent | null>(null);
  const [selectedTools, setSelectedTools] = useState<Tool[]>([]);
  const [selectedSkills, setSelectedSkills] = useState<Skill[]>([]);
  const [selectedMcpServers, setSelectedMcpServers] = useState<McpServer[]>([]);
  const [mode, setMode] = useState<SessionMode>('interactive');
  const [initialPrompt, setInitialPrompt] = useState('');

  // Session state — when set, show TerminalSessionWidget instead of form
  const [activeSessionId, setActiveSessionId] = useState<number | null>(initialSessionId ?? null);
  const [activeSession, setActiveSession] = useState<ITerminalSession | null>(null);

  // Fetch session data — only for initial load from URL
  const {
    data: fetchedSession,
    isLoading: isLoadingExisting,
    isError: isSessionError,
  } = useGetTerminalSessionQuery(activeSessionId!, {
    skip: !activeSessionId || activeSession !== null,
  });

  // Sync fetched session data into local state (initial load only)
  useEffect(() => {
    if (fetchedSession?.data && !activeSession) {
      setActiveSession(fetchedSession.data);
      if (!selectedAgent) {
        setSelectedAgent(fetchedSession.data.agentType);
      }
    }
  }, [fetchedSession, activeSession, selectedAgent]);

  // ActionCable subscription for real-time session updates
  const handleChannelUpdate = useCallback(
    (updated: ITerminalSession) => {
      setActiveSession(updated);
      if (!selectedAgent && updated.agentType) {
        setSelectedAgent(updated.agentType);
      }
      if (updated.state === 'stopped' || updated.state === 'collected') {
        enqueueSnackbar('Session completed', { variant: 'info' });
      }
    },
    [selectedAgent],
  );

  useTerminalSessionChannel({
    sessionId: activeSessionId,
    onUpdate: handleChannelUpdate,
  });

  // Resource queries — use skip to avoid conditional hooks
  const projectAgents = useGetProjectAgentsQuery(projectId!, { skip: !projectId });
  const companyAgents = useGetCompanyAgentsQuery(undefined, { skip: !!projectId });
  const agents: Agent[] = (projectId ? projectAgents.data : companyAgents.data) ?? [];

  const projectTools = useGetProjectToolsQuery(projectId!, { skip: !projectId });
  const companyTools = useGetCompanyToolsQuery(undefined, { skip: !!projectId });
  const tools: Tool[] = (projectId ? projectTools.data : companyTools.data) ?? [];

  const projectSkills = useGetProjectSkillsQuery(projectId!, { skip: !projectId });
  const companySkills = useGetCompanySkillsQuery(undefined, { skip: !!projectId });
  const skills: Skill[] = (projectId ? projectSkills.data : companySkills.data) ?? [];

  const projectMcp = useGetProjectMcpServersQuery(String(projectId), { skip: !projectId });
  const companyMcp = useGetMcpServersQuery(undefined, { skip: !!projectId });
  const mcpServers: McpServer[] = (projectId ? projectMcp.data : companyMcp.data) ?? [];

  const [createSession, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [cancelSession] = useCancelSessionMutation();
  const [isStopping, setIsStopping] = useState(false);

  const canSubmit = selectedAgent !== null && (mode === 'interactive' || initialPrompt.trim().length > 0);

  const handleAgentChange = (_: React.MouseEvent<HTMLElement>, newAgent: AgentType | null) => {
    if (newAgent) {
      setSelectedAgent(newAgent);
    }
  };

  const handleModeChange = (_: React.MouseEvent<HTMLElement>, newMode: SessionMode | null) => {
    if (newMode) {
      setMode(newMode);
      if (newMode === 'interactive') {
        setInitialPrompt('');
      }
    }
  };

  const handleStart = async () => {
    if (!selectedAgent) return;

    // Build session_config — only include non-default values
    const hasCustomConfig =
      selectedPersona ||
      selectedTools.length > 0 ||
      selectedSkills.length > 0 ||
      selectedMcpServers.length > 0 ||
      mode === 'non_interactive';

    try {
      const result = await createSession({
        terminalSession: {
          sessionType: 'agent_session',
          agentType: selectedAgent,
          projectId: projectId,
          ...(hasCustomConfig
            ? {
                sessionConfig: {
                  ...(selectedPersona ? { agentId: selectedPersona.id } : {}),
                  ...(selectedTools.length > 0 ? { toolIds: selectedTools.map((t) => t.id) } : {}),
                  ...(selectedSkills.length > 0 ? { skillIds: selectedSkills.map((s) => s.id) } : {}),
                  ...(selectedMcpServers.length > 0 ? { mcpServerIds: selectedMcpServers.map((m) => m.id) } : {}),
                  mode: mode,
                  ...(mode === 'non_interactive' ? { initialPrompt } : {}),
                },
              }
            : {}),
        },
      }).unwrap();

      const agentLabel = AGENT_TYPES.find((a) => a.type === selectedAgent)?.label ?? selectedAgent;
      enqueueSnackbar(`${agentLabel} session started`, { variant: 'success' });

      setActiveSessionId(result.data.id);
      setActiveSession(result.data);
      onSessionChange?.(result.data.id);
    } catch (error) {
      const message = (error as { data?: { error?: string } })?.data?.error || 'Failed to start session';
      enqueueSnackbar(message, { variant: 'error' });
      console.error('Session creation failed:', error);
    }
  };

  const handleStop = async () => {
    if (!activeSessionId) return;
    setIsStopping(true);
    try {
      await cancelSession(activeSessionId).unwrap();
      enqueueSnackbar('Session stopped', { variant: 'info' });
    } catch {
      enqueueSnackbar('Failed to stop session', { variant: 'error' });
      setIsStopping(false);
    }
  };

  const handleNewSession = () => {
    setActiveSessionId(null);
    setActiveSession(null);
    setIsStopping(false);
    onSessionChange?.(null);
  };

  // ── Loading existing session ─────────────────────────────────────
  if (activeSessionId && isLoadingExisting && !activeSession) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', py: 8 }}>
        <CircularProgress size={24} />
        <Typography sx={{ ml: 2 }} color="text.secondary">
          Loading session...
        </Typography>
      </Box>
    );
  }

  // ── Session fetch error (will retry via polling) ───────────────
  if (activeSessionId && isSessionError && !activeSession) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', py: 8 }}>
        <CircularProgress size={20} />
        <Typography sx={{ ml: 2 }} color="text.secondary">
          Waiting for session #{activeSessionId}...
        </Typography>
      </Box>
    );
  }

  // ── Active session view ──────────────────────────────────────────
  if (activeSessionId) {
    const agentLabel = selectedAgent
      ? AGENT_TYPES.find((a) => a.type === selectedAgent)?.label
      : activeSession?.agentType;
    const isTerminal =
      activeSession?.state === 'stopped' ||
      activeSession?.state === 'collected' ||
      activeSession?.state === 'failed' ||
      activeSession?.state === 'cancelled';

    // Reset isStopping once backend confirms terminal state
    if (isTerminal && isStopping) {
      setIsStopping(false);
    }

    return (
      <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        {/* Session header bar */}
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            px: 2,
            py: 1,
            borderBottom: '1px solid',
            borderColor: 'divider',
            bgcolor: 'background.paper',
            flexShrink: 0,
          }}
        >
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <Typography variant="subtitle2">{agentLabel}</Typography>
            {activeSession && (
              <Chip
                size="small"
                label={activeSession.state}
                color={
                  activeSession.state === 'running' ? 'success' : activeSession.state === 'failed' ? 'error' : 'default'
                }
              />
            )}
            <Typography variant="caption" color="text.secondary">
              #{activeSessionId}
            </Typography>
            {activeSession?.containerId && (
              <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>
                {activeSession.containerId.slice(0, 12)}
              </Typography>
            )}
            {activeSession?.errorMessage && (
              <Tooltip title={activeSession.errorMessage} arrow>
                <Typography
                  variant="caption"
                  color="error"
                  sx={{ maxWidth: 300, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                >
                  {activeSession.errorMessage}
                </Typography>
              </Tooltip>
            )}
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            {!isTerminal && (
              <Button size="small" variant="outlined" color="error" onClick={handleStop} disabled={isStopping}>
                {isStopping ? 'Stopping…' : 'Stop'}
              </Button>
            )}
            <Button size="small" variant="outlined" onClick={handleNewSession}>
              New Session
            </Button>
          </Box>
        </Box>

        {/* Terminal session widget, stopping overlay, or ended message */}
        {isStopping && !isTerminal ? (
          <Box
            sx={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexDirection: 'column',
              gap: 2,
              bgcolor: '#1e1e1e',
            }}
          >
            <CircularProgress size={28} sx={{ color: '#f44336' }} />
            <Typography variant="body1" sx={{ color: '#d4d4d4' }}>
              Stopping session…
            </Typography>
          </Box>
        ) : isTerminal ? (
          <Box
            sx={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexDirection: 'column',
              gap: 2,
            }}
          >
            <Typography variant="h6" color="text.secondary">
              Session {activeSession?.state}
            </Typography>
            {activeSession?.errorMessage && (
              <Typography variant="body2" color="error">
                {activeSession.errorMessage}
              </Typography>
            )}
            <Button variant="contained" onClick={handleNewSession}>
              Start New Session
            </Button>
          </Box>
        ) : (
          <Box sx={{ flex: 1, overflow: 'hidden' }}>
            <TerminalSessionWidget
              sessionId={activeSessionId}
              session={activeSession}
              showFileTree={true}
              showFileViewer={true}
              showTerminal={true}
            />
          </Box>
        )}
      </Box>
    );
  }

  // ── Config form ──────────────────────────────────────────────────
  return (
    <Box sx={{ maxWidth: 720, mx: 'auto', py: 4, px: 2 }}>
      {/* Agent Runtime */}
      <Typography variant="subtitle2" sx={{ mb: 1, color: 'text.secondary' }}>
        Agent Runtime
      </Typography>
      <ToggleButtonGroup
        value={selectedAgent}
        exclusive
        onChange={handleAgentChange}
        size="small"
        sx={{ mb: 3, flexWrap: 'wrap' }}
      >
        {AGENT_TYPES.map(({ type, label, color }) => {
          const isConfigured = configuredAgents.includes(type);
          return (
            <Tooltip key={type} title={isConfigured ? '' : 'Not configured — complete Onboarding first'} arrow>
              <span>
                <ToggleButton
                  value={type}
                  disabled={!isConfigured}
                  sx={{
                    '&.Mui-selected': {
                      bgcolor: color,
                      color: '#fff',
                      '&:hover': { bgcolor: color },
                    },
                  }}
                >
                  {label}
                </ToggleButton>
              </span>
            </Tooltip>
          );
        })}
      </ToggleButtonGroup>

      <Divider sx={{ mb: 3 }}>
        <Typography variant="caption" color="text.secondary">
          Optional Configuration
        </Typography>
      </Divider>

      {/* Agent Persona */}
      <Autocomplete
        options={agents}
        getOptionLabel={(option) => option.title || option.name}
        value={selectedPersona}
        onChange={(_, newValue) => setSelectedPersona(newValue)}
        renderInput={(params) => <TextField {...params} label="Agent Persona (optional)" size="small" />}
        sx={{ mb: 2 }}
        isOptionEqualToValue={(option, value) => option.id === value.id}
      />

      {/* Tools */}
      <Autocomplete
        multiple
        options={tools}
        getOptionLabel={(option) => option.displayName || option.name}
        value={selectedTools}
        onChange={(_, newValue) => setSelectedTools(newValue)}
        renderInput={(params) => <TextField {...params} label="Tools (optional)" size="small" />}
        renderTags={(value, getTagProps) =>
          value.map((option, index) => (
            <Chip {...getTagProps({ index })} key={option.id} label={option.displayName || option.name} size="small" />
          ))
        }
        sx={{ mb: 2 }}
        isOptionEqualToValue={(option, value) => option.id === value.id}
      />

      {/* Skills */}
      <Autocomplete
        multiple
        options={skills}
        getOptionLabel={(option) => option.title || option.name}
        value={selectedSkills}
        onChange={(_, newValue) => setSelectedSkills(newValue)}
        renderInput={(params) => <TextField {...params} label="Skills (optional)" size="small" />}
        renderTags={(value, getTagProps) =>
          value.map((option, index) => (
            <Chip {...getTagProps({ index })} key={option.id} label={option.title || option.name} size="small" />
          ))
        }
        sx={{ mb: 2 }}
        isOptionEqualToValue={(option, value) => option.id === value.id}
      />

      {/* MCP Servers */}
      <Autocomplete
        multiple
        options={mcpServers}
        getOptionLabel={(option) => option.displayName || option.name}
        value={selectedMcpServers}
        onChange={(_, newValue) => setSelectedMcpServers(newValue)}
        renderInput={(params) => <TextField {...params} label="MCP Servers (optional)" size="small" />}
        renderTags={(value, getTagProps) =>
          value.map((option, index) => (
            <Chip {...getTagProps({ index })} key={option.id} label={option.displayName || option.name} size="small" />
          ))
        }
        sx={{ mb: 3 }}
        isOptionEqualToValue={(option, value) => option.id === value.id}
      />

      <Divider sx={{ mb: 3 }}>
        <Typography variant="caption" color="text.secondary">
          Execution Mode
        </Typography>
      </Divider>

      {/* Mode */}
      <ToggleButtonGroup value={mode} exclusive onChange={handleModeChange} size="small" sx={{ mb: 2 }}>
        <ToggleButton value="interactive">Interactive</ToggleButton>
        <ToggleButton value="non_interactive">Non-interactive</ToggleButton>
      </ToggleButtonGroup>

      {/* Initial Prompt (non-interactive only) */}
      {mode === 'non_interactive' && (
        <TextField
          label="Initial Prompt"
          placeholder="Describe the task for the agent..."
          multiline
          minRows={3}
          maxRows={8}
          fullWidth
          value={initialPrompt}
          onChange={(e) => setInitialPrompt(e.target.value)}
          required
          error={mode === 'non_interactive' && initialPrompt.trim().length === 0}
          helperText={
            mode === 'non_interactive' && initialPrompt.trim().length === 0
              ? 'Prompt is required for non-interactive mode'
              : ''
          }
          sx={{ mb: 2 }}
        />
      )}

      {/* Submit */}
      <Box sx={{ mt: 3 }}>
        <Button
          variant="contained"
          onClick={handleStart}
          disabled={!canSubmit || isCreating}
          startIcon={isCreating ? <CircularProgress size={16} color="inherit" /> : undefined}
          sx={{
            bgcolor: selectedAgent ? AGENT_TYPES.find((a) => a.type === selectedAgent)?.color : undefined,
          }}
          size="large"
        >
          Start Session
        </Button>
      </Box>
    </Box>
  );
};
