import type { FormDataConvertible } from '@inertiajs/core';
import { router, usePage } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Center,
  Checkbox,
  Group,
  Loader,
  Progress,
  Select,
  SimpleGrid,
  Stack,
  Stepper,
  Text,
  ThemeIcon,
} from '@mantine/core';
import { IconCheck, IconChevronLeft, IconChevronRight, IconLock, IconRocket, IconUser } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type TerminalSession from 'types/generated/TerminalSession';

import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { apiV1TerminalSessionsPath, finishApiV1TerminalSessionPath } from 'shared/routes';
import { PageShell, type AgentType, type SharedProps } from 'shared/ui';

import classes from './OnboardingPage.module.css';

const POSITION_OPTIONS = [
  { value: 'dev', label: 'Developer' },
  { value: 'qa', label: 'QA Engineer' },
  { value: 'pm_po_ba', label: 'Product Manager / BA' },
  { value: 'designer', label: 'Designer' },
  { value: 'cto', label: 'CTO' },
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
    try {
      await apiFetch(finishApiV1TerminalSessionPath(session.id), { method: 'POST' });

      onAuthenticated();
    } catch {
      finishedRef.current = false;
    }
  }, [session, onAuthenticated]);

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
          style={{ borderTop: '1px solid var(--mantine-color-dark-4)', flexShrink: 0 }}
        >
          <Group gap="xs">
            {authDetected && (
              <Badge color="green" size="sm" variant="filled">
                Auth detected
              </Badge>
            )}
            {!authDetected && (
              <Text size="xs" c="dimmed">
                Complete authentication in the terminal above
              </Text>
            )}
          </Group>
          <Button color="green" size="xs" onClick={handleFinish} disabled={!authDetected}>
            Save Authentication
          </Button>
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

// ── Step 3: Authenticate ───────────────────────────

function AuthenticateStep({
  selectedAgents,
  configuredAgents,
  configuredCount,
  authSessions,
  loading,
  onBack,
  onNext,
}: {
  selectedAgents: AgentType[];
  configuredAgents: AgentType[];
  configuredCount: number;
  authSessions: TerminalSession[];
  loading: boolean;
  onBack: () => void;
  onNext: () => void;
}) {
  const [activeAgent, setActiveAgent] = useState<string | null>(null);

  return (
    <Card withBorder p={0} style={{ overflow: 'hidden' }}>
      <Box style={{ display: 'flex', minHeight: 500 }}>
        <Box w={280} p="md" style={{ borderRight: '1px solid var(--mantine-color-dark-4)', flexShrink: 0 }}>
          <Text fw={600} size="lg" mb="xs">
            Authenticate Your Agents
          </Text>
          <Text size="sm" c="dimmed" mb="md">
            Sign in to at least one agent&apos;s service to enable it.
          </Text>
          <Stack gap="xs">
            {selectedAgents.map((agentType) => {
              const agent = AVAILABLE_AGENTS.find((a) => a.type === agentType);
              const isConfigured = configuredAgents.includes(agentType);
              const hasActiveSession = authSessions.some((s) => s.agentType === agentType);
              const isActive = activeAgent === agentType;
              return (
                <Box
                  key={agentType}
                  onClick={() => setActiveAgent(agentType)}
                  p="sm"
                  style={{
                    border: `1px solid ${isActive ? 'var(--mantine-color-blue-6)' : 'var(--mantine-color-dark-4)'}`,
                    borderLeft: `4px solid ${AGENT_COLORS[agentType] ?? '#666'}`,
                    borderRadius: 8,
                    cursor: 'pointer',
                    backgroundColor: isActive ? 'var(--mantine-color-dark-5)' : undefined,
                  }}
                >
                  <Group justify="space-between">
                    <Text size="sm" fw={500}>
                      {agent?.name ?? agentType}
                    </Text>
                    {isConfigured ? (
                      <Badge size="sm" color="green" variant="filled" leftSection={<IconCheck size={10} />}>
                        Authenticated
                      </Badge>
                    ) : hasActiveSession ? (
                      <Badge size="sm" color="yellow" variant="filled">
                        In progress
                      </Badge>
                    ) : (
                      <Badge size="sm" color="gray" variant="outline">
                        Click to authenticate
                      </Badge>
                    )}
                  </Group>
                </Box>
              );
            })}
          </Stack>
          <Text size="xs" c="dimmed" mt="md">
            {configuredCount > 0
              ? `${configuredCount} of ${selectedAgents.length} authenticated.`
              : 'No agents authenticated yet.'}
          </Text>
        </Box>

        <Box style={{ flex: 1, minHeight: 500, display: 'flex', flexDirection: 'column' }}>
          {activeAgent ? (
            <AgentAuthTerminal
              key={activeAgent}
              agentType={activeAgent}
              session={authSessions.find((s) => s.agentType === activeAgent)}
              isConfigured={configuredAgents.includes(activeAgent as AgentType)}
              onAuthenticated={() => router.reload()}
            />
          ) : (
            <Stack align="center" justify="center" style={{ flex: 1 }} gap="sm">
              <IconLock size={48} color="var(--mantine-color-dimmed)" />
              <Text size="sm" c="dimmed">
                Select an agent to authenticate
              </Text>
            </Stack>
          )}
        </Box>
      </Box>

      <Group justify="space-between" p="md" style={{ borderTop: '1px solid var(--mantine-color-dark-4)' }}>
        <Button
          variant="outline"
          size="md"
          leftSection={<IconChevronLeft size={16} />}
          onClick={onBack}
          loading={loading}
        >
          Back
        </Button>
        <Button
          size="md"
          rightSection={<IconChevronRight size={16} />}
          onClick={onNext}
          loading={loading}
          disabled={configuredCount === 0}
        >
          Continue ({configuredCount}/{selectedAgents.length})
        </Button>
      </Group>
    </Card>
  );
}

