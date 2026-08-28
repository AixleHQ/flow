import { Deferred, Head, router, useForm } from '@inertiajs/react';
import {
  Alert,
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
  Skeleton,
  Stack,
  Switch,
  Text,
  TextInput,
  ThemeIcon,
  Title,
  Tooltip,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { type Subscription } from '@rails/actioncable';
import { IconCheck, IconDoorExit, IconLock, IconTrash } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { z } from 'zod';

import { AuthLayout } from 'layouts/AuthLayout';

import { getConsumer } from 'shared/lib/actionCableConsumer';
import { apiFetch } from 'shared/lib/apiFetch';
import { formatDateMedium } from 'shared/lib/formatDate';
import { getInitials } from 'shared/lib/getInitials';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { AwsConnectionModal } from 'shared/resources/cloud-connections/AwsConnectionModal';
import {
  apiV1CloudAwsConnectionPath,
  apiV1TerminalSessionPath,
  apiV1TerminalSessionsPath,
  companyMembershipPath,
  finishApiV1TerminalSessionPath,
  healthApiV1CloudAwsConnectionPath,
} from 'shared/routes';
import { AGENT_BRAND_COLORS, TERMINAL_BG } from 'shared/theme/vendorColors';
import { type AgentCredential, type AgentType, type SharedMembership, type SharedUser, type UserRole } from 'shared/ui';
import { StatusBadge, type StatusTone } from 'shared/ui/StatusBadge';

import { ProfileTabs } from './ProfileTabs';
import classes from './Show.module.css';
import { UsageLimitsCard, type UsageLimitsEntry } from './UsageLimitsCard';

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
    color: AGENT_BRAND_COLORS.claude_code,
  },
  {
    type: 'cursor_cli',
    name: 'Cursor CLI',
    description: 'AI-powered code editor with context-aware suggestions',
    color: AGENT_BRAND_COLORS.cursor_cli,
  },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
    color: AGENT_BRAND_COLORS.codex,
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI for code and documentation tasks",
    color: AGENT_BRAND_COLORS.gemini_cli,
  },
  {
    type: 'grok',
    name: 'Grok',
    description: "xAI's Grok CLI for agentic coding in the terminal",
    color: AGENT_BRAND_COLORS.grok,
  },
];

const ROLE_COLORS: Record<UserRole, string> = {
  super_admin: 'grape',
  admin: 'blue',
  employee: 'gray',
  viewer: 'teal',
};

const ROLE_LABELS: Record<UserRole, string> = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  employee: 'Employee',
  viewer: 'Viewer',
};

// Which login a credential auth session performs: the agent's normal login, or
// Claude's /design-login (layers a designOauth block onto an existing claude.ai login).
type AuthKind = 'agent' | 'design';

// Agent-credential connection status (derived from token expiry — agents have no
// error state). Functional labels + colour so it reads without relying on hue.
// A badge states what IS, never what to do — the action next to it is already a button
// labelled "Re-authenticate", and having both say the same thing reads as a duplicate.
const AGENT_STATUS_BADGE: Record<AgentCredential['connectionStatus'], { tone: StatusTone; label: string }> = {
  active: { tone: 'success', label: 'Connected' },
  expiring: { tone: 'warning', label: 'Expiring soon' },
  expired: { tone: 'danger', label: 'Expired' },
};

const getAgentInfo = (type: AgentType) => AVAILABLE_AGENTS.find((a) => a.type === type)!;

const profileSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters'),
  preferredAgentLanguage: z.string().min(1, 'Language is required'),
  shareActiveSessions: z.boolean(),
  shareCompletedSessions: z.boolean(),
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
  // Memberships still in the `invited` state — profile.memberships is active-only.
  // Optional: only ProfileController#show sends it.
  pendingInvitations?: SharedMembership[];
  languageOptions: string[];
  agentModels: AgentModelsEntry[];
  cableStream?: string;
  // Deferred (group "limits"): absent until Inertia's follow-up request lands.
  usageLimits?: UsageLimitsEntry[];
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
      <Text size="sm" c="dimmed">
        No agent credentials configured. Complete onboarding to set up agents.
      </Text>
    );
  }

  return (
    <Box>
      <Text size="sm" fw={500} mb={6}>
        Default Runtime
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
    </Box>
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

  // The saved pin is always an option, even when the fetched list doesn't contain it
  // (a model retired since it was chosen, a Bedrock inference-profile ARN, or a list
  // that failed to load). Mantine renders a value with no matching option as an empty
  // input, so without this the row reads as "no default set" and the next change the
  // user makes silently replaces a pin they never saw.
  const selectData = useMemo(() => {
    const options = models.map((m) => ({ value: m.modelId, label: m.displayName }));
    if (currentModel && !options.some((o) => o.value === currentModel)) {
      options.push({ value: currentModel, label: currentModel });
    }
    return options;
  }, [models, currentModel]);

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
    <Box>
      <Text size="sm" fw={500} mb={2}>
        Default Models
      </Text>
      <Text size="xs" c="dimmed" mb={10}>
        Used when no model is specified in a session or workflow step.
      </Text>
      <Stack gap={16}>
        {credentials.map((cred) => (
          <CredentialModelRow key={cred.id} credential={cred} models={modelsMap[cred.agentType] ?? []} />
        ))}
      </Stack>
    </Box>
  );
}

