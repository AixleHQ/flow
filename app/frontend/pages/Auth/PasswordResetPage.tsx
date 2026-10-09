import { Head, router } from '@inertiajs/react';
import { Anchor, Button, Paper, PasswordInput, Stack, Text, Title } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver } from 'mantine-form-zod-resolver';
import { useState } from 'react';
import { z } from 'zod';

import { loginPath, newPasswordResetPath, passwordResetPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface PageProps {
  token: string;
  /** False once the link is spent, expired, or was never one of ours. */
  valid: boolean;
  minLength: number;
  [key: string]: unknown;
}

const buildSchema = (minLength: number) =>
  z
    .object({
      password: z.string().min(1, 'Enter a new password.').min(minLength, `Use at least ${minLength} characters.`),
      passwordConfirmation: z.string(),
    })
    .refine((values) => values.password === values.passwordConfirmation, {
      message: 'The passwords do not match.',
      path: ['passwordConfirmation'],
    });

type FormValues = z.infer<ReturnType<typeof buildSchema>>;

function SpentLink() {
  return (
    <>
      <Title order={3}>This link no longer works</Title>
      <Text size="sm" c="dimmed">
        A reset link works once and expires after an hour. Ask for a new one and use the latest email.
      </Text>
      <Button component="a" href={newPasswordResetPath()} fullWidth size="lg">
        Send a new link
      </Button>
    </>
  );
}

export default function PasswordResetPage({ token, valid, minLength }: PageProps) {
  const [saving, setSaving] = useState(false);
  const form = useForm<FormValues>({
    initialValues: { password: '', passwordConfirmation: '' },
    validate: zod4Resolver(buildSchema(minLength)),
  });

  // The token is a signed message in standard base64, so it can carry a "/".
  const save = (values: FormValues) => {
    setSaving(true);
    router.patch(passwordResetPath(encodeURIComponent(token)), values, {
      onError: (errors) => form.setErrors(errors),
      onFinish: () => setSaving(false),
    });
  };

  return (
    <PageShell variant="centered">
      <Head title="Choose a new password" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          {valid ? (
            <>
              <Title order={3}>Choose a new password</Title>
              <Text size="sm" c="dimmed">
                Saving it signs you out everywhere else you are signed in.
              </Text>
              <form onSubmit={form.onSubmit(save)} aria-label="Choose a new password">
                <Stack gap="md">
                  <PasswordInput
                    label="New password"
                    description={`At least ${minLength} characters.`}
                    autoComplete="new-password"
                    autoFocus
                    {...form.getInputProps('password')}
                  />
                  <PasswordInput
                    label="Confirm password"
                    autoComplete="new-password"
                    {...form.getInputProps('passwordConfirmation')}
                  />
                  <Button type="submit" fullWidth size="lg" loading={saving}>
                    Save password
                  </Button>
                </Stack>
              </form>
            </>
          ) : (
            <SpentLink />
          )}
          <Anchor href={loginPath()} size="sm">
            Back to sign in
          </Anchor>
        </Stack>
      </Paper>
    </PageShell>
  );
}
