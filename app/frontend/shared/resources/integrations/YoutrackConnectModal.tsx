import { router } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Checkbox,
  Code,
  Divider,
  Group,
  Loader,
  Modal,
  MultiSelect,
  PasswordInput,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { CopyValue } from './CopyValue';
import { requestJson as requestTrackerJson } from './requestJson';

export interface YoutrackProps {
  enabled: boolean;
}

interface YoutrackProject {
  id: string;
  key: string;
  name: string;
}

interface Inspection {
  base_url: string;
  identity: { id: string; login: string; name: string };
  projects: YoutrackProject[];
}

interface ProjectWebhook {
  scopeId: string;
  key: string | null;
  name: string | null;
  url: string;
  header: string;
  token: string;
  status: string;
  lastEventAt: string | null;
}

const DOCS_URL = '/docs/youtrack';
const MIN_TOKEN = 32;

const requestJson = (url: string, init: RequestInit = {}) =>
  requestTrackerJson(url, init, 'YouTrack rejected the request');

const projectOptions = (projects: YoutrackProject[]) =>
  projects.map((p) => ({ value: p.id, label: `${p.name} (${p.key})` }));

const DEDICATED_LABEL = 'This YouTrack account is kept for Aixle';
const DEDICATED_DESCRIPTION =
  'Then Aixle recognises its own changes and @mentions of the account. Leave it off for a personal account.';

interface ConnectProps {
  opened: boolean;
  onClose: () => void;
  basePath: string;
}

