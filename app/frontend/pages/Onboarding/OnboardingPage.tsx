import type { FormDataConvertible } from '@inertiajs/core';
import { router, usePage } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Center,
  Group,
  Loader,
  Select,
  SimpleGrid,
  Stack,
  Stepper,
  Text,
  ThemeIcon,
  UnstyledButton,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import {
  IconBrandGoogleFilled,
  IconBrandOpenai,
  IconBrandX,
  IconBrush,
  IconBuilding,
  IconCheck,
  IconChevronLeft,
  IconChevronRight,
  IconClipboardList,
  IconCode,
  IconCursorText,
  IconDots,
  IconPlug,
  IconSparkles,
  IconTestPipe,
} from '@tabler/icons-react';
import { useCallback, useEffect, useRef, useState } from 'react';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { apiV1TerminalSessionsPath, finishApiV1TerminalSessionPath } from 'shared/routes';
import { AGENT_BRAND_COLORS, TERMINAL_BG } from 'shared/theme/vendorColors';
import { PageShell, type AgentType, type SharedProps } from 'shared/ui';

import classes from './OnboardingPage.module.css';

const POSITION_OPTIONS = [
  { value: 'dev', label: 'Developer', icon: IconCode },
  { value: 'qa', label: 'QA Engineer', icon: IconTestPipe },
  { value: 'pm_po_ba', label: 'Product Manager / BA', icon: IconClipboardList },
  { value: 'designer', label: 'Designer', icon: IconBrush },
  { value: 'cto', label: 'CTO', icon: IconBuilding },
  { value: 'other', label: 'Other', icon: IconDots },
];

const LANGUAGE_OPTIONS = [
  { value: 'en', label: 'English' },
  { value: 'ru', label: 'Russian' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'pl', label: 'Polish' },
];

const AVAILABLE_AGENTS: { type: AgentType; name: string; description: string; icon: typeof IconSparkles }[] = [
  {
    type: 'claude_code',
    name: 'Claude Code',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
    icon: IconSparkles,
  },
  {
    type: 'cursor_cli',
    name: 'Cursor CLI',
    description: 'AI-powered code editor with context-aware suggestions',
    icon: IconCursorText,
  },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
    icon: IconBrandOpenai,
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI assistant for code generation and analysis",
    icon: IconBrandGoogleFilled,
  },
  {
    type: 'grok',
    name: 'Grok',
    description: "xAI's Grok CLI for agentic coding in the terminal",
    icon: IconBrandX,
  },
];

const AGENT_COLORS = AGENT_BRAND_COLORS;

interface ViewerWorkflowPreview {
  workflowName: string;
  workflowDescription: string;
  steps: Array<{ name: string; description: string }>;
}

// Server state → visual step index. Two steps only: step1 (0, Profile) and
// step2 (1, Connect Agents / See the platform) — `complete` finishes directly
// from step2, so `completed` still renders the same step until the redirect lands.
const STEP_MAP: Record<string, number> = {
  step1: 0,
  step2: 1,
  completed: 1,
};

// ── Agent Auth Terminal ────────────────────────────

function ttydUrlFromWs(websocketUrl: string) {
  return websocketUrl.replace('wss://', 'https://').replace('ws://', 'http://').replace('/ws', '');
}

