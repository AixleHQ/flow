import { router } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Button,
  Checkbox,
  Group,
  Loader,
  Modal,
  MultiSelect,
  PasswordInput,
  SegmentedControl,
  Stack,
  Text,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

import { requestJson as requestTrackerJson } from './requestJson';

export interface LinearProps {
  oauthEnabled: boolean;
}

interface LinearTeam {
  id: string;
  key: string;
  name: string;
}

interface Inspection {
  identity: { id: string; name: string };
  organization: { id: string; name: string };
  teams: LinearTeam[];
}

const DOCS_URL = '/docs/linear';

const requestJson = (url: string, init: RequestInit = {}) =>
  requestTrackerJson(url, init, 'Linear rejected the request');

const teamOptions = (teams: LinearTeam[]) => teams.map((t) => ({ value: t.id, label: `${t.name} (${t.key})` }));

interface ConnectProps {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  linear: LinearProps;
}

export const LinearConnectModal = ({ opened, onClose, basePath, linear }: ConnectProps) => {
  const [mode, setMode] = useState<'oauth' | 'api_key'>(linear.oauthEnabled ? 'oauth' : 'api_key');
  const [apiKey, setApiKey] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [teamIds, setTeamIds] = useState<string[]>([]);
  const [dedicated, setDedicated] = useState(false);
  const [checking, setChecking] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => {
    onClose();
    setApiKey('');
    setInspection(null);
    setTeamIds([]);
    setDedicated(false);
    setError(null);
  }, [onClose]);

  const check = useCallback(async () => {
    setError(null);
    setChecking(true);
    try {
      const result = (await requestJson(`${basePath}/linear_inspect`, {
        method: 'POST',
        body: JSON.stringify({ api_key: apiKey.trim() }),
      })) as Inspection;
      setInspection(result);
      setTeamIds([]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reach Linear');
    } finally {
      setChecking(false);
    }
  }, [apiKey, basePath]);

  const connect = useCallback(() => {
    setConnecting(true);
    router.post(
      basePath,
      { provider: 'linear', apiKey: apiKey.trim(), teamIds, dedicatedIdentity: dedicated },
      {
        preserveScroll: true,
        onSuccess: close,
        onError: () => notifications.show({ message: 'Failed to connect Linear', color: 'red' }),
        onFinish: () => setConnecting(false),
      },
    );
  }, [apiKey, basePath, close, dedicated, teamIds]);

  return (
    <Modal opened={opened} onClose={close} title="Connect Linear" size="lg">
      <Stack gap="md">
        {linear.oauthEnabled && (
          <SegmentedControl
            value={mode}
            onChange={(value) => setMode(value as typeof mode)}
            data={[
              { label: 'Aixle app', value: 'oauth' },
              { label: 'API key', value: 'api_key' },
            ]}
          />
        )}

        {mode === 'oauth' ? (
          <>
            <Text size="sm">
              A Linear workspace admin installs Aixle&apos;s Linear app, then you choose which teams to connect. Aixle
              acts as the app itself, so its changes never appear as anyone&apos;s, and the app delivers the
              workspace&apos;s events on its own.
            </Text>
            <Group justify="flex-end">
              <Button variant="default" onClick={close}>
                Cancel
              </Button>
              <Button component="a" href={`${basePath}/linear_oauth_start`}>
                Install Aixle&apos;s Linear app
              </Button>
            </Group>
          </>
        ) : (
          <>
            <Text size="sm" c="dimmed">
              Create a personal API key in Linear under Settings → Security &amp; access, best of an account kept for
              Aixle: Aixle acts as the key&apos;s owner. Tracker triggers need Linear to send events, and only a
              workspace admin&apos;s key can register the webhooks — with another key the tools work but triggers do not
              fire. See the <Anchor href={DOCS_URL}>Linear guide</Anchor>.
            </Text>
            <PasswordInput label="API key" value={apiKey} onChange={(e) => setApiKey(e.currentTarget.value)} />
            {error && (
              <Alert color="red" icon={<IconAlertCircle size={16} />}>
                {error}
              </Alert>
            )}
            {inspection && (
              <>
                <Alert color="green" icon={<IconCheck size={16} />}>
                  Signed in to {inspection.organization.name} as {inspection.identity.name}.
                </Alert>
                <MultiSelect
                  label="Linear teams"
                  description="Each one becomes a tracker in this project."
                  data={teamOptions(inspection.teams)}
                  value={teamIds}
                  onChange={setTeamIds}
                  searchable
                />
                <Checkbox
                  label="This Linear account is kept for Aixle"
                  description="Then Aixle recognises its own changes and @mentions of the account. Leave it off for a personal account."
                  checked={dedicated}
                  onChange={(e) => setDedicated(e.currentTarget.checked)}
                />
              </>
            )}
            <Group justify="flex-end">
              <Button variant="default" onClick={close}>
                Cancel
              </Button>
              {inspection ? (
                <Button onClick={connect} loading={connecting} disabled={teamIds.length === 0}>
                  Connect
                </Button>
              ) : (
                <Button onClick={check} loading={checking} disabled={!apiKey.trim()}>
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

interface TeamsProps {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

// Finishes a connection made through the Linear app, or changes which teams a
// connection covers.
export const LinearTeamsModal = ({ integration, onClose, basePath }: TeamsProps) => {
  const [teams, setTeams] = useState<LinearTeam[] | null>(null);
  const [teamIds, setTeamIds] = useState<string[]>([]);
  const [dedicated, setDedicated] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const apiKeyMode = integration?.linearAuthMode === 'api_key';

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setTeams(null);
    setError(null);
    setTeamIds(integration.linearTeams.map((t) => t.id));
    setDedicated(integration.linearDedicatedIdentity);
    requestJson(`${basePath}/${integration.id}/linear_teams`, { method: 'GET' })
      .then((result) => !cancelled && setTeams(result.teams as LinearTeam[]))
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not list the Linear teams'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  const save = useCallback(() => {
    if (!integration) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      { teamIds, ...(apiKeyMode ? { dedicatedIdentity: dedicated } : {}) },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to save the Linear teams', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [apiKeyMode, basePath, dedicated, integration, onClose, teamIds]);

  return (
    <Modal opened={!!integration} onClose={onClose} title="Linear teams" size="lg">
      <Stack gap="md">
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {teams === null && !error && <Loader size="sm" aria-label="Loading teams" />}
        {teams && (
          <MultiSelect
            label="Linear teams"
            description="Each one becomes a tracker in this project. A team you remove is detached."
            data={teamOptions(teams)}
            value={teamIds}
            onChange={setTeamIds}
            searchable
          />
        )}
        {apiKeyMode && (
          <Checkbox
            label="This Linear account is kept for Aixle"
            description="Then Aixle recognises its own changes and @mentions of the account. Leave it off for a personal account."
            checked={dedicated}
            onChange={(e) => setDedicated(e.currentTarget.checked)}
          />
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={save} loading={saving} disabled={!teams || teamIds.length === 0}>
            Save
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