export const YoutrackConnectModal = ({ opened, onClose, basePath }: ConnectProps) => {
  const [baseUrl, setBaseUrl] = useState('');
  const [token, setToken] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [dedicated, setDedicated] = useState(false);
  const [checking, setChecking] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => {
    onClose();
    setBaseUrl('');
    setToken('');
    setInspection(null);
    setProjectIds([]);
    setDedicated(false);
    setError(null);
  }, [onClose]);
  const requestClose = useConfirmClose(baseUrl !== '' || token !== '' || projectIds.length > 0, close);

  const check = useCallback(async () => {
    setError(null);
    setChecking(true);
    try {
      const result = (await requestJson(`${basePath}/youtrack_inspect`, {
        method: 'POST',
        body: JSON.stringify({ base_url: baseUrl.trim(), permanent_token: token.trim() }),
      })) as Inspection;
      setInspection(result);
      setProjectIds([]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reach YouTrack');
    } finally {
      setChecking(false);
    }
  }, [baseUrl, basePath, token]);

  const connect = useCallback(() => {
    if (!inspection) return;
    setConnecting(true);
    router.post(
      basePath,
      {
        provider: 'youtrack',
        baseUrl: inspection.base_url,
        permanentToken: token.trim(),
        projectIds,
        dedicatedIdentity: dedicated,
      },
      {
        preserveScroll: true,
        onSuccess: close,
        onError: () => notifications.show({ message: 'Failed to connect YouTrack', color: 'red' }),
        onFinish: () => setConnecting(false),
      },
    );
  }, [basePath, close, dedicated, inspection, projectIds, token]);

  const editCredentials = (apply: () => void) => {
    apply();
    setInspection(null);
  };

  return (
    <Modal opened={opened} onClose={requestClose} title="Connect YouTrack" size="lg">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Create a permanent token in YouTrack under your profile → Account Security, best of an account kept for Aixle:
          Aixle acts as the token&apos;s owner. YouTrack Cloud and self-hosted YouTrack 2026.2 or later both work. See
          the <Anchor href={DOCS_URL}>YouTrack guide</Anchor>.
        </Text>
        <TextInput
          label="YouTrack URL"
          placeholder="https://acme.youtrack.cloud"
          value={baseUrl}
          onChange={(e) => {
            const value = e.currentTarget.value;
            editCredentials(() => setBaseUrl(value));
          }}
        />
        <PasswordInput
          label="Permanent token"
          value={token}
          onChange={(e) => {
            const value = e.currentTarget.value;
            editCredentials(() => setToken(value));
          }}
        />
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {inspection && (
          <>
            <Alert color="green" icon={<IconCheck size={16} />}>
              Signed in to {inspection.base_url} as {inspection.identity.name} (@{inspection.identity.login}).
            </Alert>
            <MultiSelect
              label="YouTrack projects"
              description="Each one becomes a tracker in this project."
              data={projectOptions(inspection.projects)}
              value={projectIds}
              onChange={setProjectIds}
              searchable
            />
            <Checkbox
              label={DEDICATED_LABEL}
              description={DEDICATED_DESCRIPTION}
              checked={dedicated}
              onChange={(e) => setDedicated(e.currentTarget.checked)}
            />
          </>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={requestClose}>
            Cancel
          </Button>
          {inspection ? (
            <Button onClick={connect} loading={connecting} disabled={projectIds.length === 0}>
              Connect
            </Button>
          ) : (
            <Button onClick={check} loading={checking} disabled={!baseUrl.trim() || !token.trim()}>
              Check
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
};

interface IntegrationModalProps {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

// Changes which YouTrack projects a connection covers, and whether its account is kept for Aixle.
export const YoutrackProjectsModal = ({ integration, onClose, basePath }: IntegrationModalProps) => {
  const [projects, setProjects] = useState<YoutrackProject[] | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [dedicated, setDedicated] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setProjects(null);
    setError(null);
    setProjectIds(integration.youtrackProjects.map((p) => p.id));
    setDedicated(integration.youtrackDedicatedIdentity);
    requestJson(`${basePath}/${integration.id}/youtrack_projects`, { method: 'GET' })
      .then((result) => !cancelled && setProjects(result.projects as YoutrackProject[]))
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not list the YouTrack projects'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  const covered = integration?.youtrackProjects.map((p) => p.id) ?? [];
  const dirty =
    !!integration &&
    (dedicated !== integration.youtrackDedicatedIdentity ||
      projectIds.length !== covered.length ||
      projectIds.some((id) => !covered.includes(id)));
  const requestClose = useConfirmClose(dirty, onClose);

  const save = useCallback(() => {
    if (!integration) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      { projectIds, dedicatedIdentity: dedicated },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to save the YouTrack projects', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [basePath, dedicated, integration, onClose, projectIds]);

  return (
    <Modal opened={!!integration} onClose={requestClose} title="YouTrack projects" size="lg">
      <Stack gap="md">
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {projects === null && !error && <Loader size="sm" aria-label="Loading projects" />}
        {projects && (
          <MultiSelect
            label="YouTrack projects"
            description="Each one becomes a tracker in this project. A project you remove is detached."
            data={projectOptions(projects)}
            value={projectIds}
            onChange={setProjectIds}
            searchable
          />
        )}
        <Checkbox
          label={DEDICATED_LABEL}
          description={DEDICATED_DESCRIPTION}
          checked={dedicated}
          onChange={(e) => setDedicated(e.currentTarget.checked)}
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={requestClose}>
            Cancel
          </Button>
          <Button onClick={save} loading={saving} disabled={!projects || projectIds.length === 0}>
            Save
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};

const Field = ({ label, value, secret = false }: { label: string; value: string; secret?: boolean }) => (
  <Stack gap={2}>
    <Text size="xs" fw={600}>
      {label}
    </Text>
    <Group gap={4} wrap="nowrap">
      {secret ? (
        <PasswordInput value={value} readOnly aria-label={label} style={{ flex: 1 }} />
      ) : (
        <Code style={{ wordBreak: 'break-all' }}>{value}</Code>
      )}
      <CopyValue label={label} value={value} />
    </Group>
  </Stack>
);

// The app holds one token per YouTrack project, shared by every URL it posts
// to, so a project that already uses the app keeps its token and it is entered here.
const ProjectWebhookSetup = ({
  webhook,
  onSaved,
  saveUrl,
}: {
  webhook: ProjectWebhook;
  onSaved: (webhook: ProjectWebhook) => void;
  saveUrl: string;
}) => {
  const [editing, setEditing] = useState(false);
  const [token, setToken] = useState('');
  const [header, setHeader] = useState(webhook.header);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const result = (await requestJson(saveUrl, {
        method: 'PATCH',
        body: JSON.stringify({ scope_id: webhook.scopeId, token: token.trim(), header: header.trim() }),
      })) as ProjectWebhook;
      onSaved(result);
      setEditing(false);
      setToken('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the token');
    } finally {
      setSaving(false);
    }
  };

  const title = webhook.key ? `${webhook.name ?? webhook.key} (${webhook.key})` : webhook.scopeId;

  return (
    <Stack gap="xs">
      <Group justify="space-between">
        <Text fw={600} size="sm">
          {title}
        </Text>
        {webhook.lastEventAt ? (
          <Badge color="green" variant="light">
            Last event {new Date(webhook.lastEventAt).toLocaleString()}
          </Badge>
        ) : (
          <Badge color="gray" variant="light">
            No event yet
          </Badge>
        )}
      </Group>
      <Field label={`URL for ${webhook.key ?? webhook.scopeId}`} value={webhook.url} />
      <Field label={`Header name for ${webhook.key ?? webhook.scopeId}`} value={webhook.header} />
      <Field label={`Token for ${webhook.key ?? webhook.scopeId}`} value={webhook.token} secret />
      {editing ? (
        <Stack gap="xs">
          <PasswordInput
            label="The token this project's app already uses"
            description={`At least ${MIN_TOKEN} characters. Aixle then expects it instead of its own.`}
            value={token}
            onChange={(e) => setToken(e.currentTarget.value)}
          />
          <TextInput label="Header name" value={header} onChange={(e) => setHeader(e.currentTarget.value)} />
          {error && (
            <Alert color="red" icon={<IconAlertCircle size={16} />}>
              {error}
            </Alert>
          )}
          <Group justify="flex-end" gap="xs">
            <Button variant="default" size="xs" onClick={() => setEditing(false)}>
              Cancel
            </Button>
            <Button size="xs" onClick={save} loading={saving} disabled={token.trim().length < MIN_TOKEN}>
              Save token
            </Button>
          </Group>
        </Stack>
      ) : (
        <Anchor size="xs" component="button" type="button" onClick={() => setEditing(true)}>
          This project&apos;s app already has a token
        </Anchor>
      )}
    </Stack>
  );
};

// What a YouTrack project admin enters in each project's Webhook Triggers app.
export const YoutrackWebhookModal = ({ integration, onClose, basePath }: IntegrationModalProps) => {
  const [webhooks, setWebhooks] = useState<ProjectWebhook[] | null>(null);
  const [events, setEvents] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setWebhooks(null);
    setError(null);
    requestJson(`${basePath}/${integration.id}/youtrack_webhook`, { method: 'GET' })
      .then((result) => {
        if (cancelled) return;
        setWebhooks(result.projects as ProjectWebhook[]);
        setEvents(result.events as string[]);
      })
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not load the webhook settings'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  const replace = (saved: ProjectWebhook) =>
    setWebhooks((current) => current?.map((w) => (w.scopeId === saved.scopeId ? saved : w)) ?? null);

  return (
    <Modal opened={!!integration} onClose={onClose} title="YouTrack webhooks" size="lg">
      <Stack gap="sm">
        <Text size="sm">
          Tracker triggers need YouTrack to send its events here. In each project, a project admin installs
          JetBrains&apos; <b>Webhook Triggers</b> app, opens the project&apos;s <b>Apps → Webhook Triggers</b> settings,
          and enters the token, the header name and the URL below
          {events.length > 0 ? ` — as an All Events URL, or for ${events.join(', ')}` : ''}.
        </Text>
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {!webhooks && !error && <Loader size="sm" aria-label="Loading webhook settings" />}
        {webhooks?.map((webhook, index) => (
          <Stack key={webhook.scopeId} gap="sm">
            {index > 0 && <Divider />}
            <ProjectWebhookSetup
              webhook={webhook}
              onSaved={replace}
              saveUrl={`${basePath}/${integration?.id}/youtrack_webhook_token`}
            />
          </Stack>
        ))}
        <Group justify="flex-end">
          <Button onClick={onClose}>Done</Button>
        </Group>
      </Stack>
    </Modal>
  );
};
