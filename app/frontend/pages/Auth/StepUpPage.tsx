import { Head, router, useForm } from '@inertiajs/react';
import { Alert, Button, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { useState } from 'react';

import { stepUpPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface AllowedMethod {
  kind: string;
  name: string;
  /** Where to POST to start a redirect method. Absent for the password form. */
  startPath?: string | null;
}

function getCsrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

// POST, never a GET link — the same CSRF reasoning as the login buttons.
function RedirectMethodButton({ method }: { method: AllowedMethod }) {
  return (
    <form method="post" action={method.startPath ?? ''}>
      <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
      <Button type="submit" variant="default" fullWidth>
        Continue with {method.name}
      </Button>
    </form>
  );
}

interface PageProps {
  companyName: string;
  methods: AllowedMethod[];
  error?: string;
  [key: string]: unknown;
}

const ERROR_MESSAGES: Record<string, string> = {
  invalid_credentials: 'That password did not match. Please try again.',
  method_not_allowed: 'This workspace no longer accepts that sign-in method.',
};

export default function StepUpPage({ companyName, methods, error }: PageProps) {
  const { data, setData } = useForm({ password: '', code: '' });
  const [processing, setProcessing] = useState(false);
  const passwordAllowed = methods.some((method) => method.kind === 'password');
  const redirectMethods = methods.filter((method) => method.startPath);
  const totpAllowed = methods.some((method) => method.kind === 'totp');

  // The payload is built here rather than via setData-then-post: a React state
  // update is asynchronous, so posting straight after setData sends the PREVIOUS
  // kind — which made the code form submit as a password attempt with an empty
  // password, and always fail.
  const submit = (kind: 'password' | 'totp') => (event: React.FormEvent) => {
    event.preventDefault();
    setProcessing(true);
    router.post(
      stepUpPath(),
      { step_up: { kind, password: data.password, code: data.code } },
      { onFinish: () => setProcessing(false) },
    );
  };

  return (
    <PageShell>
      <Head title="Confirm it's you" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo />
          <Title order={3}>Confirm it&apos;s you</Title>
          <Text size="sm" c="dimmed">
            {companyName} accepts {methods.map((method) => method.name).join(', ') || 'no sign-in method'} for entry.
            Confirm with one of them to continue — you stay signed in either way.
          </Text>

          {error && <Alert color="red">{ERROR_MESSAGES[error] ?? 'Please try again.'}</Alert>}

          {redirectMethods.length > 0 && (
            <Stack gap="xs">
              {redirectMethods.map((method) => (
                <RedirectMethodButton key={method.kind} method={method} />
              ))}
            </Stack>
          )}

          {passwordAllowed ? (
            <form onSubmit={submit('password')}>
              <Stack gap="sm">
                <PasswordInput
                  label="Password"
                  value={data.password}
                  onChange={(event) => setData('password', event.currentTarget.value)}
                  autoFocus
                  required
                />
                <Button type="submit" loading={processing} fullWidth>
                  Confirm
                </Button>
              </Stack>
            </form>
          ) : null}

          {totpAllowed && (
            <form onSubmit={submit('totp')}>
              <Stack gap="sm">
                <TextInput
                  label="Authentication code"
                  description="The six-digit code from your authenticator app"
                  inputMode="numeric"
                  value={data.code}
                  onChange={(event) => setData('code', event.currentTarget.value)}
                  required
                />
                <Button type="submit" loading={processing} fullWidth>
                  Confirm code
                </Button>
              </Stack>
            </form>
          )}

          {!passwordAllowed && !totpAllowed && redirectMethods.length === 0 && (
            <Alert color="yellow">Ask an administrator of {companyName} to enable a sign-in method you can use.</Alert>
          )}
        </Stack>
      </Paper>
    </PageShell>
  );
}
