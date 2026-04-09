import { router, useForm } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Center,
  Divider,
  Group,
  Loader,
  Modal,
  Select,
  Stack,
  Text,
  TextInput,
  ThemeIcon,
  Title,
  Tooltip,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { type Subscription } from '@rails/actioncable';
import { IconCheck, IconLock, IconTrash } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { z } from 'zod';

import { AuthLayout } from 'layouts/AuthLayout';

import { getConsumer } from 'shared/lib/actionCableConsumer';
import { apiFetch } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { apiV1TerminalSessionPath, apiV1TerminalSessionsPath, finishApiV1TerminalSessionPath } from 'shared/routes';
import { type AgentCredential, type AgentType, type SharedUser, type UserRole } from 'shared/ui';

import classes from './Show.module.css';

const LANGUAGE_OPTIONS = [
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ru', label: 'Russian' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'pl', label: 'Polish' },
  { value: 'uk', label: 'Ukrainian' },
];

const AVAILABLE_AGENTS: { type: AgentType; name: string; description: string; color: string }[] = [
  {
    type: 'claude_code',
    name: 'Claude Code',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
    color: '#d97706',
  },
  {
    type: 'cursor_cli',
    name: 'Cursor CLI',
    description: 'AI-powered code editor with context-aware suggestions',
    color: '#7c3aed',
  },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
    color: '#10a37f',
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI for code and documentation tasks",
    color: '#3b82f6',
  },
];

const ROLE_COLORS: Record<UserRole, string> = {
  super_admin: 'grape',
  admin: 'blue',
  employee: 'gray',
};

const ROLE_LABELS: Record<UserRole, string> = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  employee: 'Employee',
};

const formatDate = (d: string | null) => {
  if (!d) return '';
  return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

const getAgentInfo = (type: AgentType) => AVAILABLE_AGENTS.find((a) => a.type === type)!;

const profileSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters'),
  preferredAgentLanguage: z.string().min(1, 'Language is required'),
});

type ProfileFormErrors = Partial<Record<keyof z.infer<typeof profileSchema>, string>>;

