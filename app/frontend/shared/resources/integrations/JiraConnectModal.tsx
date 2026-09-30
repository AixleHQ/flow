import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Alert,
  Anchor,
  Button,
  Checkbox,
  Code,
  CopyButton,
  Group,
  Loader,
  Modal,
  MultiSelect,
  PasswordInput,
  SegmentedControl,
  Select,
  Stack,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck, IconCopy } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

export interface JiraProps {
  oauthEnabled: boolean;
}

interface JiraProject {
  id: string;
  key: string;
  name: string;
}

interface Inspection {
  site: { id: string; name: string; url: string };
  identity: { id: string; name: string };
  projects: JiraProject[];
}

interface WebhookSetup {
  url: string;
  secret: string;
  events: string[];
  jql: string | null;
  lastEventAt: string | null;
}

const DOCS_URL = '/docs/jira';

// JSON rather than an Inertia visit: the dialogs keep their state between steps.
const requestJson = async (url: string, init: RequestInit = {}) => {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
  const response = await fetch(url, {
    ...init,
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, Accept: 'application/json' },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || 'Jira rejected the request');
  return payload;
};

const projectOptions = (projects: JiraProject[]) =>
  projects.map((p) => ({ value: p.id, label: `${p.name} (${p.key})` }));

interface ConnectProps {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  jira: JiraProps;
}

export const JiraConnectModal = ({ opened, onClose, basePath, jira }: ConnectProps) => {
  const [mode, setMode] = useState<'oauth' | 'service_account'>(jira.oauthEnabled ? 'oauth' : 'service_account');
  const [siteUrl, setSiteUrl] = useState('');
  const [clientId, setClientId] = useState('');
  const [clientSecret, setClientSecret] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [checking, setChecking] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => {
    onClose();
    setSiteUrl('');
    setClientId('');
    setClientSecret('');
    setInspection(null);
    setProjectIds([]);
    setError(null);
  }, [onClose]);

  const check = useCallback(async () => {
    setError(null);
    setChecking(true);
    try {
      const result = (await requestJson(`${basePath}/jira_inspect`, {
        method: 'POST',
        body: JSON.stringify({
          site_url: siteUrl.trim(),
          client_id: clientId.trim(),
          client_secret: clientSecret.trim(),
        }),
      })) as Inspection;
      setInspection(result);
      setProjectIds([]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reach Jira');
    } finally {
      setChecking(false);
    }
  }, [basePath, clientId, clientSecret, siteUrl]);

  const connect = useCallback(() => {
    setConnecting(true);
    router.post(
      basePath,
      {
        provider: 'jira',
        siteUrl: siteUrl.trim(),
        clientId: clientId.trim(),
        clientSecret: clientSecret.trim(),
        projectIds,
      },
      {
        preserveScroll: true,
        onSuccess: close,
        onError: () => notifications.show({ message: 'Failed to connect Jira', color: 'red' }),
        onFinish: () => setConnecting(false),
      },
    );
  }, [basePath, clientId, clientSecret, close, projectIds, siteUrl]);

  return (
    <Modal opened={opened} onClose={close} title="Connect Jira" size="lg">
      <Stack gap="md">
        {jira.oauthEnabled && (
          <SegmentedControl
            value={mode}
            onChange={(value) => setMode(value as typeof mode)}
            data={[
              { label: 'Atlassian account', value: 'oauth' },
              { label: 'Service account', value: 'service_account' },
            ]}
          />
        )}

        {mode === 'oauth' ? (
          <>
            <Text size="sm">
              You sign in at Atlassian, pick the site, then choose which Jira projects to connect. Aixle acts as the
              account you sign in with — use an account kept for Aixle if its changes should not appear as yours.
            </Text>
            <Group justify="flex-end">
              <Button variant="default" onClick={close}>
                Cancel
              </Button>
              <Button component="a" href={`${basePath}/jira_oauth_start`}>
                Continue to Atlassian
              </Button>
            </Group>
          </>
        ) : (
          <>
            <Text size="sm" c="dimmed">
              An Atlassian organization admin creates a service account and an OAuth 2.0 credential for it, with the
              scopes listed in the <Anchor href={DOCS_URL}>Jira guide</Anchor>. Aixle acts as that service account.
            </Text>
            <TextInput
              label="Jira site"
              placeholder="your-team.atlassian.net"
              value={siteUrl}
              onChange={(e) => setSiteUrl(e.currentTarget.value)}
            />
            <TextInput label="Client ID" value={clientId} onChange={(e) => setClientId(e.currentTarget.value)} />
            <PasswordInput
              label="Client secret"
              value={clientSecret}
              onChange={(e) => setClientSecret(e.currentTarget.value)}
            />
            {error && (
              <Alert color="red" icon={<IconAlertCircle size={16} />}>
                {error}
              </Alert>
            )}
            {inspection && (
              <>
                <Alert color="green" icon={<IconCheck size={16} />}>
                  Signed in to {inspection.site.name} as {inspection.identity.name}.
                </Alert>
                <MultiSelect
                  label="Jira projects"
                  description="Each one becomes a tracker in this project."
                  data={projectOptions(inspection.projects)}
                  value={projectIds}
                  onChange={setProjectIds}
                  searchable
                />
              </>
            )}
            <Group justify="flex-end">
              <Button variant="default" onClick={close}>
                Cancel
              </Button>
              {inspection ? (
                <Button onClick={connect} loading={connecting} disabled={projectIds.length === 0}>
                  Connect
                </Button>
              ) : (
                <Button
                  onClick={check}
                  loading={checking}
                  disabled={!siteUrl.trim() || !clientId.trim() || !clientSecret.trim()}
                >
                  Check
                </Button>
              )}
            </Group>
          </>
        )}
      </Stack>
    </Modal>
  );
};

