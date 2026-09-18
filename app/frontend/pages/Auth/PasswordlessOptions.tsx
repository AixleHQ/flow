import { router } from '@inertiajs/react';
import { Button, Stack } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';

import { getCredential, isSupported } from 'shared/lib/webauthn';
import { passkeyLoginOptionsPath, passkeyLoginPath, requestMagicLinkPath } from 'shared/routes';

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

interface Props {
  /** The address typed into the form, used for the emailed link. */
  email: string;
  methods: string[];
}

export const PasswordlessOptions = ({ email, methods }: Props) => {
  const [busy, setBusy] = useState(false);
  const passkeyOffered = methods.includes('passkey') && isSupported();
  const magicLinkOffered = methods.includes('magic_link');

  const signInWithPasskey = async () => {
    setBusy(true);
    try {
      const { ok, data } = await postJson(passkeyLoginOptionsPath(), {});
      if (!ok) throw new Error('options');

      const credential = await getCredential(data);
      const result = await postJson(passkeyLoginPath(), { credential });
      if (!result.ok) throw new Error('rejected');

      router.visit(result.data.redirect_to ?? '/');
    } catch {
      // A cancelled prompt is the common case and is not an error worth shouting
      // about; a genuine rejection deserves a word.
      notifications.show({ color: 'red', message: 'That passkey was not accepted.' });
    } finally {
      setBusy(false);
    }
  };

  if (!passkeyOffered && !magicLinkOffered) return null;

  return (
    <Stack gap="sm">
      {passkeyOffered && (
        <Button variant="default" fullWidth loading={busy} onClick={signInWithPasskey}>
          Sign in with a passkey
        </Button>
      )}
      {magicLinkOffered && (
        <Button
          variant="subtle"
          fullWidth
          disabled={!email}
          onClick={() => router.post(requestMagicLinkPath(), { email })}
        >
          Email me a sign-in link
        </Button>
      )}
    </Stack>
  );
};
