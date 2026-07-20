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
  Progress,
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
  IconBrush,
  IconBuilding,
  IconCheck,
  IconChevronLeft,
  IconChevronRight,
  IconCode,
  IconClipboardList,
  IconRocket,
  IconTestPipe,
  IconUser,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { apiV1TerminalSessionsPath, finishApiV1TerminalSessionPath } from 'shared/routes';
import { PageShell, type AgentType, type SharedProps } from 'shared/ui';

import classes from './OnboardingPage.module.css';

const POSITION_OPTIONS = [
  { value: 'dev', label: 'Developer', icon: IconCode },
  { value: 'qa', label: 'QA Engineer', icon: IconTestPipe },
  { value: 'pm_po_ba', label: 'Product Manager / BA', icon: IconClipboardList },
  { value: 'designer', label: 'Designer', icon: IconBrush },
  { value: 'cto', label: 'CTO', icon: IconBuilding },
];

// Kept for label lookups only (no icon needed in non-grid contexts)
const POSITION_LABEL_MAP = Object.fromEntries(POSITION_OPTIONS.map((o) => [o.value, o.label]));

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

const AVAILABLE_AGENTS: { type: AgentType; name: string; description: string }[] = [
  {
    type: 'claude_code',
    name: 'Claude Code',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
  },
  { type: 'cursor_cli', name: 'Cursor CLI', description: 'AI-powered code editor with context-aware suggestions' },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI assistant for code generation and analysis",
  },
];

const AGENT_COLORS: Record<string, string> = {
  claude_code: '#d97706',
  cursor_cli: '#7c3aed',
  codex: '#10a37f',
  gemini_cli: '#3b82f6',
};

interface ViewerWorkflowPreview {
  workflowName: string;
  workflowDescription: string;
  steps: Array<{ name: string; description: string }>;
}