interface AgentModel {
  modelId: string;
  displayName: string;
  description: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface Props {
  profile: SharedUser;
  languageOptions: string[];
  agentModels: AgentModelsEntry[];
  cableStream?: string;
}

function DefaultAgentSelector({ profile }: { profile: SharedUser }) {
  const credentials = profile.agentCredentials ?? [];
  const [saving, setSaving] = useState(false);

  const handleChange = (val: string | null) => {
    const id = val ? Number(val) : null;
    setSaving(true);
    router.patch(
      '/profile',
      { profile: { defaultAgentCredentialId: id } },
      {
        preserveScroll: true,
        onFinish: () => setSaving(false),
      },
    );
  };

  if (credentials.length === 0) {
    return (
      <Card p={20} mt={24}>
        <Title order={5} mb={4}>
          Default Agent Runtime
        </Title>
        <Text size="sm" c="dimmed">
          No agent credentials configured. Complete onboarding to set up agents.
        </Text>
      </Card>
    );
  }

  return (
    <Card p={20} mt={24}>
      <Title order={5} mb={4}>
        Default Agent Runtime
      </Title>
      <Text size="sm" c="dimmed" mb="md">
        Used when starting new sessions and as fallback for workflow execution.
      </Text>
      <Select
        value={profile.defaultAgentCredentialId?.toString() ?? ''}
        onChange={handleChange}
        disabled={saving || credentials.length <= 1}
        data={credentials.map((c: AgentCredential) => ({
          value: c.id.toString(),
          label: getAgentInfo(c.agentType).name,
        }))}
      />
    </Card>
  );
}

function CredentialModelRow({ credential, models }: { credential: AgentCredential; models: AgentModel[] }) {
  const [currentModel, setCurrentModel] = useState(credential.defaultModel ?? '');
  const agentLabel = getAgentInfo(credential.agentType).name;

  const handleSubmit = useCallback(
    (modelId: string | null) => {
      router.put(
        '/profile/update_default_model',
        {
          agentCredentialId: credential.id,
          defaultModel: modelId || null,
        },
        {
          preserveScroll: true,
          preserveState: true,
          onSuccess: () => {
            notifications.show({
              message: modelId
                ? `Default model set to ${modelId} for ${agentLabel}`
                : `Default model cleared for ${agentLabel}`,
              color: 'green',
            });
          },
          onError: () => {
            notifications.show({ message: 'Failed to update default model', color: 'red' });
          },
        },
      );
    },
    [credential.id, agentLabel],
  );

  const handleChange = (val: string | null) => {
    setCurrentModel(val ?? '');
    handleSubmit(val);
  };

  const selectData =
    models.length > 0
      ? models.map((m) => ({ value: m.modelId, label: m.displayName }))
      : currentModel
        ? [{ value: currentModel, label: currentModel }]
        : [];

  return (
    <Box>
      <Group gap="md" align="center">
        <Text size="sm" fw={500} style={{ minWidth: 120 }}>
          {agentLabel}
        </Text>
        <Select
          placeholder="Default (runtime selects)"
          value={currentModel || null}
          onChange={handleChange}
          data={selectData}
          searchable
          clearable
          style={{ flex: 1 }}
          size="sm"
        />
      </Group>
    </Box>
  );
}

function DefaultModelSelector({ profile, agentModels }: { profile: SharedUser; agentModels: AgentModelsEntry[] }) {
  const credentials = profile.agentCredentials ?? [];
  const modelsMap = useMemo(() => {
    const m: Record<string, AgentModel[]> = {};
    for (const entry of agentModels) m[entry.agentType] = entry.models;
    return m;
  }, [agentModels]);
  if (credentials.length === 0) return null;

  return (
    <Card p={20} mt={24}>
      <Title order={5} mb={4}>
        Default Models
      </Title>
      <Text size="sm" c="dimmed" mb="md">
        Set a preferred model per agent runtime. Used when no model is specified in session or workflow step.
      </Text>
      <Stack gap={16}>
        {credentials.map((cred) => (
          <CredentialModelRow key={cred.id} credential={cred} models={modelsMap[cred.agentType] ?? []} />
        ))}
      </Stack>
    </Card>
  );
}

type AuthSessionState = 'idle' | 'starting' | 'not_started' | 'running' | 'ready' | 'finished' | 'failed';

function AgentAuthModal({
  agentType,
  opened,
  onClose,
}: {
  agentType: AgentType;
  opened: boolean;
  onClose: () => void;
}) {
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [sessionState, setSessionState] = useState<AuthSessionState>('idle');
  const [ttydUrl, setTtydUrl] = useState<string | null>(null);
  const [watcherUrl, setWatcherUrl] = useState<string | null>(null);
  const [cableStream, setCableStream] = useState<string | null>(null);
  const [authDetected, setAuthDetected] = useState(false);
  const cableSubRef = useRef<Subscription | null>(null);
  const watcherPollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const agentInfo = AVAILABLE_AGENTS.find((a) => a.type === agentType)!;

  const applySessionData = useCallback((s: Record<string, unknown>) => {
    const state = s.state as AuthSessionState;
    setSessionState(state);
    if (state === 'ready' && s.websocketUrl) {
      const base = (s.websocketUrl as string)
        .replace('wss://', 'https://')
        .replace('ws://', 'http://')
        .replace('/ws', '');
      setTtydUrl(base);
    }
    if (s.watcherUrl) setWatcherUrl(s.watcherUrl as string);
  }, []);

  const fetchSession = useCallback(
    async (id: number) => {
      try {
        const res = await apiFetch(apiV1TerminalSessionPath(id));
        if (!res.ok) return;
        const raw = await res.json();
        applySessionData(raw.data ?? raw);
      } catch {
        /* ignore */
      }
    },
    [applySessionData],
  );

  const cleanup = useCallback(() => {
    if (cableSubRef.current) {
      cableSubRef.current.unsubscribe();
      cableSubRef.current = null;
    }
    if (watcherPollRef.current) {
      clearInterval(watcherPollRef.current);
      watcherPollRef.current = null;
    }
  }, []);

  const startAuth = useCallback(async () => {
    cleanup();
    setSessionState('starting');
    setTtydUrl(null);
    setWatcherUrl(null);
    setCableStream(null);
    setAuthDetected(false);
    try {
      const res = await apiFetch(apiV1TerminalSessionsPath(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ terminalSession: { agentType, sessionType: 'auth_setup', mode: 'interactive' } }),
      });
      if (res.ok) {
        const data = await res.json();
        const s = data.data ?? data;
        const id = s.id as number;
        setSessionId(id);
        applySessionData(s);
        if (s.cableStream) setCableStream(s.cableStream as string);
      } else {
        setSessionState('failed');
      }
    } catch {
      setSessionState('failed');
    }
  }, [agentType, cleanup, applySessionData]);

  useEffect(() => {
    if (opened) startAuth();
  }, [opened, startAuth]);

  // Subscribe to Inertia Cable for session updates
  useEffect(() => {
    if (!cableStream || !sessionId) return;
    const isTerminal = sessionState === 'finished' || sessionState === 'failed';
    if (isTerminal) return;

    let cancelled = false;
    const timer = setTimeout(() => {
      if (cancelled) return;
      const consumer = getConsumer();
      cableSubRef.current = consumer.subscriptions.create(
        { channel: 'InertiaCable::StreamChannel', signed_stream_name: cableStream },
        {
          received(data: Record<string, unknown>) {
            if (data.type === 'refresh') fetchSession(sessionId);
          },
        } as unknown as Subscription,
      );
    }, 50);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      if (cableSubRef.current) {
        cableSubRef.current.unsubscribe();
        cableSubRef.current = null;
      }
    };
  }, [cableStream, sessionId, sessionState, fetchSession]);

  // Poll watcher URL to detect auth completion
  useEffect(() => {
    if (!watcherUrl || authDetected || sessionState !== 'ready') return;
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
  }, [watcherUrl, authDetected, sessionState]);

  const handleFinish = useCallback(async () => {
    if (!sessionId) return;
    try {
      await apiFetch(finishApiV1TerminalSessionPath(sessionId), { method: 'POST' });
      setSessionState('finished');
      notifications.show({ message: `${agentInfo.name} authentication saved!`, color: 'green' });
      setTimeout(() => {
        cleanup();
        onClose();
      }, 2000);
    } catch {
      notifications.show({ message: 'Failed to save authentication', color: 'red' });
    }
  }, [sessionId, agentInfo.name, cleanup, onClose]);

  const handleClose = useCallback(() => {
    cleanup();
    if (sessionId && sessionState !== 'finished' && sessionState !== 'failed') {
      apiFetch(finishApiV1TerminalSessionPath(sessionId), { method: 'POST' }).catch(() => {});
    }
    setSessionId(null);
    setSessionState('idle');
    onClose();
  }, [sessionId, sessionState, cleanup, onClose]);

  const renderContent = () => {
    if (sessionState === 'finished') {
      return (
        <Stack align="center" justify="center" h={500} gap="sm">
          <ThemeIcon size="lg" color="green" variant="light" radius="xl">
            <IconCheck size={20} />
          </ThemeIcon>
          <Text fw={500}>Authentication complete</Text>
          <Text size="xs" c="dimmed">
            Credentials saved. You can close this dialog.
          </Text>
        </Stack>
      );
    }

    if (sessionState === 'failed') {
      return (
        <Stack align="center" justify="center" h={500} gap="sm">
          <Text c="red">Authentication session failed to start.</Text>
          <Button size="xs" variant="outline" onClick={startAuth}>
            Retry
          </Button>
        </Stack>
      );
    }

    if (sessionState === 'ready' && ttydUrl) {
      return (
        <Box style={{ display: 'flex', flexDirection: 'column', height: 500 }}>
          <Box style={{ flex: 1, overflow: 'hidden' }}>
            <iframe
              src={ttydUrl}
              title={`Authenticate ${agentInfo.name}`}
              style={{ width: '100%', height: '100%', border: 'none', borderRadius: 8, backgroundColor: '#000' }}
            />
          </Box>
          <Group justify="space-between" p="sm" style={{ borderTop: '1px solid var(--mantine-color-dark-4)' }}>
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
            <Button color="green" size="sm" onClick={handleFinish} disabled={!authDetected}>
              Save Authentication
            </Button>
          </Group>
        </Box>
      );
    }

    return (
      <Stack align="center" justify="center" h={500} gap="sm">
        <Loader size="sm" />
        <Text size="sm" c="dimmed">
          Starting authentication session...
        </Text>
      </Stack>
    );
  };

  return (
    <Modal
      opened={opened}
      onClose={handleClose}
      title={
        <Group gap="sm">
          <Box style={{ width: 4, height: 24, borderRadius: 4, backgroundColor: agentInfo.color }} />
          <Text fw={600}>Authenticate {agentInfo.name}</Text>
        </Group>
      }
      size="lg"
      centered
      padding={0}
      styles={{ body: { padding: 0 } }}
    >
      {renderContent()}
    </Modal>
  );
}