function AgentDefaultsSection({ profile, agentModels }: { profile: SharedUser; agentModels: AgentModelsEntry[] }) {
  return (
    <Card p={24}>
      <Title order={4} mb={4}>
        Agent Defaults
      </Title>
      <Text fz={14} c="dimmed" mb="md">
        Used when starting new sessions and as a fallback for workflow execution.
      </Text>
      <Stack gap={20}>
        <DefaultAgentSelector profile={profile} />
        <DefaultModelSelector profile={profile} agentModels={agentModels} />
      </Stack>
    </Card>
  );
}

function CompaniesSection({
  profile,
  pendingInvitations,
}: {
  profile: SharedUser;
  pendingInvitations: SharedMembership[];
}) {
  const memberships = profile.memberships ?? [];
  const [leavingId, setLeavingId] = useState<number | null>(null);

  const leaveCompany = (membership: SharedMembership) => {
    modals.openConfirmModal({
      title: 'Leave company',
      children: (
        <Text size="sm">
          Are you sure you want to leave {membership.company.name}? You will lose access to its projects and data. You
          will need a new invitation to rejoin.
        </Text>
      ),
      labels: { confirm: 'Leave company', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => {
        setLeavingId(membership.id);
        // Self-removal revokes the membership. Server-side edge cases: the
        // last-admin guard surfaces as a flash alert; leaving the last company
        // signs the user out and redirects to the login page.
        router.delete(companyMembershipPath(membership.id), {
          preserveScroll: true,
          onFinish: () => setLeavingId(null),
        });
      },
    });
  };

  return (
    <Card p={24}>
      <Title order={4} mb={4}>
        Companies
      </Title>
      <Text fz={14} c="dimmed" mb="md">
        Companies you are a member of. Company assignment is managed by administrators.
      </Text>

      {memberships.length === 0 && (
        <Text size="sm" c="dimmed">
          {profile.currentRole === 'super_admin' ? 'Platform Administrator' : 'No company memberships'}
        </Text>
      )}

      {pendingInvitations.length > 0 && (
        <>
          <Text size="sm" fw={500} mt={memberships.length === 0 ? 0 : 'lg'} mb="xs">
            Pending invitations
          </Text>
          <Text size="xs" c="dimmed" mb="sm">
            Open the link in the invitation email to accept. Invitations expire 7 days after they are sent.
          </Text>
          <Stack gap="xs" mb="md">
            {pendingInvitations.map((invitation) => (
              <Group key={invitation.id} gap="sm" wrap="nowrap" miw={0}>
                <Text fw={500} truncate>
                  {invitation.company.name}
                </Text>
                <Badge color={ROLE_COLORS[invitation.role]} size="sm" variant="light">
                  {ROLE_LABELS[invitation.role]}
                </Badge>
                <Badge color="blue" size="sm" variant="outline">
                  Invited
                </Badge>
              </Group>
            ))}
          </Stack>
        </>
      )}

      <Stack gap="sm">
        {memberships.map((membership) => (
          <Group key={membership.id} justify="space-between" wrap="nowrap">
            <Group gap="sm" wrap="nowrap" miw={0}>
              <Box className={classes.companyTile}>{getInitials(membership.company.name)}</Box>
              <Text fw={500} truncate>
                {membership.company.name}
              </Text>
              <Badge color={ROLE_COLORS[membership.role]} size="sm" variant="light">
                {ROLE_LABELS[membership.role]}
              </Badge>
              {/* Suspended members keep the membership but lose access, so the
                  row would otherwise look identical to an active one. */}
              {membership.state === 'suspended' && (
                <Badge color="orange" size="sm" variant="outline">
                  Suspended
                </Badge>
              )}
            </Group>
            <Button
              variant="subtle"
              color="red"
              size="xs"
              leftSection={<IconDoorExit size={14} />}
              loading={leavingId === membership.id}
              onClick={() => leaveCompany(membership)}
              aria-label={`Leave ${membership.company.name}`}
              style={{ flexShrink: 0 }}
            >
              Leave
            </Button>
          </Group>
        ))}
      </Stack>
    </Card>
  );
}

type AuthSessionState = 'idle' | 'starting' | 'not_started' | 'running' | 'ready' | 'finished' | 'failed';

function AgentAuthModal({
  agentType,
  authKind,
  opened,
  onClose,
}: {
  agentType: AgentType;
  authKind: AuthKind;
  opened: boolean;
  onClose: () => void;
}) {
  const isDesign = authKind === 'design';
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [sessionState, setSessionState] = useState<AuthSessionState>('idle');
  const [ttydUrl, setTtydUrl] = useState<string | null>(null);
  const [watcherUrl, setWatcherUrl] = useState<string | null>(null);
  const [cableStream, setCableStream] = useState<string | null>(null);
  const [authDetected, setAuthDetected] = useState(false);
  // Bedrock writes no auth file, so `authDetected` stays false forever on that path — the
  // signal that the user chose it is the credential helper asking us for credentials.
  const [cloudRequested, setCloudRequested] = useState(false);
  const [cloudConnected, setCloudConnected] = useState(false);
  const [finishError, setFinishError] = useState(false);
  const cableSubRef = useRef<Subscription | null>(null);
  const watcherPollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const finishingRef = useRef(false);
  // One auth session per opening. The app renders under StrictMode, which invokes effects
  // twice, and this effect POSTs — without the guard a single click launched two agent
  // containers, each holding a session that authenticates the same credential.
  const startedRef = useRef(false);

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
    // Set once the in-container credential helper reported no cloud connection, which only
    // happens because Claude Code's own Bedrock wizard asked it for credentials.
    if (s.cloudConnectRequested) setCloudRequested(true);
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
    setFinishError(false);
    finishingRef.current = false;
    try {
      const res = await apiFetch(apiV1TerminalSessionsPath(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          terminalSession: {
            agentType,
            sessionType: 'auth_setup',
            mode: 'interactive',
            ...(isDesign ? { authKind: 'design' } : {}),
          },
        }),
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
  }, [agentType, isDesign, cleanup, applySessionData]);

  useEffect(() => {
    if (!opened) {
      startedRef.current = false;
      return;
    }
    if (startedRef.current) return;
    startedRef.current = true;
    startAuth();
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
    if (!sessionId || finishingRef.current) return;
    finishingRef.current = true;
    setFinishError(false);
    try {
      await apiFetch(finishApiV1TerminalSessionPath(sessionId), { method: 'POST' });
      setSessionState('finished');
      notifications.show({ message: `${agentInfo.name} authentication saved!`, color: 'green' });
      setTimeout(() => {
        cleanup();
        onClose();
      }, 2000);
    } catch {
      finishingRef.current = false;
      setFinishError(true);
      notifications.show({ message: 'Failed to save authentication', color: 'red' });
    }
  }, [sessionId, agentInfo.name, cleanup, onClose]);

  // Auto-finish as soon as the watcher confirms credentials exist — no manual
  // "save" step. The watcher only reports authenticated once a real token is
  // written, and the server persists the credential during cleanup.
  useEffect(() => {
    if (authDetected && sessionState === 'ready') handleFinish();
  }, [authDetected, sessionState, handleFinish]);

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
          <Text c="var(--app-danger-fg)">Authentication session failed to start.</Text>
          <Button size="xs" variant="outline" onClick={startAuth}>
            Retry
          </Button>
        </Stack>
      );
    }

    // The wizard's credential helper is blocking while it waits, so completing this form is
    // what lets its verification pass on the first attempt instead of reporting a
    // credential error the user has to click past. The terminal stays visible below.
    if (cloudRequested && !cloudConnected) {
      return (
        <Stack p="md" gap="md" mah={620} style={{ overflowY: 'auto' }}>
          <Alert color="blue">
            You picked Amazon Bedrock in the terminal. Connect the AWS account to bill it, and the terminal will
            continue on its own.
          </Alert>
          <AwsConnectionModal
            embedded
            opened
            onClose={() => setCloudRequested(false)}
            onConnected={() => {
              setCloudConnected(true);
              notifications.show({ message: 'AWS connected — the terminal will continue', color: 'green' });
            }}
          />
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
              allow="clipboard-read; clipboard-write"
              style={{ width: '100%', height: '100%', border: 'none', borderRadius: 8, backgroundColor: TERMINAL_BG }}
            />
          </Box>
          <Group justify="space-between" p="sm" style={{ borderTop: '1px solid var(--app-border-default)' }}>
            {authDetected && finishError ? (
              <>
                <Text size="xs" c="var(--app-danger-fg)">
                  Couldn&apos;t save credentials.
                </Text>
                <Button color="green" size="xs" onClick={handleFinish}>
                  Retry
                </Button>
              </>
            ) : authDetected ? (
              <Group gap="xs">
                <Loader size="xs" color="green" />
                <Text size="xs" c="var(--app-success-fg)" fw={500}>
                  Credentials detected — saving…
                </Text>
              </Group>
            ) : (
              <Text size="xs" c="dimmed">
                {isDesign
                  ? 'Approve the design login in your browser'
                  : 'Complete authentication in the terminal above'}
              </Text>
            )}
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
          <Text fw={600}>{isDesign ? `Connect Design for ${agentInfo.name}` : `Authenticate ${agentInfo.name}`}</Text>
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
  const [authKind, setAuthKind] = useState<AuthKind>('agent');
  const [opened, { open, close }] = useDisclosure(false);
  const [disconnecting, setDisconnecting] = useState<AgentType | null>(null);

  // The AWS connection is not part of the Inertia profile payload, so read it directly.
  // It is deliberately independent of whether Claude itself is configured: a user may
  // bill everything to their own Bedrock account without ever holding a Claude login.
  const [awsState, setAwsState] = useState<{
    connected: boolean;
    reason?: string | null;
    accountId?: string | null;
    roleName?: string | null;
    region?: string | null;
  } | null>(null);
  const [awsTesting, setAwsTesting] = useState(false);
  const awsConnected = awsState?.connected ?? null;
  const hasAwsConnection = awsState !== null && (awsState.connected || Boolean(awsState.reason));

  const loadAwsConnection = useCallback(async () => {
    try {
      const res = await apiFetch(apiV1CloudAwsConnectionPath());
      if (!res.ok) return;
      const body = await res.json();
      setAwsState({
        connected: Boolean(body.connected),
        reason: body.reason ?? null,
        accountId: body.account_id ?? null,
        roleName: body.role_name ?? null,
        region: body.region ?? null,
      });
    } catch {
      // A profile page must still render when this probe fails.
    }
  }, []);

  // Claude Code hides Bedrock errors, so a broken connection otherwise shows up as an
  // agent that never answers. This surfaces the provider's own wording instead.
  const testAwsConnection = useCallback(async () => {
    setAwsTesting(true);
    try {
      const res = await apiFetch(healthApiV1CloudAwsConnectionPath(), { method: 'POST' });
      const body = await res.json();
      if (body.ok) {
        notifications.show({ message: `AWS Bedrock reachable (${body.model_id})`, color: 'green' });
      } else {
        notifications.show({
          title: body.stage === 'credentials' ? 'Credentials failed' : 'Bedrock rejected the request',
          message: body.error_message ?? body.error_code ?? 'Unknown failure',
          color: 'red',
          autoClose: false,
        });
      }
      void loadAwsConnection();
    } catch {
      notifications.show({ message: 'Could not run the connection test', color: 'red' });
    } finally {
      setAwsTesting(false);
    }
  }, [loadAwsConnection]);

  useEffect(() => {
    void loadAwsConnection();
  }, [loadAwsConnection]);

  // A session-start preflight CTA navigates here with ?authenticate=claude_code. Open the
  // AUTH modal, not a separate cloud one: the user reconnects the same way they connected
  // in the first place — by picking Amazon Bedrock in Claude Code's own wizard.
  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get('authenticate');
    if (requested === 'claude_code') {
      setAuthAgent('claude_code');
      setAuthKind('agent');
      open();
    }
  }, [open]);

  const handleAuth = (agentType: AgentType, kind: AuthKind = 'agent') => {
    setAuthAgent(agentType);
    setAuthKind(kind);
    open();
  };

  const handleClose = () => {
    close();
    setAuthAgent(null);
    setAuthKind('agent');
  };

  const handleDisconnect = (credential: AgentCredential) => {
    const agentName = getAgentInfo(credential.agentType as AgentType).name;
    modals.openConfirmModal({
      title: `Remove ${agentName} credentials`,
      children: (
        <Text size="sm">
          You will need to re-authenticate before this agent can run again. Sessions already running are unaffected.
        </Text>
      ),
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => doDisconnect(credential, agentName),
    });
  };

  const doDisconnect = (credential: AgentCredential, agentName: string) => {
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
      <Card p={24}>
        <Title order={5} mb={4}>
          Agent Runtimes
        </Title>
        <Text size="sm" c="dimmed" mb="md">
          Manage authentication for AI coding agents in this company. Each company needs its own sign-in, so its agent
          usage is billed to it and never shared with your other companies.
        </Text>

        {AVAILABLE_AGENTS.map((agent) => {
          const isConfigured = configuredAgents.includes(agent.type);
          const credential = credentialsMap[agent.type];

          return (
            <Card key={agent.type} withBorder mb="sm" styles={{ root: { borderColor: 'var(--app-border-default)' } }}>
              <Box className={classes.agentCardContent}>
                <Box className={classes.colorBar} style={{ backgroundColor: agent.color }} />

                <Box className={classes.agentCardBody}>
                  <Text fw={600}>{agent.name}</Text>
                  <Text size="xs" c="dimmed" lh={1.4}>
                    {agent.description}
                  </Text>
                  {isConfigured && credential && (
                    <Text size="xs" c="dimmed" mt={4}>
                      Configured {formatDateMedium(credential.createdAt)}
                      {credential.lastUsedAt && ` · Last used ${formatDateMedium(credential.lastUsedAt)}`}
                      {credential.expiresAt && ` · Expires ${formatDateMedium(credential.expiresAt)}`}
                    </Text>
                  )}
                  {/* Billing target lives in the card body, not among the action buttons: it is
                      a sentence about whether this agent can run, and the one question it has
                      to answer is "will it work". */}
                  {agent.type === 'claude_code' && hasAwsConnection && (
                    <Group gap={6} mt={6} wrap="wrap">
                      <Text size="xs" c={awsConnected ? 'var(--app-success-fg)' : 'var(--app-danger-fg)'} fw={500}>
                        {awsConnected ? 'Billing to your AWS' : 'AWS needs reconnecting'}
                      </Text>
                      {awsState?.accountId && (
                        <Text size="xs" c="dimmed">
                          · {awsState.accountId}
                          {awsState.roleName && ` / ${awsState.roleName}`}
                          {awsState.region && ` · ${awsState.region}`}
                        </Text>
                      )}
                      {!awsConnected && awsState?.reason && (
                        <Text size="xs" c="dimmed">
                          · {awsState.reason.replace(/_/g, ' ')}
                        </Text>
                      )}
                      <Button
                        variant="transparent"
                        size="compact-xs"
                        px={0}
                        loading={awsTesting}
                        onClick={() => void testAwsConnection()}
                      >
                        Test
                      </Button>
                    </Group>
                  )}
                </Box>

                <Box className={classes.agentActions}>
                  {isConfigured && credential && (
                    <StatusBadge tone={AGENT_STATUS_BADGE[credential.connectionStatus].tone} size="sm">
                      {AGENT_STATUS_BADGE[credential.connectionStatus].label}
                    </StatusBadge>
                  )}
                  {agent.type === 'codex' ? (
                    <Button
                      component="a"
                      href="/auth/codex/authorize"
                      variant={isConfigured ? 'outline' : 'filled'}
                      size="xs"
                    >
                      {isConfigured ? 'Re-authenticate' : 'Authenticate'}
                    </Button>
                  ) : (
                    <Button
                      variant={isConfigured ? 'outline' : 'filled'}
                      size="xs"
                      onClick={() => handleAuth(agent.type)}
                    >
                      {isConfigured ? 'Re-authenticate' : 'Authenticate'}
                    </Button>
                  )}
                  {/* Design login layers a `designOauth` block onto an existing Claude login. It works
                      on either base (claude.ai OR the Console managed key), so offer it once any base
                      login exists. */}
                  {isConfigured &&
                    credential &&
                    agent.type === 'claude_code' &&
                    (credential.configKeys.includes('claudeAiOauth') ||
                      credential.configKeys.includes('primaryApiKey')) && (
                      <Button variant="light" size="xs" onClick={() => handleAuth(agent.type, 'design')}>
                        {credential.configKeys.includes('designOauth') ? 'Reconnect Design' : 'Connect Design'}
                      </Button>
                    )}
                  {/* No separate "Connect AWS" entry point, and no AWS status here: the user
                      declares that intent by picking Amazon Bedrock inside Claude Code's own
                      login wizard, and the billing target is a sentence in the card body
                      rather than another chip competing with the login actions. */}
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

      {authAgent && <AgentAuthModal agentType={authAgent} authKind={authKind} opened={opened} onClose={handleClose} />}
    </>
  );
}

function ProfilePage({ profile, pendingInvitations, agentModels, cableStream, usageLimits }: Props) {
  const currentCompanyName = profile.currentCompany?.name ?? null;
  useInertiaCableStream(cableStream, { only: ['profile', 'agent_models'] });

  const { data, setData, patch, processing, errors, isDirty } = useForm({
    profile: {
      name: profile.name,
      preferredAgentLanguage: profile.preferredAgentLanguage || 'en',
      shareActiveSessions: profile.shareActiveSessions,
      shareCompletedSessions: profile.shareCompletedSessions,
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

  return (
    <AuthLayout>
      <Head title="My Profile" />
      <Box maw={1120} mx="auto">
        <Title order={1} fz={28} fw={600} c="var(--app-text-primary)" mb={4}>
          My Profile
        </Title>
        {/* Agents, the agent language and usage are all PER COMPANY — a separate
            credential per company is what keeps vendor billing from pooling. Say
            so up front, or the page reads as one shared set of agents. */}
        {currentCompanyName && (
          <Text size="sm" c="dimmed" mb={24}>
            Settings for <strong>{currentCompanyName}</strong>. Your agents and agent language are set per company —
            switch company to see or change another one.
          </Text>
        )}

        <ProfileTabs active="account" />

        <Box className={classes.grid2}>
          {/* Main column: personal information, agent runtimes. */}
          <Box className={classes.colMain}>
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
                    description="Language AI agents will use to communicate with you in this company"
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

                {/* Sharing is per lifecycle phase because the two are not the same
                    favour: a finished log is a record someone can read later, while
                    a running session is an interactive shell in the container the
                    agent is working in. Unchecked means nobody else can open it —
                    admins included. */}
                <Box mb="lg">
                  <Text size="sm" fw={500} mb={4}>
                    Session visibility
                  </Text>
                  <Text size="xs" c="dimmed" mb="sm">
                    Controls what other members of your projects can open. Your own sessions are always visible to you.
                  </Text>
                  <Stack gap="sm">
                    <Switch
                      label="Show my active sessions"
                      description="Project members can watch a running session — live terminal and editor"
                      checked={data.profile.shareActiveSessions}
                      onChange={(e) =>
                        setData('profile', { ...data.profile, shareActiveSessions: e.currentTarget.checked })
                      }
                      disabled={processing}
                    />
                    <Switch
                      label="Show my finished sessions"
                      description="Project members can open a finished session and replay its log"
                      checked={data.profile.shareCompletedSessions}
                      onChange={(e) =>
                        setData('profile', { ...data.profile, shareCompletedSessions: e.currentTarget.checked })
                      }
                      disabled={processing}
                    />
                  </Stack>
                </Box>

                <Button type="submit" disabled={!isDirty || !isFormValid || processing} loading={processing}>
                  Save Changes
                </Button>
              </form>
            </Card>

            <AgentRuntimesSection profile={profile} />
            {/* Deferred: reads the vendor's usage endpoint, so it must not hold up the page. */}
            <Deferred data="usageLimits" fallback={<Skeleton height={180} radius="sm" />}>
              <UsageLimitsCard entries={usageLimits ?? []} />
            </Deferred>
          </Box>

          {/* Side column: companies, agent defaults. */}
          <Box className={classes.colSide}>
            <CompaniesSection profile={profile} pendingInvitations={pendingInvitations ?? []} />
            <AgentDefaultsSection profile={profile} agentModels={agentModels} />
          </Box>
        </Box>
      </Box>
    </AuthLayout>
  );
}

export default ProfilePage;
