import { Head, router } from '@inertiajs/react';
import { Anchor, Button, Paper, Stack, Text, TextInput, Title } from '@mantine/core';
import { useState } from 'react';

import { loginPath, passwordResetsPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface PageProps {
  email?: string | null;
  /** The request went through. Says nothing about whether the address has an account. */
  sent: boolean;
  [key: string]: unknown;
}

export default function PasswordResetRequestPage({ email: prefill, sent }: PageProps) {
  const [email, setEmail] = useState(prefill ?? '');
  const [processing, setProcessing] = useState(false);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    setProcessing(true);
    router.post(passwordResetsPath(), { email: email.trim() }, { onFinish: () => setProcessing(false) });
  };

  return (
    <PageShell variant="centered">
      <Head title="Reset your password" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          {sent ? (
            <>
              <Title order={3}>Check your email</Title>
              <Text size="sm" c="dimmed">
                If that address belongs to an account that signs in with a password, a link to choose a new one is on
                its way. It works once and expires in an hour.
              </Text>
            </>
          ) : (
            <>
              <Title order={3}>Reset your password</Title>
              <Text size="sm" c="dimmed">
                Enter the address you sign in with, and we will email you a link to choose a new password.
              </Text>
              <form onSubmit={submit}>
                <Stack gap="md">
                  <TextInput
                    label="Email"
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.currentTarget.value)}
                    placeholder="you@company.com"
                    autoComplete="username"
                    autoFocus
                    required
                  />
                  <Button type="submit" fullWidth size="lg" loading={processing}>
                    Send reset link
                  </Button>
                </Stack>
              </form>
            </>
          )}
          <Anchor href={loginPath()} size="sm">
            Back to sign in
          </Anchor>
        </Stack>
      </Paper>
    </PageShell>
  );
}
