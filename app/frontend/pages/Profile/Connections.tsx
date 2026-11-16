import { Head, router, usePage } from '@inertiajs/react';
import { Avatar, Button, Card, Group, Stack, Switch, Table, Text, Title } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconBrandGithub, IconBrandGitlab } from '@tabler/icons-react';
import { useState } from 'react';

import type { ActAsConsent, UserConnection } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { apiMutate } from 'shared/lib/apiFetch';
import { postNavigate } from 'shared/lib/postNavigate';
import {
  oauthAuthorizePath,
  profileConnectionActAsConsentPath,
  profileConnectionPath,
  profileConnectionsPath,
} from 'shared/routes';
import { type SharedProps } from 'shared/ui';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { ProfileTabs } from './ProfileTabs';

type Provider = 'github' | 'gitlab';

interface PageProps {
  /** Whether this installation has each provider's OAuth client id and secret. */
  available: Record<Provider, boolean>;
  connections: Record<Provider, UserConnection | null>;
  consents: Record<Provider, ActAsConsent[]>;
  [key: string]: unknown;
}

type Switchable = 'inOwnTasks' | 'inOthersTasks';

const PROVIDERS: Provider[] = ['github', 'gitlab'];

const PROVIDER_INFO: Record<
  Provider,
  {
    name: string;
    icon: typeof IconBrandGithub;
    pitch: string;
    notConfigured: string;
    disconnectNote: string;
    consentWarning?: string;
  }
> = {
  github: {
    name: 'GitHub',
    icon: IconBrandGithub,
    pitch: 'Let agents push and open pull requests as you.',
    notConfigured:
      "This installation has not configured the GitHub App's client id and secret, so accounts cannot be connected.",
    disconnectNote:
      'Agents can no longer act as you on GitHub, and the permissions you set for each project are removed.',
  },
  gitlab: {
    name: 'GitLab',
    icon: IconBrandGitlab,
    pitch: 'Let agents push and open merge requests as you.',
    notConfigured:
      "This installation has not configured GitLab's OAuth app (client id and secret), so accounts cannot be connected.",
    disconnectNote:
      'Agents can no longer act as you on GitLab, and the permissions you set for each project are removed.',
    consentWarning:
      "A token handed out in a project can do anything you can on GitLab, not only in that project's repositories.",
  },
};

function ProviderCard({
  provider,
  available,
  connection: account,
  userId,
}: {
  provider: Provider;
  available: boolean;
  connection: UserConnection | null;
  userId: number | undefined;
}) {
  const info = PROVIDER_INFO[provider];
  const Icon = info.icon;
  const [connecting, setConnecting] = useState(false);

  const connect = () => {
    if (userId === undefined) return;
    setConnecting(true);
    // The connect hands the browser over to the provider, so it is a top-level POST.
    postNavigate(oauthAuthorizePath(provider), {
      owner_type: 'User',
      owner_id: String(userId),
      return_to: profileConnectionsPath(),
    });
  };

  const confirmDisconnect = () =>
    modals.openConfirmModal({
      title: `Disconnect ${info.name}`,
      children: <Text size="sm">{info.disconnectNote}</Text>,
      labels: { confirm: 'Disconnect', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(profileConnectionPath(provider)),
    });

  return (
    <Card p={24}>
      <Group justify="space-between" wrap="nowrap">
        <Group gap="md" wrap="nowrap">
          {account?.avatarUrl ? <Avatar src={account.avatarUrl} radius="xl" /> : <Icon size={32} />}
          <div>
            <Title order={4}>{info.name}</Title>
            <Text fz={14} c="dimmed">
              {account?.login ? `${account.name ?? account.login} (@${account.login})` : info.pitch}
            </Text>
          </div>
        </Group>
        <Group gap="sm" wrap="nowrap">
          {account && (
            <StatusBadge tone={account.status === 'connected' ? 'success' : 'warning'}>
              {account.status === 'connected' ? 'Connected' : 'Needs reconnect'}
            </StatusBadge>
          )}
          {available && account?.status !== 'connected' && (
            <Button size="compact-sm" loading={connecting} onClick={connect}>
              {account ? `Reconnect ${info.name}` : `Connect ${info.name}`}
            </Button>
          )}
          {account && (
            <Button
              size="compact-sm"
              variant="default"
              color="red"
              aria-label={`Disconnect ${info.name}`}
              onClick={confirmDisconnect}
            >
              Disconnect
            </Button>
          )}
        </Group>
      </Group>
      {!available && (
        <Text fz={13} c="dimmed" mt="md">
          {info.notConfigured}
        </Text>
      )}
    </Card>
  );
}

function ConsentsCard({ provider, consents }: { provider: Provider; consents: ActAsConsent[] }) {
  const info = PROVIDER_INFO[provider];
  const [saving, setSaving] = useState<string | null>(null);

  const change = async (consent: ActAsConsent, field: Switchable, value: boolean) => {
    setSaving(`${consent.projectId}:${field}`);
    const saved = await apiMutate(profileConnectionActAsConsentPath(provider, consent.projectId), {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ [field]: value }),
    });
    setSaving(null);
    if (saved) router.reload({ only: ['consents'] });
  };

  return (
    <Card p={24}>
      <Title order={4} mb={4}>
        What agents may do as you on {info.name}
      </Title>
      <Text fz={14} c="dimmed" mb="md">
        Decide per project. Both are off until you turn them on.
      </Text>
      {info.consentWarning && (
        <Text fz={14} mb="md">
          {info.consentWarning}
        </Text>
      )}
      {consents.length === 0 ? (
        <Text fz={14}>You have no projects in this company yet.</Text>
      ) : (
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Project</Table.Th>
              <Table.Th>In my tasks</Table.Th>
              <Table.Th>In tasks that aren&apos;t mine</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {consents.map((consent) => (
              <Table.Tr key={consent.projectId}>
                <Table.Td>{consent.projectName}</Table.Td>
                {(['inOwnTasks', 'inOthersTasks'] as const).map((field) => (
                  <Table.Td key={field}>
                    <Switch
                      aria-label={`${info.name}: ${field === 'inOwnTasks' ? 'In my tasks' : "In tasks that aren't mine"} — ${consent.projectName}`}
                      checked={consent[field]}
                      disabled={saving === `${consent.projectId}:${field}`}
                      onChange={(event) => change(consent, field, event.currentTarget.checked)}
                    />
                  </Table.Td>
                ))}
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
    </Card>
  );
}

export default function Connections({ available, connections, consents }: PageProps) {
  const { currentUser } = usePage<SharedProps>().props;

  return (
    <AuthLayout>
      <Stack gap="lg">
        <Head title="Connected accounts" />
        <ProfileTabs active="connections" />
        {PROVIDERS.map((provider) => (
          <ProviderCard
            key={provider}
            provider={provider}
            available={available[provider]}
            connection={connections[provider]}
            userId={currentUser?.id}
          />
        ))}
        {PROVIDERS.filter((provider) => connections[provider]).map((provider) => (
          <ConsentsCard key={provider} provider={provider} consents={consents[provider]} />
        ))}
      </Stack>
    </AuthLayout>
  );
}
