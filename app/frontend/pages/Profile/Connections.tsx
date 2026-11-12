import { Head, router, usePage } from '@inertiajs/react';
import { Avatar, Button, Card, Group, Stack, Switch, Table, Text, Title } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconBrandGithub } from '@tabler/icons-react';
import { useState } from 'react';

import type { ActAsConsent, UserConnection } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { apiMutate } from 'shared/lib/apiFetch';
import { postNavigate } from 'shared/lib/postNavigate';
import {
  actAsConsentsProfilePath,
  connectionsProfilePath,
  disconnectProfilePath,
  oauthAuthorizePath,
} from 'shared/routes';
import { type SharedProps } from 'shared/ui';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { ProfileTabs } from './ProfileTabs';

interface PageProps {
  /** Whether this installation has the GitHub App's client id and secret. */
  available: boolean;
  github: UserConnection | null;
  consents: ActAsConsent[];
  [key: string]: unknown;
}

type Switchable = 'inOwnTasks' | 'inOthersTasks';

const GITHUB = 'github';

function GithubCard({
  available,
  github,
  userId,
}: {
  available: boolean;
  github: UserConnection | null;
  userId: number | undefined;
}) {
  const [connecting, setConnecting] = useState(false);

  const connect = () => {
    if (userId === undefined) return;
    setConnecting(true);
    // The connect hands the browser over to github.com, so it is a top-level POST.
    postNavigate(oauthAuthorizePath(GITHUB), {
      owner_type: 'User',
      owner_id: String(userId),
      return_to: connectionsProfilePath(),
    });
  };

  const confirmDisconnect = () =>
    modals.openConfirmModal({
      title: 'Disconnect GitHub',
      children: (
        <Text size="sm">
          Agents can no longer act as you on GitHub, and the permissions you set for each project are removed.
        </Text>
      ),
      labels: { confirm: 'Disconnect', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(disconnectProfilePath(GITHUB)),
    });

  return (
    <Card p={24}>
      <Group justify="space-between" wrap="nowrap">
        <Group gap="md" wrap="nowrap">
          {github?.avatarUrl ? <Avatar src={github.avatarUrl} radius="xl" /> : <IconBrandGithub size={32} />}
          <div>
            <Title order={4}>GitHub</Title>
            <Text fz={14} c="dimmed">
              {github?.login
                ? `${github.name ?? github.login} (@${github.login})`
                : 'Let agents push and open pull requests as you.'}
            </Text>
          </div>
        </Group>
        <Group gap="sm" wrap="nowrap">
          {github && (
            <StatusBadge tone={github.status === 'connected' ? 'success' : 'warning'}>
              {github.status === 'connected' ? 'Connected' : 'Needs reconnect'}
            </StatusBadge>
          )}
          {available && github?.status !== 'connected' && (
            <Button size="compact-sm" loading={connecting} onClick={connect}>
              {github ? 'Reconnect' : 'Connect GitHub'}
            </Button>
          )}
          {github && (
            <Button size="compact-sm" variant="default" color="red" onClick={confirmDisconnect}>
              Disconnect
            </Button>
          )}
        </Group>
      </Group>
      {!available && (
        <Text fz={13} c="dimmed" mt="md">
          This installation has not configured the GitHub App&apos;s client id and secret, so accounts cannot be
          connected.
        </Text>
      )}
    </Card>
  );
}

function ConsentsCard({ consents }: { consents: ActAsConsent[] }) {
  const [saving, setSaving] = useState<string | null>(null);

  const change = async (consent: ActAsConsent, field: Switchable, value: boolean) => {
    setSaving(`${consent.projectId}:${field}`);
    const saved = await apiMutate(actAsConsentsProfilePath(), {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: consent.projectId, provider: GITHUB, [field]: value }),
    });
    setSaving(null);
    if (saved) router.reload({ only: ['consents'] });
  };

  return (
    <Card p={24}>
      <Title order={4} mb={4}>
        What agents may do as you
      </Title>
      <Text fz={14} c="dimmed" mb="md">
        Decide per project. Both are off until you turn them on.
      </Text>
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
                      aria-label={`${field === 'inOwnTasks' ? 'In my tasks' : "In tasks that aren't mine"} — ${consent.projectName}`}
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

export default function Connections({ available, github, consents }: PageProps) {
  const { currentUser } = usePage<SharedProps>().props;

  return (
    <AuthLayout>
      <Stack gap="lg">
        <Head title="Connected accounts" />
        <ProfileTabs active="connections" />
        <GithubCard available={available} github={github} userId={currentUser?.id} />
        {github && <ConsentsCard consents={consents} />}
      </Stack>
    </AuthLayout>
  );
}