function AgentAuthTerminal({
  agentType,
  session,
  isConfigured,
  onAuthenticated,
}: {
  agentType: string;
  session?: TerminalSession;
  isConfigured: boolean;
  onAuthenticated: () => void;
}) {
  const [authDetected, setAuthDetected] = useState(false);
  const [finishError, setFinishError] = useState(false);
  const watcherPollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const finishedRef = useRef(false);
  const creatingRef = useRef(false);

  if (session) creatingRef.current = false;
  const sessionState = session?.state ?? (creatingRef.current ? 'starting' : 'idle');
  const isTerminal = ['finished', 'failed', 'cancelled'].includes(sessionState);
  const ttydUrl = session?.state === 'ready' && session.websocketUrl ? ttydUrlFromWs(session.websocketUrl) : null;

  useInertiaCableStream(session?.cableStream, {
    only: ['auth_sessions'],
    enabled: !!session && !isTerminal,
  });

  const createSession = useCallback(async () => {
    if (creatingRef.current) return;
    creatingRef.current = true;
    try {
      const res = await apiFetch(apiV1TerminalSessionsPath(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ terminalSession: { agentType, sessionType: 'auth_setup', mode: 'interactive' } }),
      });
      if (res.ok) {
        router.reload({ only: ['auth_sessions'] });
      } else {
        creatingRef.current = false;
      }
    } catch {
      creatingRef.current = false;
    }
  }, [agentType]);

  useEffect(() => {
    if (isConfigured || session || creatingRef.current) return;
    createSession();
  }, [isConfigured, session, createSession]);

  // Poll watcher URL to detect auth completion
  useEffect(() => {
    const watcherUrl = session?.watcherUrl;
    if (!watcherUrl || authDetected || session?.state !== 'ready') return;
    const poll = async () => {
      try {
        const res = await fetch(`${watcherUrl}/auth`, { credentials: 'include' });
        if (res.ok) {
          const data = await res.json();
          if (data.authenticated) setAuthDetected(true);
        }
      } catch {
        /* ignore */
      }
    };
    poll();
    watcherPollRef.current = setInterval(poll, 2000);
    return () => {
      if (watcherPollRef.current) {
        clearInterval(watcherPollRef.current);
        watcherPollRef.current = null;
      }
    };
  }, [session?.watcherUrl, session?.state, authDetected]);

  const handleFinish = useCallback(async () => {
    if (!session || finishedRef.current) return;
    finishedRef.current = true;
    setFinishError(false);
    try {
      await apiFetch(finishApiV1TerminalSessionPath(session.id), { method: 'POST' });

      onAuthenticated();
    } catch {
      finishedRef.current = false;
      setFinishError(true);
      notifications.show({ message: 'Failed to save authentication', color: 'red' });
    }
  }, [session, onAuthenticated]);

  // Auto-finish as soon as the watcher confirms credentials exist — no manual
  // "save" step. Credentials are persisted server-side during session cleanup.
  useEffect(() => {
    if (authDetected && session?.state === 'ready') handleFinish();
  }, [authDetected, session?.state, handleFinish]);

  if (isConfigured) {
    return (
      <Stack align="center" justify="center" h="100%" gap="sm">
        <ThemeIcon size="lg" color="green" variant="light" radius="xl">
          <IconCheck size={20} />
        </ThemeIcon>
        <Text size="sm" fw={500}>
          Authentication complete
        </Text>
      </Stack>
    );
  }

  if (sessionState === 'queued') {
    return (
      <Stack align="center" justify="center" h="100%" gap="sm">
        <Loader size="sm" />
        <Text size="sm">Waiting for an available session slot</Text>
      </Stack>
    );
  }

  if (sessionState === 'failed' || sessionState === 'cancelled') {
    return (
      <Stack align="center" justify="center" h="100%" gap="sm">
        <Text size="sm" c="red">
          {sessionState === 'cancelled'
            ? 'Authentication session cancelled.'
            : 'Authentication session failed to start.'}
        </Text>
        <Button size="xs" variant="outline" onClick={createSession}>
          Retry
        </Button>
      </Stack>
    );
  }

  if (session?.state === 'ready' && ttydUrl) {
    return (
      <Box style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
        <Box style={{ flex: 1, overflow: 'hidden' }}>
          <iframe
            src={ttydUrl}
            title="Agent Authentication Terminal"
            allow="clipboard-read; clipboard-write"
            style={{ width: '100%', height: '100%', border: 'none', backgroundColor: TERMINAL_BG }}
          />
        </Box>
        <Group
          justify="space-between"
          px="sm"
          py="xs"
          style={{ borderTop: '1px solid var(--app-border-default)', flexShrink: 0 }}
        >
          {authDetected && finishError ? (
            <>
              <Text size="xs" c="red">
                Couldn&apos;t save credentials.
              </Text>
              <Button color="green" size="xs" onClick={handleFinish}>
                Retry
              </Button>
            </>
          ) : authDetected ? (
            <Group gap="xs">
              <Loader size="xs" color="green" />
              <Text size="xs" c="green" fw={500}>
                Credentials detected — saving…
              </Text>
            </Group>
          ) : (
            <Text size="xs" c="dimmed">
              Complete authentication in the terminal above
            </Text>
          )}
        </Group>
      </Box>
    );
  }

  return (
    <Stack align="center" justify="center" h="100%" gap="sm">
      <Loader size="sm" />
      <Text size="sm" c="dimmed">
        Starting auth session...
      </Text>
    </Stack>
  );
}

// ── Step 2+3: Connect Agents (unified) ────────────