function AgentRuntimesSection({ profile }: { profile: SharedUser }) {
  const configuredAgents = profile.configuredAgents ?? [];
  const credentialsMap = (profile.agentCredentials ?? []).reduce<Record<string, AgentCredential>>((acc, c) => {
    acc[c.agentType] = c;
    return acc;
  }, {});

  const [authAgent, setAuthAgent] = useState<AgentType | null>(null);
  const [opened, { open, close }] = useDisclosure(false);
  const [disconnecting, setDisconnecting] = useState<AgentType | null>(null);

  const handleAuth = (agentType: AgentType) => {
    setAuthAgent(agentType);
    open();
  };

  const handleClose = () => {
    close();
    setAuthAgent(null);
  };

  const handleDisconnect = (credential: AgentCredential) => {
    const agentName = getAgentInfo(credential.agentType as AgentType).name;
    if (!window.confirm(`Remove ${agentName} credentials? You will need to re-authenticate to use this agent.`)) return;

    setDisconnecting(credential.agentType as AgentType);
    router.delete('/profile/destroy_credential', {
      data: { agentCredentialId: credential.id },
      preserveScroll: true,
      onSuccess: () => {
        notifications.show({ message: `${agentName} credentials removed`, color: 'green' });
      },
      onError: () => {
        notifications.show({ message: 'Failed to remove credentials', color: 'red' });
      },
      onFinish: () => setDisconnecting(null),
    });
  };

  return (
    <>
      <Card p={24} mt={24}>
        <Title order={5} mb={4}>
          Agent Runtimes
        </Title>
        <Text size="sm" c="dimmed" mb="md">
          Manage authentication for AI coding agents. Authenticate new agents or re-authenticate existing ones.
        </Text>

        {AVAILABLE_AGENTS.map((agent) => {
          const isConfigured = configuredAgents.includes(agent.type);
          const credential = credentialsMap[agent.type];

          return (
            <Card key={agent.type} withBorder mb="sm" styles={{ root: { borderColor: 'var(--app-border-default)' } }}>
              <Box className={classes.agentCardContent}>
                <Box className={classes.colorBar} style={{ backgroundColor: agent.color }} />

                <Box style={{ flex: 1 }} miw={0}>
                  <Text fw={600}>{agent.name}</Text>
                  <Text size="xs" c="dimmed" lh={1.4}>
                    {agent.description}
                  </Text>
                  {isConfigured && credential && (
                    <Text size="xs" c="dimmed" mt={4}>
                      Configured {formatDate(credential.createdAt)}
                      {credential.lastUsedAt && ` · Last used ${formatDate(credential.lastUsedAt)}`}
                      {credential.expiresAt && ` · Expires ${formatDate(credential.expiresAt)}`}
                    </Text>
                  )}
                </Box>

                <Box className={classes.agentActions}>
                  {isConfigured && (
                    <Badge variant="outline" color="green" size="sm">
                      Connected
                    </Badge>
                  )}
                  <Button
                    variant={isConfigured ? 'outline' : 'filled'}
                    size="xs"
                    onClick={() => handleAuth(agent.type)}
                  >
                    {isConfigured ? 'Re-authenticate' : 'Authenticate'}
                  </Button>
                  {isConfigured && credential && (
                    <Tooltip label="Remove credentials">
                      <Button
                        variant="subtle"
                        color="red"
                        size="xs"
                        px={8}
                        loading={disconnecting === agent.type}
                        onClick={() => handleDisconnect(credential)}
                      >
                        <IconTrash size={14} />
                      </Button>
                    </Tooltip>
                  )}
                </Box>
              </Box>
            </Card>
          );
        })}
      </Card>

      {authAgent && <AgentAuthModal agentType={authAgent} opened={opened} onClose={handleClose} />}
    </>
  );
}

