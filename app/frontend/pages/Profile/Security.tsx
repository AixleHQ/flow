import { Head, router } from '@inertiajs/react';
import { Badge, Button, Card, Group, Paper, Stack, Text, TextInput, Title } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';

import { createCredential, isSupported } from 'shared/lib/webauthn';
import { confirmTotpPath, passkeyOptionsPath, passkeyPath, passkeysPath, totpPath } from 'shared/routes';

import { ProfileTabs } from './ProfileTabs';

interface Passkey {
  id: number;
  name: string;
  lastUsedAt: string | null;
  created_at: string;
}

interface SessionRow {
  id: number;
  ip: string | null;
  userAgent: string | null;
  lastSeenAt: string | null;
  current: boolean;
}

interface PageProps {
  passkeys: Passkey[];
  totpEnabled: boolean;
  sessions: SessionRow[];
  [key: string]: unknown;
}

function getCsrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

async function postJson(url: string, body: unknown) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrfToken() },
    body: JSON.stringify(body ?? {}),
  });
  return { ok: response.ok, data: await response.json().catch(() => ({})) };
}

export default function Security({ passkeys, totpEnabled, sessions }: PageProps) {
  const [busy, setBusy] = useState(false);
  const [totpSecret, setTotpSecret] = useState<string | null>(null);
  const [code, setCode] = useState('');

  const addPasskey = async () => {
    setBusy(true);
    try {
      const { ok, data } = await postJson(passkeyOptionsPath(), {});
      if (!ok) throw new Error('options');
      const credential = await createCredential(data);
      const result = await postJson(passkeysPath(), { credential });
      if (!result.ok) throw new Error('rejected');
      router.reload();
    } catch {
      notifications.show({ color: 'red', message: 'That passkey could not be added.' });
    } finally {
      setBusy(false);
    }
  };

  const startTotp = async () => {
    const { ok, data } = await postJson(totpPath(), {});
    if (ok) setTotpSecret(data.secret);
  };

  return (
    <Stack gap="lg">
      <Head title="Security" />
      <ProfileTabs active="security" />

      <Paper p="md" radius="md" withBorder>
        <Stack gap="sm">
          <Group justify="space-between">
            <Title order={4}>Passkeys</Title>
            <Button size="compact-sm" onClick={addPasskey} loading={busy} disabled={!isSupported()}>
              Add a passkey
            </Button>
          </Group>
          <Text size="sm" c="dimmed">
            A passkey lives on your device and works in every workspace you belong to. Only you can add or remove one.
          </Text>
          {passkeys.length === 0 && <Text size="sm">No passkeys yet.</Text>}
          {passkeys.map((passkey) => (
            <Group key={passkey.id} justify="space-between">
              <Text size="sm">{passkey.name}</Text>
              <Button
                size="compact-xs"
                variant="subtle"
                color="red"
                onClick={() => router.delete(passkeyPath(passkey.id))}
              >
                Remove
              </Button>
            </Group>
          ))}
        </Stack>
      </Paper>

      <Paper p="md" radius="md" withBorder>
        <Stack gap="sm">
          <Group justify="space-between">
            <Title order={4}>Authentication codes</Title>
            {totpEnabled ? (
              <Badge color="green">On</Badge>
            ) : (
              <Button size="compact-sm" onClick={startTotp}>
                Set up
              </Button>
            )}
          </Group>
          {totpSecret && !totpEnabled && (
            <Stack gap="xs">
              <Text size="sm">Add this secret to your authenticator app, then enter the code it shows.</Text>
              <Card withBorder padding="xs">
                <Text ff="monospace">{totpSecret}</Text>
              </Card>
              <Group>
                <TextInput
                  placeholder="123456"
                  value={code}
                  inputMode="numeric"
                  onChange={(event) => setCode(event.currentTarget.value)}
                />
                <Button onClick={() => router.post(confirmTotpPath(), { code })}>Confirm</Button>
              </Group>
            </Stack>
          )}
          {totpEnabled && (
            <Button size="compact-sm" variant="subtle" color="red" onClick={() => router.delete(totpPath())}>
              Turn off
            </Button>
          )}
        </Stack>
      </Paper>

      <Paper p="md" radius="md" withBorder>
        <Stack gap="sm">
          <Title order={4}>Signed in on</Title>
          {sessions.map((session) => (
            <Group key={session.id} justify="space-between">
              <Text size="sm">
                {session.ip ?? 'unknown address'} — {session.userAgent?.slice(0, 60) ?? 'unknown device'}
              </Text>
              {session.current && <Badge size="sm">This device</Badge>}
            </Group>
          ))}
        </Stack>
      </Paper>
    </Stack>
  );
}