function ConnectAgentsStep({
  configuredAgents,
  authSessions,
  loading,
  onBack,
  onNext,
}: {
  configuredAgents: AgentType[];
  authSessions: TerminalSession[];
  loading: boolean;
  onBack: () => void;
  onNext: () => void;
}) {
  const [expandedAgent, setExpandedAgent] = useState<string | null>(null);
  const configuredCount = AVAILABLE_AGENTS.filter((a) => configuredAgents.includes(a.type)).length;

  const handleConnect = useCallback((agentType: string) => {
    setExpandedAgent((prev) => (prev === agentType ? null : agentType));
  }, []);

  return (
    <>
      <Card withBorder p={28}>
        <Text fw={600} size="lg" mb={4}>
          Connect your agents
        </Text>
        <Text size="sm" c="dimmed" mb="md">
          Connect at least one agent to continue. You can add the rest later in Settings.
        </Text>

        <Stack gap="xs">
          {AVAILABLE_AGENTS.map((agent) => {
            const isConfigured = configuredAgents.includes(agent.type);
            const session = authSessions.find((s) => s.agentType === agent.type);
            const hasActiveSession = !!session;
            const isExpanded = expandedAgent === agent.type;

            let chipEl: React.ReactNode;
            if (isConfigured) {
              chipEl = (
                <Badge variant="light" color="green" size="sm" leftSection={<IconCheck size={10} />}>
                  Connected
                </Badge>
              );
            } else if (hasActiveSession && session?.state !== 'failed') {
              chipEl = (
                <Badge variant="outline" color="gray" size="sm" leftSection={<Loader size={10} />}>
                  Connecting
                </Badge>
              );
            } else {
              chipEl = (
                <Badge variant="outline" color="gray" size="sm">
                  NOT CONNECTED
                </Badge>
              );
            }

            return (
              <Box key={agent.type} className={classes.authRow}>
                <Group justify="space-between" wrap="nowrap">
                  <Group gap="sm" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
                    <Box
                      className={classes.agentLogo}
                      style={{ backgroundColor: AGENT_COLORS[agent.type] ?? 'var(--app-text-tertiary)' }}
                    >
                      <agent.icon size={12} color="white" />
                    </Box>
                    <Box style={{ minWidth: 0 }}>
                      <Text size="sm" fw={500} truncate>
                        {agent.name}
                      </Text>
                      <Text size="xs" c="dimmed" truncate>
                        {agent.description}
                      </Text>
                    </Box>
                  </Group>
                  <Group gap="xs" wrap="nowrap" style={{ flexShrink: 0 }}>
                    {chipEl}
                    {!isConfigured && (
                      <Button
                        size="xs"
                        variant="outline"
                        color="brand"
                        leftSection={!isExpanded ? <IconPlug size={12} /> : undefined}
                        onClick={() => handleConnect(agent.type)}
                      >
                        {isExpanded ? 'Collapse' : 'Connect'}
                      </Button>
                    )}
                  </Group>
                </Group>

                {isExpanded && !isConfigured && (
                  <Box
                    mt="sm"
                    style={{
                      height: 280,
                      border: '1px solid var(--app-border-default)',
                      borderRadius: 6,
                      overflow: 'hidden',
                    }}
                  >
                    <AgentAuthTerminal
                      key={agent.type}
                      agentType={agent.type}
                      session={session}
                      isConfigured={false}
                      onAuthenticated={() => {
                        setExpandedAgent(null);
                        router.reload();
                      }}
                    />
                  </Box>
                )}
              </Box>
            );
          })}
        </Stack>
      </Card>

      <Group justify="space-between" mt="lg">
        <Button
          variant="outline"
          size="sm"
          leftSection={<IconChevronLeft size={16} />}
          onClick={onBack}
          loading={loading}
        >
          Back
        </Button>
        <Group gap="xs">
          <Text size="xs" c="dimmed">
            {configuredCount} of {AVAILABLE_AGENTS.length} connected
          </Text>
          <Button
            size="sm"
            rightSection={<IconChevronRight size={16} />}
            onClick={onNext}
            loading={loading}
            disabled={configuredCount === 0}
          >
            Get started
          </Button>
        </Group>
      </Group>
    </>
  );
}

// ── Main Page ──────────────────────────────────────