// Viewer step map: server state → visual step index
// step1 → 0 (Profile), step2/step3 → 1 (See the platform), step4/completed → 2 (Complete)
const viewerStepMap: Record<string, number> = {
  step1: 0,
  step2: 1,
  step3: 1,
  step4: 2,
  completed: 2,
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
  const isTerminal = sessionState === 'finished' || sessionState === 'failed';
  const ttydUrl = session?.state === 'ready' && session.websocketUrl ? ttydUrlFromWs(session.websocketUrl) : null;

  useInertiaCableStream(session?.cableStream, {
    only: ['authSessions'],
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
        router.reload({ only: ['authSessions'] });
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

  if (sessionState === 'failed') {
    return (
      <Stack align="center" justify="center" h="100%" gap="sm">
        <Text size="sm" c="red">
          Authentication session failed to start.
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
            style={{ width: '100%', height: '100%', border: 'none', backgroundColor: '#000' }}
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
    <Card withBorder p={0} style={{ overflow: 'hidden' }}>
      <Box p="xl" style={{ borderBottom: '1px solid var(--app-border-default)' }}>
        <Text fw={600} size="lg" mb={4}>
          Connect your agents
        </Text>
        <Text size="sm" c="dimmed">
          Sign in to at least one agent to enable it for your workflows.
        </Text>
      </Box>

      <Stack gap={0}>
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
                  <Box className={classes.agentLogo} style={{ backgroundColor: AGENT_COLORS[agent.type] ?? '#666' }} />
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
                    <Button size="xs" variant="outline" color="brand" onClick={() => handleConnect(agent.type)}>
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

      <Group justify="space-between" p="md" style={{ borderTop: '1px solid var(--app-border-default)' }}>
        <Button
          variant="outline"
          size="md"
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
            size="md"
            rightSection={<IconChevronRight size={16} />}
            onClick={onNext}
            loading={loading}
            disabled={configuredCount === 0}
          >
            Continue
          </Button>
        </Group>
      </Group>
    </Card>
  );
}

// ── Main Page ──────────────────────────────────────

const CONFETTI_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'];

function Confetti() {
  const pieces = useMemo(
    () =>
      Array.from({ length: 24 }, (_, i) => ({
        id: i,
        left: `${Math.random() * 100}%`,
        color: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
        delay: `${Math.random() * 2}s`,
        duration: `${2 + Math.random() * 2}s`,
        size: 6 + Math.random() * 6,
      })),
    [],
  );

  return (
    <Box className={classes.confettiContainer}>
      {pieces.map((p) => (
        <Box
          key={p.id}
          className={classes.confettiPiece}
          style={{
            left: p.left,
            backgroundColor: p.color,
            width: p.size,
            height: p.size,
            animationDelay: p.delay,
            animationDuration: p.duration,
          }}
        />
      ))}
    </Box>
  );
}

const contributorStepMap: Record<string, number> = {
  step1: 0,
  step2: 1,
  step3: 1,
  step4: 2,
  completed: 2,
};

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
  // Viewers see: Profile (0) → See the platform (1) → Complete (2)
  // Contributors see: Profile (0) → Connect Agents (1) → Complete (2)
  const activeStep = isViewer ? (viewerStepMap[onboardingState] ?? 0) : (contributorStepMap[onboardingState] ?? 0);

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
    if (activeStep === 0) {
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
    } else if (activeStep === 1 && isViewer) {
      // Viewer "See the platform" step → viewer_advance jumps step2→step4
      submitStep({ onboardingStateEvent: 'viewer_advance' });
    }
  }, [activeStep, isViewer, position, language, selectedAgents, canAdvanceStep1, submitStep]);

  const handleBack = useCallback(() => {
    setValidationWarning(null);
    submitStep({ onboardingStateEvent: 'go_previous' });
  }, [submitStep]);

  const handleConnectAgentsNext = useCallback(() => {
    // Server may be at step2 (first time on Connect Agents) or step3 (re-visiting).
    // Send go_next once; if server is at step2 it advances to step3, which triggers
    // another go_next via a follow-up call since step3→step4 guard passes for contributors
    // who have at least one configured agent.
    submitStep({ onboardingStateEvent: 'go_next' });
  }, [submitStep]);

  const handleComplete = useCallback(() => {
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

      <Progress
        value={
          isViewer
            ? activeStep === 0
              ? 0
              : activeStep === 1
                ? 50
                : 100
            : activeStep === 0
              ? 0
              : activeStep === 1
                ? 50
                : 100
        }
        animated
        size="sm"
        mb="lg"
        radius="xl"
      />

      <Stepper active={activeStep} mb="xl" allowNextStepsSelect={false}>
        <Stepper.Step label="Your Profile" icon={<IconUser size={18} />} />
        {!isViewer && <Stepper.Step label="Connect Agents" />}
        {isViewer && <Stepper.Step label="See the platform" />}
        <Stepper.Step label="Complete" icon={<IconCheck size={18} />} />
      </Stepper>

      {/* Step 1: Profile */}
      {activeStep === 0 && (
        <Box key="step-0" className={classes.stepContent}>
          <Card withBorder p="xl">
            <Text fw={600} size="lg" mb="md">
              Tell us about yourself
            </Text>
            <Stack gap="md">
              <Box>
                <Text size="sm" fw={500} mb="xs">
                  Your Position
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
                        <Text size="sm" fw={500} mt={4}>
                          {opt.label}
                        </Text>
                      </UnstyledButton>
                    );
                  })}
                </SimpleGrid>
              </Box>
              <Select
                label="Preferred Agent Language"
                placeholder="Select language"
                data={LANGUAGE_OPTIONS}
                value={language}
                onChange={handleLanguageChange}
                searchable
                required
                size="md"
              />
            </Stack>
            {validationWarning && (
              <Text size="sm" c="yellow" mt="md">
                ⚠ {validationWarning}
              </Text>
            )}
            <Group justify="flex-end" mt="xl">
              <Button
                size="md"
                rightSection={<IconChevronRight size={16} />}
                onClick={handleNext}
                loading={loading}
                disabled={!canAdvanceStep1}
              >
                Continue
              </Button>
            </Group>
          </Card>
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
            onNext={handleConnectAgentsNext}
          />
        </Box>
      )}

      {/* Step 2: See the platform (viewers only) */}
      {activeStep === 1 && isViewer && (
        <Box key="step-viewer" className={classes.stepContent}>
          <Card withBorder p="xl">
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
            <Group justify="flex-end">
              <Button size="md" rightSection={<IconChevronRight size={16} />} onClick={handleNext} loading={loading}>
                Continue
              </Button>
            </Group>
          </Card>
        </Box>
      )}

      {/* Step 3/2: Complete */}
      {((!isViewer && activeStep === 2) || (isViewer && activeStep === 2)) && (
        <Box key="step-complete" className={classes.stepContent} pos="relative">
          <Confetti />
          <Card withBorder p="xl">
            <Center mb="md">
              <ThemeIcon size="xl" radius="xl" color="green" variant="light">
                <IconCheck size={28} />
              </ThemeIcon>
            </Center>
            <Text fw={600} size="lg" ta="center" mb="xs">
              You&apos;re all set!
            </Text>
            <Text size="sm" c="dimmed" ta="center" mb="xl">
              Review your configuration and click &quot;Get Started&quot; to begin.
            </Text>

            <Stack gap="sm" mb="xl" style={{ maxWidth: 500, margin: '0 auto' }}>
              <Card withBorder p="sm">
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">
                    Position
                  </Text>
                  <Text size="sm" fw={500}>
                    {POSITION_LABEL_MAP[position] ?? position}
                  </Text>
                </Group>
              </Card>
              <Card withBorder p="sm">
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">
                    Language
                  </Text>
                  <Text size="sm" fw={500}>
                    {LANGUAGE_OPTIONS.find((o) => o.value === language)?.label ?? language}
                  </Text>
                </Group>
              </Card>

              {!isViewer &&
                selectedAgents.map((a) => {
                  const agent = AVAILABLE_AGENTS.find((ag) => ag.type === a);
                  const isAuth = configuredAgents.includes(a);
                  return (
                    <Card
                      key={a}
                      withBorder
                      p="sm"
                      className={`${classes.summaryCard} ${classes.agentCard}`}
                      style={{ borderLeftColor: AGENT_COLORS[a] ?? '#666' }}
                    >
                      <Group justify="space-between">
                        <Text size="sm" fw={500}>
                          {agent?.name ?? a}
                        </Text>
                        <Badge size="sm" color={isAuth ? 'green' : 'yellow'} variant="filled">
                          {isAuth ? '✓ Authenticated' : '⚠ Not authenticated'}
                        </Badge>
                      </Group>
                    </Card>
                  );
                })}
            </Stack>

            <Group justify={isViewer ? 'flex-end' : 'space-between'}>
              {!isViewer && (
                <Button
                  variant="outline"
                  size="md"
                  leftSection={<IconChevronLeft size={16} />}
                  onClick={handleBack}
                  loading={loading}
                >
                  Back
                </Button>
              )}
              <Button size="md" leftSection={<IconRocket size={16} />} onClick={handleComplete} loading={loading}>
                Get Started
              </Button>
            </Group>
          </Card>
        </Box>
      )}
    </PageShell>
  );
};

export default OnboardingPage;