function ProfilePage({ profile, agentModels, cableStream }: Props) {
  useInertiaCableStream(cableStream, { only: ['profile', 'agentModels'] });

  const { data, setData, patch, processing, errors, isDirty } = useForm({
    profile: {
      name: profile.name,
      preferredAgentLanguage: profile.preferredAgentLanguage || 'en',
    },
  });

  const [clientErrors, setClientErrors] = useState<ProfileFormErrors>({});

  const isFormValid = useMemo(
    () => data.profile.name.trim().length >= 2 && !!data.profile.preferredAgentLanguage,
    [data.profile.name, data.profile.preferredAgentLanguage],
  );

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const result = profileSchema.safeParse(data.profile);
    if (!result.success) {
      const fieldErrors: ProfileFormErrors = {};
      for (const issue of result.error.issues) {
        const field = issue.path[0] as keyof ProfileFormErrors;
        if (!fieldErrors[field]) fieldErrors[field] = issue.message;
      }
      setClientErrors(fieldErrors);
      return;
    }
    setClientErrors({});
    patch('/profile', { preserveScroll: true });
  };

  if (!profile) {
    return (
      <Center mih="100vh">
        <Loader />
      </Center>
    );
  }

  const companyDisplayName = profile.company?.name ?? 'Platform Administrator';

  return (
    <AuthLayout>
      <Box maw={600} mx="auto">
        <Title order={2} fz={32} fw={600} c="var(--app-text-primary)" mb={24}>
          My Profile
        </Title>

        <Card p={24}>
          <Title order={4} mb={4}>
            Personal Information
          </Title>
          <Divider mb="md" />

          <form onSubmit={handleSubmit}>
            <Box mb="lg">
              <Box className={classes.fieldLabel}>
                <Text size="sm" fw={500} c="dimmed">
                  Email
                </Text>
                <Tooltip label="Email is managed by Google OAuth and cannot be changed">
                  <IconLock size={16} color="var(--mantine-color-dimmed)" />
                </Tooltip>
              </Box>
              <Text>{profile.email}</Text>
              <Text size="xs" c="dimmed" mt={4}>
                Email is managed by Google OAuth and cannot be changed
              </Text>
            </Box>

            <Box mb="lg">
              <TextInput
                label="Display Name"
                value={data.profile.name}
                onChange={(e) => {
                  setData('profile', { ...data.profile, name: e.currentTarget.value });
                  if (clientErrors.name) setClientErrors((prev) => ({ ...prev, name: undefined }));
                }}
                error={clientErrors.name || errors['profile.name']}
                disabled={processing}
              />
            </Box>

            <Box mb="lg">
              <Select
                label="Agent Language"
                description="Language AI agents will use to communicate with you"
                value={data.profile.preferredAgentLanguage}
                onChange={(val) => {
                  setData('profile', { ...data.profile, preferredAgentLanguage: val ?? 'en' });
                  if (clientErrors.preferredAgentLanguage)
                    setClientErrors((prev) => ({ ...prev, preferredAgentLanguage: undefined }));
                }}
                data={LANGUAGE_OPTIONS}
                disabled={processing}
                error={clientErrors.preferredAgentLanguage || errors['profile.preferredAgentLanguage']}
              />
            </Box>

            <Box mb="lg">
              <Box className={classes.fieldLabel}>
                <Text size="sm" fw={500} c="dimmed">
                  Company
                </Text>
                <Tooltip label="Company assignment is managed by administrators">
                  <IconLock size={16} color="var(--mantine-color-dimmed)" />
                </Tooltip>
              </Box>
              <Text>{companyDisplayName}</Text>
            </Box>

            <Box mb="lg">
              <Text size="sm" fw={500} c="dimmed" mb={4}>
                Role
              </Text>
              <Badge color={ROLE_COLORS[profile.role]} size="sm">
                {ROLE_LABELS[profile.role]}
              </Badge>
            </Box>

            <Button type="submit" disabled={!isDirty || !isFormValid || processing} loading={processing}>
              Save Changes
            </Button>
          </form>
        </Card>

        <DefaultAgentSelector profile={profile} />
        <DefaultModelSelector profile={profile} agentModels={agentModels} />
        <AgentRuntimesSection profile={profile} />
      </Box>
    </AuthLayout>
  );
}

export default ProfilePage;