const OnboardingPage = () => {
  const {
    currentUser,
    authSessions = [],
    cableStream,
    viewerWorkflowPreview = null,
  } = usePage<
    SharedProps & {
      authSessions: TerminalSession[];
      cableStream?: string;
      viewerWorkflowPreview?: ViewerWorkflowPreview | null;
    }
  >().props;

  useInertiaCableStream(cableStream);

  const company = currentUser?.currentCompany ?? null;
  const isViewer = currentUser?.currentRole === 'viewer';
  const onboardingState = currentUser?.onboardingState ?? 'step1';
  // Two steps: Profile (0) → Connect Agents / See the platform (1). "Get started"
  // on step 2 fires `complete` directly — there is no separate summary step.
  const activeStep = STEP_MAP[onboardingState] ?? 0;

  const [position, setPosition] = useState(currentUser?.position ?? '');
  const [language, setLanguage] = useState(currentUser?.preferredAgentLanguage ?? '');
  const selectedAgents = currentUser?.selectedAgents ?? [];
  const [loading, setLoading] = useState(false);
  const [validationWarning, setValidationWarning] = useState<string | null>(null);

  const autoSaveRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const canAdvanceStep1 = !!position && !!language;

  const configuredAgents = currentUser?.configuredAgents ?? [];

  const autoSave = useCallback((data: Record<string, unknown>) => {
    if (autoSaveRef.current) clearTimeout(autoSaveRef.current);
    autoSaveRef.current = setTimeout(() => {
      router.patch('/onboarding', { onboarding: data } as Record<string, FormDataConvertible>, {
        preserveScroll: true,
        preserveState: true,
      });
    }, 300);
  }, []);

  useEffect(() => {
    return () => {
      if (autoSaveRef.current) clearTimeout(autoSaveRef.current);
    };
  }, []);

  const handlePositionChange = useCallback(
    (v: string | null) => {
      const val = v ?? '';
      setPosition(val);
      setValidationWarning(null);
      autoSave({ position: val, preferredAgentLanguage: language });
    },
    [autoSave, language],
  );

  const handleLanguageChange = useCallback(
    (v: string | null) => {
      const val = v ?? '';
      setLanguage(val);
      setValidationWarning(null);
      autoSave({ position, preferredAgentLanguage: val });
    },
    [autoSave, position],
  );

  const submitStep = useCallback((data: Record<string, unknown>) => {
    setLoading(true);
    router.patch('/onboarding', { onboarding: data } as Record<string, FormDataConvertible>, {
      preserveScroll: true,
      onFinish: () => setLoading(false),
    });
  }, []);

  const handleNext = useCallback(() => {
    if (!canAdvanceStep1) {
      setValidationWarning('Please fill in all required fields to continue');
      return;
    }
    submitStep({
      position,
      preferredAgentLanguage: language,
      selectedAgents: selectedAgents,
      onboardingStateEvent: 'go_next',
    });
  }, [position, language, selectedAgents, canAdvanceStep1, submitStep]);

  const handleBack = useCallback(() => {
    setValidationWarning(null);
    submitStep({ onboardingStateEvent: 'go_previous' });
  }, [submitStep]);

  // Step 2's "Get started" finishes onboarding directly — step2 → completed.
  const handleFinish = useCallback(() => {
    submitStep({ onboardingStateEvent: 'complete' });
  }, [submitStep]);

  if (!currentUser) return null;

  const inviteSubtitle = company?.name
    ? `You've been invited to join ${company.name} — you can change everything later.`
    : 'Set up your profile to get started.';

  return (
    <PageShell variant="narrow" py={60}>
      <Center mb="xl" className={classes.welcomeCard}>
        <Stack align="center" gap={4}>
          {company?.logoUrl && <img src={company.logoUrl} alt={company.name} className={classes.companyLogo} />}
          <Text size="xl" fw={700}>
            Set up your workspace
          </Text>
          <Text size="sm" c="dimmed" className={classes.subtitle}>
            {inviteSubtitle}
          </Text>
        </Stack>
      </Center>

      <Stepper
        active={activeStep}
        mb="xl"
        size="xs"
        iconSize={26}
        allowNextStepsSelect={false}
        classNames={{ stepLabel: classes.stepLabel, stepIcon: classes.stepIcon }}
      >
        <Stepper.Step label="Profile" />
        <Stepper.Step label={isViewer ? 'Platform' : 'Agents'} />
      </Stepper>

      {/* Step 1: Profile */}
      {activeStep === 0 && (
        <Box key="step-0" className={classes.stepContent}>
          <Card withBorder p={28}>
            <Text fw={600} size="lg" mb={4}>
              Tell us about yourself
            </Text>
            <Text size="sm" c="dimmed" mb="md">
              This helps us tailor agent defaults to your role.
            </Text>
            <Stack gap="md">
              <Box>
                <Text size="xs" c="dimmed" fw={500} mb="xs">
                  Your position{' '}
                  <Text component="span" c="red" inherit>
                    *
                  </Text>
                </Text>
                <SimpleGrid cols={2} spacing="xs">
                  {POSITION_OPTIONS.map((opt) => {
                    const Icon = opt.icon;
                    const selected = position === opt.value;
                    return (
                      <UnstyledButton
                        key={opt.value}
                        className={`${classes.roleOpt} ${selected ? classes.roleOptSelected : ''}`}
                        onClick={() => handlePositionChange(opt.value)}
                        aria-pressed={selected}
                      >
                        <Icon size={18} />
                        <Text size="sm" fw={500}>
                          {opt.label}
                        </Text>
                      </UnstyledButton>
                    );
                  })}
                </SimpleGrid>
              </Box>
              <Select
                label="Agent response language"
                placeholder="Select language"
                data={LANGUAGE_OPTIONS}
                value={language}
                onChange={handleLanguageChange}
                searchable
                size="sm"
                classNames={{ label: classes.fieldLabel }}
              />
            </Stack>
            {validationWarning && (
              <Text size="sm" c="yellow" mt="md">
                ⚠ {validationWarning}
              </Text>
            )}
          </Card>
          <Group justify="flex-end" mt="lg">
            <Button
              size="sm"
              rightSection={<IconChevronRight size={16} />}
              onClick={handleNext}
              loading={loading}
              disabled={!canAdvanceStep1}
            >
              Continue
            </Button>
          </Group>
        </Box>
      )}

      {/* Step 2: Connect Agents (contributors only) */}
      {activeStep === 1 && !isViewer && (
        <Box key="step-connect" className={classes.stepContent}>
          <ConnectAgentsStep
            configuredAgents={configuredAgents}
            authSessions={authSessions}
            loading={loading}
            onBack={handleBack}
            onNext={handleFinish}
          />
        </Box>
      )}

      {/* Step 2: See the platform (viewers only) */}
      {activeStep === 1 && isViewer && (
        <Box key="step-viewer" className={classes.stepContent}>
          <Card withBorder p={28}>
            {viewerWorkflowPreview ? (
              <>
                <Text fw={600} size="lg" mb={4}>
                  Here&apos;s what a workflow looks like in action
                </Text>
                <Badge size="sm" variant="outline" mb="md">
                  Read-only preview
                </Badge>
                <Text size="sm" c="dimmed" mb="md">
                  {viewerWorkflowPreview.workflowName}
                </Text>
                <Text size="sm" mb="xs">
                  {viewerWorkflowPreview.workflowDescription}
                </Text>
                {viewerWorkflowPreview.steps?.length > 0 && (
                  <Stack gap="xs" mb="md">
                    {viewerWorkflowPreview.steps?.map((step, i) => (
                      <Card key={i} withBorder p="sm">
                        <Text size="sm" fw={500}>
                          {i + 1}. {step.name}
                        </Text>
                        {step.description && (
                          <Text size="xs" c="dimmed">
                            {step.description}
                          </Text>
                        )}
                      </Card>
                    ))}
                  </Stack>
                )}
                <Text size="xs" c="dimmed" mb="xl">
                  You can explore the full board once you&apos;re in.
                </Text>
              </>
            ) : (
              <>
                <Text fw={600} size="lg" mb={4}>
                  See the platform in action
                </Text>
                <Text size="sm" c="dimmed" mb="md">
                  Once you&apos;re in, you&apos;ll see your team&apos;s workflows here.
                </Text>
                <Text size="sm" mb="xl">
                  Each workflow automates a step of your process — from code review to bug triage to deployment.
                </Text>
              </>
            )}
          </Card>
          <Group justify="space-between" mt="lg">
            <Button
              variant="outline"
              size="sm"
              leftSection={<IconChevronLeft size={16} />}
              onClick={handleBack}
              loading={loading}
            >
              Back
            </Button>
            <Button size="sm" rightSection={<IconChevronRight size={16} />} onClick={handleFinish} loading={loading}>
              Get started
            </Button>
          </Group>
        </Box>
      )}
    </PageShell>
  );
};

export default OnboardingPage;
