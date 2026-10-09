import { Head, router } from '@inertiajs/react';
import { Badge, Button, Card, Group, Paper, Stack, Text, TextInput, Title } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { formatDateMedium } from 'shared/lib/formatDate';
import { createCredential, isSupported } from 'shared/lib/webauthn';
import {
  confirmTotpPath,
  passkeyOptionsPath,
  passkeyPath,
  passkeysPath,
  signInMethodPath,
  signInMethodsPath,
  totpPath,
} from 'shared/routes';

import { PasswordSection, type PasswordState } from './PasswordSection';
import { ProfileTabs } from './ProfileTabs';

interface SignInMethod {
  id: number;
  kind: string;
  name: string;
  email: string | null;
  lastUsedAt: string | null;
  removable: boolean;
  /** Why Remove would be refused, said before the person tries. */
  removalRefusal: string | null;
}

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
  signInMethods: SignInMethod[];
  /** Redirect providers this person may link: offered here and accepted by a company of theirs. */
  linkableKinds: string[];
  password: PasswordState;
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

const LINKABLE_LABELS: Record<string, string> = { google: 'Google', microsoft: 'Microsoft' };

// A real form POST, not router.post: linking ends at the provider's own page,
// and an Inertia XHR cannot follow a cross-origin redirect. POST rather than a
// link for CVE-2015-9284. The kind travels in the body; the server keeps the
// intent to link in the session.
const LinkMethodButton = ({ kind }: { kind: string }) => {
  const label = `Link ${LINKABLE_LABELS[kind] ?? kind}`;
  return (
    <form method="post" action={signInMethodsPath()} aria-label={label}>
      <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
      <input type="hidden" name="kind" value={kind} />
      <Button type="submit" size="compact-sm" variant="default">
        {label}
      </Button>
    </form>
  );
};

function SignInMethodsSection({ methods, linkableKinds }: { methods: SignInMethod[]; linkableKinds: string[] }) {
  return (
    <Paper p="md" radius="md" withBorder>
      <Stack gap="sm">
        <Group justify="space-between">
          <Title order={4}>Sign-in methods</Title>
          {linkableKinds.length > 0 && (
            <Group gap="xs">
              {linkableKinds.map((kind) => (
                <LinkMethodButton key={kind} kind={kind} />
              ))}
            </Group>
          )}
        </Group>
        <Text size="sm" c="dimmed">
          The ways you can sign in to this account. A Google or Microsoft account is added only when you sign in to it
          from here — never because its address matches yours.
        </Text>
        {methods.length === 0 && <Text size="sm">No sign-in methods recorded yet.</Text>}
        {methods.map((method) => (
          <Stack key={method.id} gap={2}>
            <Group justify="space-between" wrap="nowrap">
              <div>
                <Text size="sm" fw={500}>
                  {method.name}
                </Text>
                <Text size="xs" c="dimmed">
                  {method.email ?? 'No address'} ·{' '}
                  {method.lastUsedAt ? `last used ${formatDateMedium(method.lastUsedAt)}` : 'not used yet'}
                </Text>
              </div>
              {method.removable && (
                <Button
                  size="compact-xs"
                  variant="subtle"
                  color="red"
                  disabled={method.removalRefusal !== null}
                  aria-label={`Remove ${method.name} (${method.email ?? 'no address'})`}
                  onClick={() => router.delete(signInMethodPath(method.id))}
                >
                  Remove
                </Button>
              )}
            </Group>
            {method.removable && method.removalRefusal && (
              <Text size="xs" c="dimmed">
                {method.removalRefusal}
              </Text>
            )}
          </Stack>
        ))}
      </Stack>
    </Paper>
  );
}

export default function Security({
  signInMethods,
  linkableKinds,
  password,
  passkeys,
  totpEnabled,
  sessions,
}: PageProps) {
  const [busy, setBusy] = useState(false);
  const [totpSetup, setTotpSetup] = useState<{ secret: string; qrCode: string | null } | null>(null);
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
    // A plain `render json:` — unlike an Inertia response, its keys are not
    // camelized, so they are read as the server spells them.
    const { ok, data } = await postJson(totpPath(), {});
    if (ok) setTotpSetup({ secret: data.secret, qrCode: data.qr_code ?? null });
  };

  return (
    <AuthLayout>
      <Stack gap="lg">
        <Head title="Security" />
        <ProfileTabs active="security" />

        <SignInMethodsSection methods={signInMethods} linkableKinds={linkableKinds} />

        <PasswordSection password={password} />

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
            {totpSetup && !totpEnabled && (
              <Stack gap="xs">
                <Text size="sm">
                  Scan this with your authenticator app — Google Authenticator, 1Password, Authy — then enter the code
                  it shows.
                </Text>
                {totpSetup.qrCode && (
                  <Card withBorder padding={0} w={180}>
                    <img src={totpSetup.qrCode} alt="QR code for your authenticator app" width={180} height={180} />
                  </Card>
                )}
                <Text size="sm" c="dimmed">
                  Cannot scan? Type this into the app instead:
                </Text>
                <Card withBorder padding="xs">
                  <Text ff="monospace">{totpSetup.secret}</Text>
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
    </AuthLayout>
  );
}