// ── Main Page ──────────────────────────────────────

const STEP_PROGRESS: Record<number, number> = { 0: 0, 1: 33, 2: 66, 3: 100 };

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

const stateToStep: Record<string, number> = { step1: 0, step2: 1, step3: 2, step4: 3 };

const OnboardingPage = () => {
  const {
    currentUser,
    authSessions = [],
    cableStream,
  } = usePage<SharedProps & { authSessions: TerminalSession[]; cableStream?: string }>().props;

  useInertiaCableStream(cableStream);

  const company = currentUser?.company ?? null;
  const activeStep = stateToStep[currentUser?.onboardingState ?? ''] ?? 0;

  const [position, setPosition] = useState(currentUser?.position ?? '');
  const [language, setLanguage] = useState(currentUser?.preferredAgentLanguage ?? '');
  const [selectedAgents, setSelectedAgents] = useState<AgentType[]>(currentUser?.selectedAgents ?? []);
  const [loading, setLoading] = useState(false);
  const [validationWarning, setValidationWarning] = useState<string | null>(null);

  const autoSaveRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const canAdvanceStep1 = !!position && !!language;
  const canAdvanceStep2 = selectedAgents.length > 0;

  const configuredAgents = currentUser?.configuredAgents ?? [];

  const configuredCount = useMemo(
    () => selectedAgents.filter((a) => configuredAgents.includes(a)).length,
    [selectedAgents, configuredAgents],
  );

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

  const toggleAgent = useCallback(
    (type: AgentType) => {
      setSelectedAgents((prev) => {
        const next = prev.includes(type) ? prev.filter((a) => a !== type) : [...prev, type];
        autoSave({ selectedAgents: next });
        return next;
      });
      setValidationWarning(null);
    },
    [autoSave],
  );

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
    } else if (activeStep === 1) {
      if (!canAdvanceStep2) {
        setValidationWarning('Select at least one agent to continue');
        return;
      }
      submitStep({ selectedAgents: selectedAgents, onboardingStateEvent: 'go_next' });
    } else if (activeStep === 2) {
      submitStep({ onboardingStateEvent: 'go_next' });
    }
  }, [activeStep, position, language, selectedAgents, canAdvanceStep1, canAdvanceStep2, submitStep]);

  const handleBack = useCallback(() => {
    setValidationWarning(null);
    submitStep({ onboardingStateEvent: 'go_previous' });
  }, [submitStep]);

  const handleComplete = useCallback(() => {
    submitStep({ onboardingStateEvent: 'complete' });
  }, [submitStep]);

  if (!currentUser) return null;

  return (
    <PageShell variant="narrow" py={60}>
      <Center mb="xl" className={classes.welcomeCard}>
        <Stack align="center" gap={4}>
          {company?.logoUrl && <img src={company.logoUrl} alt={company.name} className={classes.companyLogo} />}
          <ThemeIcon size="xl" radius="xl" variant="gradient" gradient={{ from: 'blue', to: 'cyan' }}>
            <IconRocket size={28} />
          </ThemeIcon>
          <Text size="xl" fw={700}>
            Welcome to {company?.name ?? 'the Platform'}!
          </Text>
          <Text size="sm" c="dimmed" className={classes.subtitle}>
            Let&apos;s set up your profile and AI agents to get started
          </Text>
        </Stack>
      </Center>

      <Progress value={STEP_PROGRESS[activeStep] ?? 0} animated size="sm" mb="lg" radius="xl" />

      <Stepper active={activeStep} mb="xl" allowNextStepsSelect={false}>
        <Stepper.Step label="Your Profile" icon={<IconUser size={18} />} />
        <Stepper.Step label="Select Agents" />
        <Stepper.Step label="Authenticate" />
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
              <Select
                label="Your Position"
                placeholder="Select your role"
                data={POSITION_OPTIONS}
                value={position}
                onChange={handlePositionChange}
                required
                size="md"
              />
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
              <Button size="md" rightSection={<IconChevronRight size={16} />} onClick={handleNext} loading={loading}>
                Continue
              </Button>
            </Group>
          </Card>
        </Box>
      )}

      {/* Step 2: Select Agents */}
      {activeStep === 1 && (
        <Box key="step-1" className={classes.stepContent}>
          <Card withBorder p="xl">
            <Text fw={600} size="lg" mb="xs">
              Select your AI agents
            </Text>
            <Text size="sm" c="dimmed" mb="md">
              Choose at least one agent to work with. You can change this later.
            </Text>
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
              {AVAILABLE_AGENTS.map((agent) => {
                const selected = selectedAgents.includes(agent.type);
                return (
                  <Card
                    key={agent.type}
                    withBorder
                    p="md"
                    className={classes.agentCard}
                    style={{
                      borderLeftColor: AGENT_COLORS[agent.type] ?? '#666',
                      borderRightColor: selected ? 'var(--mantine-color-blue-6)' : undefined,
                      borderTopColor: selected ? 'var(--mantine-color-blue-6)' : undefined,
                      borderBottomColor: selected ? 'var(--mantine-color-blue-6)' : undefined,
                      backgroundColor: selected ? 'var(--mantine-color-blue-light)' : undefined,
                    }}
                    onClick={() => toggleAgent(agent.type)}
                  >
                    <Group justify="space-between" mb="xs">
                      <Text fw={500} size="sm">
                        {agent.name}
                      </Text>
                      <Checkbox checked={selected} onChange={() => toggleAgent(agent.type)} size="sm" />
                    </Group>
                    <Text size="xs" c="dimmed">
                      {agent.description}
                    </Text>
                  </Card>
                );
              })}
            </SimpleGrid>
            {validationWarning && (
              <Text size="sm" c="yellow" mt="md">
                ⚠ {validationWarning}
              </Text>
            )}
            <Group justify="space-between" mt="xl">
              <Button
                variant="outline"
                size="md"
                leftSection={<IconChevronLeft size={16} />}
                onClick={handleBack}
                loading={loading}
              >
                Back
              </Button>
              <Button size="md" rightSection={<IconChevronRight size={16} />} onClick={handleNext} loading={loading}>
                Continue
              </Button>
            </Group>
          </Card>
        </Box>
      )}

      {/* Step 3: Authenticate */}
      {activeStep === 2 && (
        <Box key="step-2" className={classes.stepContent}>
          <AuthenticateStep
            selectedAgents={selectedAgents}
            configuredAgents={configuredAgents}
            configuredCount={configuredCount}
            authSessions={authSessions}
            loading={loading}
            onBack={handleBack}
            onNext={handleNext}
          />
        </Box>
      )}

      {/* Step 4: Complete */}
      {activeStep === 3 && (
        <Box key="step-3" className={classes.stepContent} pos="relative">
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
                    {POSITION_OPTIONS.find((o) => o.value === position)?.label ?? position}
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

              {selectedAgents.map((a) => {
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

            <Group justify="space-between">
              <Button
                variant="outline"
                size="md"
                leftSection={<IconChevronLeft size={16} />}
                onClick={handleBack}
                loading={loading}
              >
                Back
              </Button>
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