interface ProjectsProps {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

// Finishes a connection made through the Atlassian app, or changes which
// projects a connection covers.
export const JiraProjectsModal = ({ integration, onClose, basePath }: ProjectsProps) => {
  const sites = integration?.jiraSites ?? [];
  const pickSite = integration?.status === 'inactive' && sites.length > 1;
  const [cloudId, setCloudId] = useState<string | null>(null);
  const [projects, setProjects] = useState<JiraProject[] | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [dedicated, setDedicated] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!integration) return;
    setCloudId(null);
    setProjects(null);
    setError(null);
    setProjectIds(integration.jiraProjects.map((p) => p.id));
    setDedicated(integration.jiraDedicatedIdentity);
  }, [integration]);

  useEffect(() => {
    if (!integration || (pickSite && !cloudId)) return;
    let cancelled = false;
    const query = cloudId ? `?cloud_id=${encodeURIComponent(cloudId)}` : '';
    requestJson(`${basePath}/${integration.id}/jira_projects${query}`, { method: 'GET' })
      .then((result) => !cancelled && setProjects(result.projects as JiraProject[]))
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not list the Jira projects'));
    return () => {
      cancelled = true;
    };
  }, [basePath, cloudId, integration, pickSite]);

  const save = useCallback(() => {
    if (!integration) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      {
        projectIds,
        ...(cloudId ? { cloudId } : {}),
        ...(integration.jiraAuthMode === 'oauth' ? { dedicatedIdentity: dedicated } : {}),
      },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to save the Jira projects', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [basePath, cloudId, dedicated, integration, onClose, projectIds]);

  return (
    <Modal opened={!!integration} onClose={onClose} title="Jira projects" size="lg">
      <Stack gap="md">
        {pickSite && (
          <Select
            label="Jira site"
            data={sites.map((s) => ({ value: s.id, label: `${s.name} (${s.url})` }))}
            value={cloudId}
            onChange={(value) => {
              setCloudId(value);
              setProjects(null);
              setProjectIds([]);
            }}
          />
        )}
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {projects === null && !error && (!pickSite || cloudId) && <Loader size="sm" aria-label="Loading projects" />}
        {projects && (
          <MultiSelect
            label="Jira projects"
            description="Each one becomes a tracker in this project. A project you remove is detached."
            data={projectOptions(projects)}
            value={projectIds}
            onChange={setProjectIds}
            searchable
          />
        )}
        {integration?.jiraAuthMode === 'oauth' && (
          <Checkbox
            label="This Atlassian account is kept for Aixle"
            description="Then Aixle recognises its own changes and @mentions of the account. Leave it off if you signed in as yourself."
            checked={dedicated}
            onChange={(e) => setDedicated(e.currentTarget.checked)}
          />
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
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

interface WebhookProps {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

const CopyValue = ({ label, value }: { label: string; value: string }) => (
  <CopyButton value={value}>
    {({ copied, copy }) => (
      <Tooltip label={copied ? 'Copied' : `Copy ${label.toLowerCase()}`}>
        <ActionIcon aria-label={`Copy ${label.toLowerCase()}`} variant="subtle" size="sm" color="gray" onClick={copy}>
          {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
        </ActionIcon>
      </Tooltip>
    )}
  </CopyButton>
);

// A service account cannot register webhooks, so a Jira admin adds one by hand.
export const JiraWebhookModal = ({ integration, onClose, basePath }: WebhookProps) => {
  const [setup, setSetup] = useState<WebhookSetup | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setSetup(null);
    setError(null);
    requestJson(`${basePath}/${integration.id}/jira_webhook`, { method: 'GET' })
      .then((result) => !cancelled && setSetup(result as WebhookSetup))
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not load the webhook settings'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  return (
    <Modal opened={!!integration} onClose={onClose} title="Jira webhook" size="lg">
      <Stack gap="sm">
        <Text size="sm">
          Tracker triggers need Jira to send its events here. A Jira admin opens <b>Settings → System → WebHooks</b>,
          creates a webhook with these values, and saves it.
        </Text>
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {!setup && !error && <Loader size="sm" aria-label="Loading webhook settings" />}
        {setup && (
          <>
            <Stack gap={2}>
              <Text size="xs" fw={600}>
                URL
              </Text>
              <Group gap={4} wrap="nowrap">
                <Code style={{ wordBreak: 'break-all' }}>{setup.url}</Code>
                <CopyValue label="URL" value={setup.url} />
              </Group>
            </Stack>
            <Stack gap={2}>
              <Text size="xs" fw={600}>
                Secret
              </Text>
              <Group gap={4} wrap="nowrap">
                <PasswordInput value={setup.secret} readOnly aria-label="Secret" style={{ flex: 1 }} />
                <CopyValue label="Secret" value={setup.secret} />
              </Group>
            </Stack>
            {setup.jql && (
              <Stack gap={2}>
                <Text size="xs" fw={600}>
                  JQL
                </Text>
                <Group gap={4} wrap="nowrap">
                  <Code>{setup.jql}</Code>
                  <CopyValue label="JQL" value={setup.jql} />
                </Group>
              </Stack>
            )}
            <Text size="sm">Events: {setup.events.join(', ')}.</Text>
            <Text size="xs" c="dimmed">
              {setup.lastEventAt
                ? `Last event received ${new Date(setup.lastEventAt).toLocaleString()}.`
                : 'No event received yet.'}
            </Text>
          </>
        )}
        <Group justify="flex-end">
          <Button onClick={onClose}>Done</Button>
        </Group>
      </Stack>
    </Modal>
  );
};
